#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>

#define PLUGIN_VERSION "0.1.0"
#define MAX_BOUNDARY_NAME 64
#define MARKER_MODEL "sprites/blueglow1.vmt"

public Plugin myinfo =
{
    name = "SM Context Boundary Curator",
    author = "TF2R",
    description = "Captures named map-boundary polygons with a sniper rifle",
    version = PLUGIN_VERSION,
    url = "https://github.com/sunayadahal/sm-context-plugin"
};

ArrayList g_ActiveVertices[MAXPLAYERS + 1];
ArrayList g_ActiveMarkers[MAXPLAYERS + 1];
int g_CaptureRifle[MAXPLAYERS + 1];
bool g_Capturing[MAXPLAYERS + 1];

ArrayList g_BoundaryNames;
ArrayList g_BoundaryMaps;
ArrayList g_BoundaryOwners;
ArrayList g_BoundaryIds;
ArrayList g_BoundaryVertices;
int g_NextBoundaryId;

public void OnPluginStart()
{
    RegConsoleCmd("sm_bstart", Command_BStart, "Begin capturing a boundary polygon");
    RegConsoleCmd("sm_bstop", Command_BStop, "Finish the polygon: sm_bstop [name]");
    RegConsoleCmd("sm_bexport", Command_BExport, "Export a polygon: sm_bexport [name]");
    RegConsoleCmd("sm_bcancel", Command_BCancel, "Cancel the active polygon");
    RegConsoleCmd("sm_bundo", Command_BUndo, "Remove the most recent vertex");

    HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);

    g_BoundaryNames = new ArrayList(ByteCountToCells(MAX_BOUNDARY_NAME));
    g_BoundaryMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
    g_BoundaryOwners = new ArrayList();
    g_BoundaryIds = new ArrayList();
    g_BoundaryVertices = new ArrayList();

    for (int client = 1; client <= MaxClients; client++)
    {
        g_CaptureRifle[client] = INVALID_ENT_REFERENCE;
        if (IsClientInGame(client))
        {
            InitializeClient(client);
        }
    }
}

public void OnMapStart()
{
    PrecacheModel(MARKER_MODEL, true);
    ResetCompletedBoundaries();
    g_NextBoundaryId = 0;
}

public void OnMapEnd()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        ResetCapture(client, true);
    }
    ResetCompletedBoundaries();
}

public void OnClientPutInServer(int client)
{
    InitializeClient(client);
}

public void OnClientDisconnect(int client)
{
    ResetCapture(client, true);
    delete g_ActiveVertices[client];
    delete g_ActiveMarkers[client];
}

void InitializeClient(int client)
{
    delete g_ActiveVertices[client];
    delete g_ActiveMarkers[client];
    g_ActiveVertices[client] = new ArrayList(3);
    g_ActiveMarkers[client] = new ArrayList();
    g_Capturing[client] = false;
    g_CaptureRifle[client] = INVALID_ENT_REFERENCE;
}

public Action Command_BStart(int client, int args)
{
    if (!RequirePlayer(client))
    {
        return Plugin_Handled;
    }

    ResetCapture(client, true);
    g_Capturing[client] = true;
    GiveCaptureRifle(client);
    ReplyToCommand(client, "[SM Context] Boundary capture started. Shoot each polygon vertex, then use /bstop [name].");
    return Plugin_Handled;
}

public Action Command_BStop(int client, int args)
{
    if (!RequireCapture(client))
    {
        return Plugin_Handled;
    }

    int count = g_ActiveVertices[client].Length;
    if (count < 3)
    {
        ReplyToCommand(client, "[SM Context] A polygon needs at least 3 vertices; currently %d.", count);
        return Plugin_Handled;
    }

    int id = ++g_NextBoundaryId;
    char name[MAX_BOUNDARY_NAME];
    if (args > 0)
    {
        GetCmdArgString(name, sizeof(name));
        StripQuotes(name);
        TrimString(name);
    }
    if (name[0] == '\0')
    {
        IntToString(id, name, sizeof(name));
    }

    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));

    ArrayList vertices = g_ActiveVertices[client].Clone();
    g_BoundaryNames.PushString(name);
    g_BoundaryMaps.PushString(map);
    g_BoundaryOwners.Push(GetClientUserId(client));
    g_BoundaryIds.Push(id);
    g_BoundaryVertices.Push(view_as<int>(vertices));

    g_Capturing[client] = false;
    g_ActiveVertices[client].Clear();
    RemoveCaptureRifle(client);

    ReplyToCommand(client, "[SM Context] Stored boundary '%s' as %s:%d with %d vertices.", name, map, id, count);
    ReplyToCommand(client, "[SM Context] Use /bexport %s, or /bexport to export your latest boundary as %s:%d.", name, map, id);
    return Plugin_Handled;
}

public Action Command_BExport(int client, int args)
{
    if (!RequirePlayer(client))
    {
        return Plugin_Handled;
    }

    char requested[MAX_BOUNDARY_NAME];
    if (args > 0)
    {
        GetCmdArgString(requested, sizeof(requested));
        StripQuotes(requested);
        TrimString(requested);
    }

    char currentMap[PLATFORM_MAX_PATH];
    GetCurrentMap(currentMap, sizeof(currentMap));
    int index = FindBoundary(client, currentMap, requested);
    if (index == -1)
    {
        if (requested[0] == '\0')
        {
            ReplyToCommand(client, "[SM Context] You have no completed boundary on this map.");
        }
        else
        {
            ReplyToCommand(client, "[SM Context] Boundary '%s' was not found on this map.", requested);
        }
        return Plugin_Handled;
    }

    char path[PLATFORM_MAX_PATH];
    if (!ExportBoundary(index, requested, path, sizeof(path)))
    {
        ReplyToCommand(client, "[SM Context] Export failed; check the SourceMod error log.");
        return Plugin_Handled;
    }

    ReplyToCommand(client, "[SM Context] Exported boundary to %s", path);
    return Plugin_Handled;
}

public Action Command_BCancel(int client, int args)
{
    if (!RequireCapture(client))
    {
        return Plugin_Handled;
    }
    ResetCapture(client, true);
    ReplyToCommand(client, "[SM Context] Active boundary cancelled.");
    return Plugin_Handled;
}

public Action Command_BUndo(int client, int args)
{
    if (!RequireCapture(client))
    {
        return Plugin_Handled;
    }
    int length = g_ActiveVertices[client].Length;
    if (length == 0)
    {
        ReplyToCommand(client, "[SM Context] There are no vertices to undo.");
        return Plugin_Handled;
    }

    g_ActiveVertices[client].Erase(length - 1);
    int reference = g_ActiveMarkers[client].Get(g_ActiveMarkers[client].Length - 1);
    g_ActiveMarkers[client].Erase(g_ActiveMarkers[client].Length - 1);
    RemoveMarker(reference);
    ReplyToCommand(client, "[SM Context] Removed vertex %d.", length);
    return Plugin_Handled;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && g_Capturing[client])
    {
        CreateTimer(0.2, Timer_GiveCaptureRifle, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_GiveCaptureRifle(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsPlayerAlive(client) && g_Capturing[client])
    {
        GiveCaptureRifle(client);
    }
    return Plugin_Stop;
}

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !g_Capturing[client] || !IsPlayerAlive(client))
    {
        return;
    }

    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= MaxClients || weapon != EntRefToEntIndex(g_CaptureRifle[client]))
    {
        return;
    }

    CaptureImpact(client);
}

void CaptureImpact(int client)
{
    float origin[3], angles[3], impact[3];
    GetClientEyePosition(client, origin);
    GetClientEyeAngles(client, angles);

    Handle trace = TR_TraceRayFilterEx(origin, angles, MASK_SHOT, RayType_Infinite, TraceFilter_NoSelf, client);
    if (!TR_DidHit(trace))
    {
        delete trace;
        PrintToChat(client, "[SM Context] Shot did not hit a surface.");
        return;
    }

    TR_GetEndPosition(impact, trace);
    delete trace;
    g_ActiveVertices[client].PushArray(impact, 3);
    int marker = CreateVertexMarker(impact);
    g_ActiveMarkers[client].Push(marker == -1 ? INVALID_ENT_REFERENCE : EntIndexToEntRef(marker));
    PrintToChat(client, "[SM Context] Vertex %d: [%.2f, %.2f, %.2f]", g_ActiveVertices[client].Length, impact[0], impact[1], impact[2]);
}

public bool TraceFilter_NoSelf(int entity, int contentsMask, any client)
{
    return entity != client;
}

void GiveCaptureRifle(int client)
{
    RemoveCaptureRifle(client);
    int weapon = GivePlayerItem(client, "tf_weapon_sniperrifle");
    if (weapon == -1)
    {
        PrintToChat(client, "[SM Context] Could not create the capture rifle.");
        return;
    }
    SetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex", 14);
    EquipPlayerWeapon(client, weapon);
    g_CaptureRifle[client] = EntIndexToEntRef(weapon);
}

void RemoveCaptureRifle(int client)
{
    int weapon = EntRefToEntIndex(g_CaptureRifle[client]);
    if (weapon > MaxClients && IsValidEntity(weapon))
    {
        RemovePlayerItem(client, weapon);
        AcceptEntityInput(weapon, "Kill");
    }
    g_CaptureRifle[client] = INVALID_ENT_REFERENCE;
}

int CreateVertexMarker(const float position[3])
{
    int marker = CreateEntityByName("env_sprite");
    if (marker == -1)
    {
        return -1;
    }
    DispatchKeyValue(marker, "model", MARKER_MODEL);
    DispatchKeyValue(marker, "rendermode", "5");
    DispatchKeyValue(marker, "rendercolor", "255 190 40");
    DispatchKeyValue(marker, "renderamt", "230");
    DispatchKeyValue(marker, "scale", "0.22");
    DispatchSpawn(marker);
    TeleportEntity(marker, position, NULL_VECTOR, NULL_VECTOR);
    return marker;
}

void ResetCapture(int client, bool removeMarkers)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }
    g_Capturing[client] = false;
    RemoveCaptureRifle(client);
    if (g_ActiveVertices[client] != null)
    {
        g_ActiveVertices[client].Clear();
    }
    if (g_ActiveMarkers[client] != null)
    {
        if (removeMarkers)
        {
            for (int i = 0; i < g_ActiveMarkers[client].Length; i++)
            {
                RemoveMarker(g_ActiveMarkers[client].Get(i));
            }
        }
        g_ActiveMarkers[client].Clear();
    }
}

void RemoveMarker(int reference)
{
    int entity = EntRefToEntIndex(reference);
    if (entity > MaxClients && IsValidEntity(entity))
    {
        AcceptEntityInput(entity, "Kill");
    }
}

void ResetCompletedBoundaries()
{
    if (g_BoundaryVertices == null)
    {
        return;
    }
    for (int i = 0; i < g_BoundaryVertices.Length; i++)
    {
        ArrayList vertices = view_as<ArrayList>(g_BoundaryVertices.Get(i));
        delete vertices;
    }
    g_BoundaryNames.Clear();
    g_BoundaryMaps.Clear();
    g_BoundaryOwners.Clear();
    g_BoundaryIds.Clear();
    g_BoundaryVertices.Clear();
}

int FindBoundary(int client, const char[] map, const char[] requested)
{
    int userid = GetClientUserId(client);
    char candidateMap[PLATFORM_MAX_PATH], candidateName[MAX_BOUNDARY_NAME];
    for (int i = g_BoundaryNames.Length - 1; i >= 0; i--)
    {
        g_BoundaryMaps.GetString(i, candidateMap, sizeof(candidateMap));
        if (!StrEqual(candidateMap, map) || g_BoundaryOwners.Get(i) != userid)
        {
            continue;
        }
        if (requested[0] == '\0')
        {
            return i;
        }
        g_BoundaryNames.GetString(i, candidateName, sizeof(candidateName));
        if (StrEqual(candidateName, requested, false))
        {
            return i;
        }
    }
    return -1;
}

bool ExportBoundary(int index, const char[] requested, char[] outputPath, int outputPathLength)
{
    char map[PLATFORM_MAX_PATH], name[MAX_BOUNDARY_NAME], exportName[MAX_BOUNDARY_NAME * 2];
    g_BoundaryMaps.GetString(index, map, sizeof(map));
    g_BoundaryNames.GetString(index, name, sizeof(name));
    int id = g_BoundaryIds.Get(index);
    if (requested[0] == '\0')
    {
        Format(exportName, sizeof(exportName), "%s:%d", map, id);
    }
    else
    {
        strcopy(exportName, sizeof(exportName), requested);
    }

    char safeName[MAX_BOUNDARY_NAME * 2];
    SanitizeFilename(exportName, safeName, sizeof(safeName));
    char directory[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, directory, sizeof(directory), "data/sm-context-plugin");
    if (!DirExists(directory) && !CreateDirectory(directory, 511))
    {
        LogError("Unable to create export directory: %s", directory);
        return false;
    }
    Format(outputPath, outputPathLength, "%s/%s.json", directory, safeName);

    File file = OpenFile(outputPath, "w");
    if (file == null)
    {
        LogError("Unable to open export file: %s", outputPath);
        return false;
    }

    char escapedMap[PLATFORM_MAX_PATH * 2], escapedName[MAX_BOUNDARY_NAME * 2];
    char escapedExportName[MAX_BOUNDARY_NAME * 4];
    JsonEscape(map, escapedMap, sizeof(escapedMap));
    JsonEscape(name, escapedName, sizeof(escapedName));
    JsonEscape(exportName, escapedExportName, sizeof(escapedExportName));
    ArrayList vertices = view_as<ArrayList>(g_BoundaryVertices.Get(index));
    file.WriteLine("{");
    file.WriteLine("  \"schema_version\": 1,");
    file.WriteLine("  \"map\": \"%s\",", escapedMap);
    file.WriteLine("  \"id\": %d,", id);
    file.WriteLine("  \"name\": \"%s\",", escapedName);
    file.WriteLine("  \"export_name\": \"%s\",", escapedExportName);
    file.WriteLine("  \"geometry\": {");
    file.WriteLine("    \"type\": \"polygon3d\",");
    file.WriteLine("    \"closed\": true,");
    file.WriteLine("    \"vertices\": [");
    float vertex[3];
    for (int i = 0; i < vertices.Length; i++)
    {
        vertices.GetArray(i, vertex, 3);
        file.WriteLine("      [%.3f, %.3f, %.3f]%s", vertex[0], vertex[1], vertex[2], i + 1 < vertices.Length ? "," : "");
    }
    file.WriteLine("    ]");
    file.WriteLine("  }");
    file.WriteLine("}");
    delete file;
    return true;
}

void SanitizeFilename(const char[] input, char[] output, int outputLength)
{
    int written = 0;
    for (int i = 0; input[i] != '\0' && written < outputLength - 1; i++)
    {
        char value = input[i];
        bool allowed = (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z')
            || (value >= '0' && value <= '9') || value == '-' || value == '_';
        if (allowed)
        {
            output[written++] = value;
        }
        else
        {
            output[written++] = '_';
        }
    }
    output[written] = '\0';
}

void JsonEscape(const char[] input, char[] output, int outputLength)
{
    int written = 0;
    for (int i = 0; input[i] != '\0' && written < outputLength - 1; i++)
    {
        if ((input[i] == '\\' || input[i] == '"') && written < outputLength - 2)
        {
            output[written++] = '\\';
        }
        output[written++] = input[i];
    }
    output[written] = '\0';
}

bool RequirePlayer(int client)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        ReplyToCommand(client, "[SM Context] This command must be used in game.");
        return false;
    }
    return true;
}

bool RequireCapture(int client)
{
    if (!RequirePlayer(client))
    {
        return false;
    }
    if (!g_Capturing[client])
    {
        ReplyToCommand(client, "[SM Context] No boundary is active. Use /bstart first.");
        return false;
    }
    return true;
}

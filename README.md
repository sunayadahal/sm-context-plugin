# SM Context Boundary Curator

SourceMod plugin for manually capturing TF2 map-region polygon vertices in game.

## Commands

| Chat command | Purpose |
| --- | --- |
| `/bstart` | Start a boundary and equip a Sniper Rifle regardless of class. |
| `/bstop [name]` | Store the boundary. Missing names receive the next numeric ID. |
| `/bexport [name]` | Export a named boundary, or the latest as `map_name:id`. |
| `/bundo` | Remove the latest vertex. |
| `/bcancel` | Cancel the active boundary. |

While capture is active, every shot from the supplied rifle traces its impact and places a visible sphere marker at the resulting Source coordinate. A boundary requires at least three vertices.

Exports are written to:

```text
addons/sourcemod/data/sm-context-plugin/<export-name>.json
```

The JSON retains exact `[x, y, z]` Source coordinates as a closed `polygon3d` footprint. It is intended for review and conversion into TF2R Context Studio region geometry.

## Build

Use SourceMod 1.12 or newer:

```bash
mkdir -p vendor/sourcemod
SM_ARCHIVE="$(curl -fsSL https://www.sourcemod.net/smdrop/1.12/sourcemod-latest-linux)"
curl -fsSL "https://www.sourcemod.net/smdrop/1.12/$SM_ARCHIVE" -o /tmp/sourcemod.tar.gz
tar -xzf /tmp/sourcemod.tar.gz -C vendor/sourcemod
./scripts/build.sh
```

Or point the script at an existing compiler:

```bash
SPCOMP=/path/to/addons/sourcemod/scripting/spcomp ./scripts/build.sh
```

Copy `build/sm_context_plugin.smx` to `tf/addons/sourcemod/plugins/` and change or reload the map.

## Capture workflow

```text
/bstart
<shoot polygon vertices in order>
/bstop kitchen
/bexport kitchen
```

Capture vertices clockwise or counterclockwise without crossing edges. Use the exact BSP revision that the geometry will describe.

## Requirements

- Team Fortress 2 dedicated or listen server
- MetaMod:Source
- SourceMod 1.12+
- Standard `sdktools` and `tf2` extensions included with SourceMod

## License

MIT

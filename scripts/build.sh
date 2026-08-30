#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPCOMP="${SPCOMP:-$ROOT/vendor/sourcemod/addons/sourcemod/scripting/spcomp}"

if [[ ! -x "$SPCOMP" ]]; then
  echo "spcomp not found at $SPCOMP" >&2
  echo "Set SPCOMP=/path/to/addons/sourcemod/scripting/spcomp or unpack SourceMod into vendor/sourcemod." >&2
  exit 1
fi

mkdir -p "$ROOT/build"
"$SPCOMP" \
  -i"$(dirname "$SPCOMP")/include" \
  -o"$ROOT/build/sm_context_plugin.smx" \
  "$ROOT/scripting/sm_context_plugin.sp"

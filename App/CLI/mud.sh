#!/bin/sh
# mud — Mud.app CLI dispatcher
#
# With any flag: delegates to the bundled `mud` tool, which owns the flag
# vocabulary (so there is no second flag list here to fall out of date).
# With only filenames (or nothing): opens the Mud GUI via `open`.

set -eu

# Resolve symlinks to find the true location of this script.
SOURCE="$0"
while [ -h "$SOURCE" ]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in
    /*) ;;
    *) SOURCE="$DIR/$SOURCE" ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

# mud CLI is at Contents/Helpers/mud; this script is at Contents/Resources/mud.sh
MUD_CLI="$(dirname "$SCRIPT_DIR")/Helpers/mud"
BUNDLE="$(dirname "$(dirname "$SCRIPT_DIR")")"

if [ ! -x "$MUD_CLI" ]; then
  printf 'mud: mud CLI not found at %s\n' "$MUD_CLI" >&2
  exit 1
fi

# Any flag at all means the bundled mud tool handles the invocation —
# including flags this script has never heard of, and its own usage errors.
for arg in "$@"; do
  case "$arg" in
    -*)
      exec "$MUD_CLI" "$@"
      ;;
  esac
done

# Only filenames: open in the Mud GUI.
if [ $# -eq 0 ]; then
  if [ ! -t 0 ]; then
    # Piped stdin with no render flags — write to temp file and open in GUI
    tmp="$(mktemp /tmp/mud-stdin.XXXXXX)" && mv "$tmp" "$tmp.md"
    tmp="$tmp.md"
    cat > "$tmp"
    open -a "$BUNDLE" "$tmp"
  else
    open -a "$BUNDLE"
  fi
else
  open -a "$BUNDLE" "$@"
fi

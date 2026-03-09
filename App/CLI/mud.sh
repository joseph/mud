#!/bin/sh
# mud — Mud.app CLI dispatcher
#
# With rendering flags (-u, -d, etc.): delegates to the bundled `mud` tool.
# Without rendering flags: opens files in the Mud GUI via `open`.

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

# If any rendering or meta flag is present, delegate to the bundled mud tool.
for arg in "$@"; do
  case "$arg" in
    -u|--html-up|-d|--html-down|-b|--browser|-f|--fragment|\
    --line-numbers|--word-wrap|--readable-column|--theme|\
    -h|--help|-v|--version)
      exec "$MUD_CLI" "$@"
      ;;
  esac
done

# No rendering flags: open in the Mud GUI.
if [ $# -eq 0 ]; then
  if [ ! -t 0 ]; then
    # Piped stdin with no render flags — write to temp file and open in GUI
    tmp="$(mktemp /tmp/mud-stdin.XXXXXX.md)"
    cat > "$tmp"
    open -a "$BUNDLE" "$tmp"
  else
    open -a "$BUNDLE"
  fi
else
  open -a "$BUNDLE" "$@"
fi

#!/usr/bin/env bash
# Run after extracting/moving the whole bundle. Installs only a per-user entry.
set -euo pipefail

bundle=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
executable="$bundle/bdk_audio"
icon="$bundle/share/icons/hicolor/512x512/apps/com.bdkaudio.bdk_audio.png"
if [[ ! -x "$executable" || ! -f "$icon" ]]; then
  printf '%s\n' 'Keep this script beside the complete BDK Audio bundle.' >&2
  exit 1
fi
# The desktop Exec specification forbids '=' in executable paths. Control
# characters are refused before any existing entry is touched.
if [[ "$bundle" == *'='* || "$bundle" =~ [[:cntrl:]] ]]; then
  printf '%s\n' 'Move the bundle to a path without = or control characters.' >&2
  exit 1
fi

# First quote executable-argument metacharacters and literal percent signs;
# then encode backslashes for the desktop string layer. No shell is launched
# by the desktop entry, and user paths never become evaluated shell text.
# A fixed env executable also lets GLib validate an executable path before
# expanding a literal %% in the bundle argument; env receives one absolute path.
quoted_exec=$(printf '%s' "$executable" | sed -e 's/\\/\\\\/g' -e 's/["`$]/\\&/g' -e 's/%/%%/g' -e 's/\\/\\\\/g')
escaped_icon=$(printf '%s' "$icon" | sed 's/\\/\\\\/g')
applications="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p -- "$applications"
temporary=$(mktemp "$applications/.bdk-audio.XXXXXX")
trap 'rm -f -- "$temporary"' EXIT
printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Name=BDK Audio' \
  'Comment=Sound and lighting for your BDK speaker' \
  "Exec=/usr/bin/env \"$quoted_exec\"" \
  "Icon=$escaped_icon" \
  'Terminal=false' \
  'Categories=AudioVideo;Audio;' \
  'StartupWMClass=com.bdkaudio.bdk_audio' > "$temporary"
chmod 644 "$temporary"
mv -f -- "$temporary" "$applications/com.bdkaudio.bdk_audio.desktop"
printf '%s\n' "Registered BDK Audio from $bundle"

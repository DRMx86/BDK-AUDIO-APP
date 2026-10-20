#!/usr/bin/env bash
# Run inside the disposable Ubuntu guest as runner, never on the Windows host.
set -euo pipefail

readonly flutter_revision=ad70ec4617166f1c38e5d2bfd388af71fda14f06
readonly sdk_dir="$HOME/toolchains/flutter"

if [[ $(uname -s) != Linux || $(id -un) != runner ]]; then
  printf '%s\n' 'This bootstrap is only for the isolated Linux runner account.' >&2
  exit 1
fi

sudo env DEBIAN_FRONTEND=noninteractive apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates curl git unzip xz-utils zip clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev libsecret-1-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  gstreamer1.0-plugins-ugly gstreamer1.0-libav libgl1-mesa-dri libegl1-mesa-dev \
  xvfb xauth dbus-x11 python3-gi desktop-file-utils mesa-utils x11-utils xdotool \
  xdg-desktop-portal xdg-desktop-portal-gtk

mkdir -p "$HOME/toolchains"
if [[ ! -d "$sdk_dir/.git" ]]; then
  git init "$sdk_dir"
  git -C "$sdk_dir" remote add origin https://github.com/flutter/flutter.git
  git -C "$sdk_dir" fetch --depth=1 origin refs/tags/3.44.4:refs/tags/3.44.4
  git -C "$sdk_dir" checkout --detach "$flutter_revision"
fi
[[ $(git -C "$sdk_dir" rev-parse HEAD) == "$flutter_revision" ]]
export PATH="$sdk_dir/bin:$PATH"
flutter --disable-analytics
flutter config --enable-linux-desktop
flutter precache --linux
flutter --version
flutter doctor -v

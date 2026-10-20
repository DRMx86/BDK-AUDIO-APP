#!/usr/bin/env bash
set -euo pipefail
readonly phase=${1:?expected phase}
readonly source=/home/runner/bdk-audio-056-jammy
readonly revision=ad70ec4617166f1c38e5d2bfd388af71fda14f06
[[ $(id -un) == runner && $HOME == /home/runner ]]
[[ $(cat /.bdk-owned-jammy-root) == jammy-056-20261016 ]]
grep -qx 'VERSION_ID="22.04"' /etc/os-release
export PATH=/home/runner/toolchains/flutter/bin:/usr/local/bin:/usr/bin:/bin
export CMAKE_BUILD_PARALLEL_LEVEL=2 CC=/usr/bin/clang-14 CXX=/usr/bin/clang++-14
export PUB_CACHE=/home/runner/.pub-cache-jammy
[[ $(git -C /home/runner/toolchains/flutter rev-parse HEAD) == "$revision" ]]
mkdir -p /home/runner/evidence
date -u +%FT%TZ > "/home/runner/evidence/$phase.started"
printf '%s\n' "$$" > "/home/runner/evidence/$phase.pid"
trap 'status=$?; date -u +%FT%TZ > "/home/runner/evidence/$phase.finished"; printf "%s\n" "$status" > "/home/runner/evidence/$phase.exit"' EXIT
case "$phase" in
  inventory)
    cp /etc/os-release /home/runner/evidence/os-release
    dpkg-query -W > /home/runner/evidence/packages.tsv
    { command -v clang clang++ cmake ninja pkg-config; clang --version; cmake --version;
      ldd --version; pkg-config --modversion gtk+-3.0 gstreamer-1.0; } > /home/runner/evidence/toolchain.txt 2>&1
    git -C /home/runner/toolchains/flutter status --short > /home/runner/evidence/sdk-status.txt
    flutter --version --machine > /home/runner/evidence/flutter-version.json
    python3 /home/runner/jammy-source.py extract /home/runner/app-source-056-manifest.json \
      "$source" /home/runner/app-source-056.tar.gz > /home/runner/evidence/source-before.json
    ;;
  build|release)
    cd "$source"
    python3 /home/runner/jammy-source.py verify /home/runner/app-source-056-manifest.json "$source" > "/home/runner/evidence/source-before-$phase.json"
    if [[ $phase == build ]]; then
      [[ ! -e build ]]
      flutter pub get --enforce-lockfile
      flutter build linux --debug --no-pub -t lib/main.dart --dart-define=BDK_PREVIEW_ONLY=true --verbose
    else
      [[ ! -e build/linux/x64/release ]]
      flutter build linux --release --no-pub -t lib/main.dart --dart-define=BDK_PREVIEW_ONLY=true --verbose
    fi
    python3 /home/runner/jammy-source.py verify /home/runner/app-source-056-manifest.json "$source" > "/home/runner/evidence/source-after-$phase.json"
    ;;
  gui|gui-softpipe)
    export XDG_RUNTIME_DIR=/run/user/1000
    if [[ $phase == gui-softpipe ]]; then
      export GALLIUM_DRIVER=softpipe BDK_JAMMY_QA_PROFILE=gui-softpipe
    fi
    timeout --signal=TERM --kill-after=15s 1000 dbus-run-session -- xvfb-run -a \
      -s '-screen 0 1280x900x24 -nolisten tcp' env LIBGL_ALWAYS_SOFTWARE=1 GDK_BACKEND=x11 \
      python3 /home/runner/jammy-gui.py
    ;;
  export)
    python3 /home/runner/jammy-audit.py "$source/build/linux/x64/debug/bundle" /home/runner/evidence
    python3 /home/runner/jammy-source.py verify /home/runner/app-source-056-manifest.json "$source" > /home/runner/evidence/source-after-qa.json
    ;;
  *) exit 2 ;;
esac

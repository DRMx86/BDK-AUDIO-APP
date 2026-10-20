#!/usr/bin/env bash
# Root-only namespace entry; every persistent write stays in this guest-owned root.
set -euo pipefail
readonly base=/home/runner/jammy-056-20261016
readonly root="$base/root"
readonly phase=${1:?expected phase}
[[ $phase == setup || $phase == build || $phase == gui || $phase == gui-softpipe || $phase == export || $phase == release ]]
[[ $(id -u) == 0 && $(hostname) == bdk-linux-runner && $(uname -m) == x86_64 ]]
[[ $(realpath -e "$base") == "$base" && ! -L $root ]]
[[ $(readlink /proc/self/ns/mnt) != $(readlink /proc/1/ns/mnt) ]]
mount --make-rprivate /
readonly own_namespace=$(readlink /proc/self/ns/mnt)
cleanup() {
  local proc pid until
  local -a owned=()
  # Match both our private namespace and chroot, never names or guest-wide groups.
  for proc in /proc/[0-9]*; do
    pid=${proc##*/}
    [[ $pid != $$ ]] || continue
    if [[ $(readlink "$proc/ns/mnt" 2>/dev/null || true) == "$own_namespace" &&
          $(readlink "$proc/root" 2>/dev/null || true) == "$root" ]]; then
      printf 'owned-namespace-child=%s command=' "$pid" >> "$base/evidence/cleanup-$phase.txt"
      tr '\0' ' ' < "$proc/cmdline" >> "$base/evidence/cleanup-$phase.txt" || true
      printf '\n' >> "$base/evidence/cleanup-$phase.txt"
      owned+=("$pid")
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  until=$((SECONDS + 10))
  while (( SECONDS < until )); do
    local active=0
    for pid in "${owned[@]}"; do
      if [[ $(readlink "/proc/$pid/ns/mnt" 2>/dev/null || true) == "$own_namespace" &&
            $(readlink "/proc/$pid/root" 2>/dev/null || true) == "$root" ]]; then
        active=1
      fi
    done
    (( active )) || break
    sleep 1
  done
  for pid in "${owned[@]}"; do
    if [[ $(readlink "/proc/$pid/ns/mnt" 2>/dev/null || true) == "$own_namespace" &&
          $(readlink "/proc/$pid/root" 2>/dev/null || true) == "$root" ]]; then
      kill -KILL "$pid" 2>/dev/null || true
      printf 'owned-namespace-child-killed=%s\n' "$pid" >> "$base/evidence/cleanup-$phase.txt"
    fi
  done
}
trap cleanup EXIT
printf 'pid=%s phase=%s namespace=%s root=%s\n' "$$" "$phase" "$(readlink /proc/self/ns/mnt)" "$root" > "$base/evidence/namespace-$phase.txt"
if [[ $phase == setup ]]; then
  [[ ! -e $root ]]
  export DEBOOTSTRAP_DIR="$base/bootstrap/debootstrap-package/usr/share/debootstrap"
  "$base/bootstrap/debootstrap-package/usr/sbin/debootstrap" --arch=amd64 \
    --variant=minbase --include=ca-certificates --components=main,universe \
    --force-check-gpg --keyring="$base/bootstrap/ubuntu-archive-keyring.gpg" \
    jammy "$root" https://archive.ubuntu.com/ubuntu
  printf '%s\n' jammy-056-20261016 > "$root/.bdk-owned-jammy-root"
else
  [[ $(cat "$root/.bdk-owned-jammy-root") == jammy-056-20261016 ]]
fi
[[ $(realpath -e "$root") == "$root" ]]
grep -qx 'VERSION_ID="22.04"' "$root/etc/os-release"
mkdir -p -- "$root/proc" "$root/dev" "$root/run" "$root/tmp"
mount -t proc -o nosuid,nodev,noexec proc "$root/proc"
mount -t tmpfs -o mode=0755,nosuid tmpfs "$root/dev"
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs "$root/run"
mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs "$root/tmp"
for node in null:1:3 zero:1:5 random:1:8 urandom:1:9 tty:5:0; do
  IFS=: read -r name major minor <<< "$node"
  mknod -m 0666 "$root/dev/$name" c "$major" "$minor"
done
mkdir "$root/dev/shm"
mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs "$root/dev/shm"
ln -s /proc/self/fd "$root/dev/fd"
ln -s /proc/self/fd/0 "$root/dev/stdin"
ln -s /proc/self/fd/1 "$root/dev/stdout"
ln -s /proc/self/fd/2 "$root/dev/stderr"
install -m 0644 /etc/resolv.conf "$root/etc/resolv.conf"
if [[ $phase == setup ]]; then
  printf '#!/bin/sh\nexit 101\n' > "$root/usr/sbin/policy-rc.d"
  chmod 0755 "$root/usr/sbin/policy-rc.d"
  printf '%s\n' \
    'deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://archive.ubuntu.com/ubuntu jammy main universe' \
    'deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://archive.ubuntu.com/ubuntu jammy-updates main universe' \
    'deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://security.ubuntu.com/ubuntu jammy-security main universe' > "$root/etc/apt/sources.list"
  chroot "$root" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash -c '
    set -euo pipefail
    apt-get -o Acquire::AllowInsecureRepositories=false update
    apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils zip \
      clang-14 cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-11-dev \
      libsecret-1-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
      gstreamer1.0-plugins-base gstreamer1.0-plugins-good libgl1-mesa-dri libegl1-mesa-dev \
      xvfb xauth dbus-x11 python3-gi python3-pil desktop-file-utils mesa-utils x11-utils \
      xdotool xdg-desktop-portal xdg-desktop-portal-gtk binutils
    useradd --create-home --uid 1000 --shell /bin/bash runner
    ln -s /usr/bin/clang-14 /usr/local/bin/clang
    ln -s /usr/bin/clang++-14 /usr/local/bin/clang++
    mkdir -p /home/runner/toolchains /home/runner/evidence
  '
  cp -a -- /home/runner/toolchains/flutter "$root/home/runner/toolchains/flutter"
  cp -- "$base/bootstrap"/jammy-*.py "$base/bootstrap"/jammy-inroot.sh \
    "$base/bootstrap/app-source-056.tar.gz" "$base/bootstrap/app-source-056-manifest.json" "$root/home/runner/"
  chown -R 1000:1000 "$root/home/runner"
  chroot "$root" su runner -c 'bash /home/runner/jammy-inroot.sh inventory'
else
  mkdir -p "$root/run/user/1000"
  chown 1000:1000 "$root/run/user/1000"
  chmod 0700 "$root/run/user/1000"
  chroot "$root" su runner -c "bash /home/runner/jammy-inroot.sh $phase"
fi
# Exiting the private namespace drops only its own mounts; no shared mount is removed.
findmnt -R "$root" > "$base/evidence/mounts-$phase.txt" || true

#!/usr/bin/env bash
# Execute as runner in the existing owned QEMU guest, after its mutation fence clears.
set -euo pipefail
readonly base=/home/runner/jammy-056-20261016
readonly revision=ad70ec4617166f1c38e5d2bfd388af71fda14f06
readonly deb_sha=836bb4cfe322a415cc9e2b1abe46d65cdc53cefac315764edb498380f8f28de5
readonly helper_dir=$(realpath -e -- "${1:?expected helper directory}")
[[ $(uname -s) == Linux && $(hostname) == bdk-linux-runner && $(id -un) == runner && $HOME == /home/runner ]]
[[ $helper_dir == /home/runner/jammy-helpers-20261016 ]]
[[ $(realpath -e /home/runner) == /home/runner && ! -e $base && ! -L $base ]]
[[ $(git -C /home/runner/toolchains/flutter rev-parse HEAD) == "$revision" ]]
printf '%s  %s\n' 0fcb10a86eb935986326008e9cec64cc5f66541a54734e84f3b071d83714ed50 /home/runner/app-source-056.tar.gz | sha256sum --check --strict
mkdir -m 0755 -- "$base"
mkdir -- "$base/bootstrap" "$base/jobs" "$base/evidence"
date -u +%FT%TZ > "$base/jobs/setup.started"
printf '%s\n' "$$" > "$base/jobs/setup.pid"
trap 'status=$?; date -u +%FT%TZ > "$base/jobs/setup.finished"; printf "%s\n" "$status" > "$base/jobs/setup.exit"' EXIT
cp -- "$helper_dir"/jammy-* "$base/bootstrap/"
cp -- /home/runner/app-source-056.tar.gz /home/runner/app-source-056-manifest.json "$base/bootstrap/"
cp -- /usr/share/keyrings/ubuntu-archive-keyring.gpg "$base/bootstrap/"
apt-cache policy debootstrap > "$base/evidence/debootstrap-policy.txt"
apt-cache show debootstrap=1.0.134ubuntu2 > "$base/evidence/debootstrap-package.txt"
[[ $(awk '/^SHA256: / {print $2; exit}' "$base/evidence/debootstrap-package.txt") == "$deb_sha" ]]
cd "$base/bootstrap"
apt-get download debootstrap=1.0.134ubuntu2
printf '%s  %s\n' "$deb_sha" debootstrap_1.0.134ubuntu2_all.deb | sha256sum --check --strict
dpkg-deb -x debootstrap_1.0.134ubuntu2_all.deb debootstrap-package
sha256sum ubuntu-archive-keyring.gpg > "$base/evidence/archive-keyring.sha256"
gpgv --keyring "$base/bootstrap/ubuntu-archive-keyring.gpg" /var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_noble-updates_InRelease > "$base/evidence/noble-package-index-signature.txt" 2>&1
sudo -n timeout --signal=TERM --kill-after=30s 3600 unshare --mount --propagation private \
  bash "$base/bootstrap/jammy-namespace.sh" setup

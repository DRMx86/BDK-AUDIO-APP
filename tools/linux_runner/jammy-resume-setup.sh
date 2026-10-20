#!/usr/bin/env bash
# Resume only the recorded pre-root relative-keyring failure; preserve the failed run.
set -euo pipefail
readonly base=/home/runner/jammy-056-20261016
readonly helpers=/home/runner/jammy-helpers-20261016
readonly attempt=${2:?expected known failed pre-root stage}
[[ $attempt == setup-resume || $attempt == setup-resume2 ]]
[[ $(id -un) == runner && $(hostname) == bdk-linux-runner && $HOME == /home/runner ]]
[[ $(realpath -e "$base") == "$base" && $(realpath -e "$helpers") == "$helpers" ]]
[[ ! -e $base/root && ! -L $base/root && $(cat "$base/jobs/setup.exit") == 2 ]]
[[ ! -e $base/jobs/$attempt.started ]]
grep -Fq "keyblock resource '/home/runner/.gnupg/ubuntu-archive-keyring.gpg': No such file" "$base/evidence/noble-package-index-signature.txt"
if [[ $attempt == setup-resume ]]; then
  [[ ! -e $base/evidence/namespace-setup.txt ]]
else
  [[ $(cat "$base/jobs/setup-resume.exit") == 1 && $(cat "$helpers/jobs/setup-resume/exit") == 1 ]]
  grep -Fq 'E: unrecognized or invalid option --force-check-sig' "$helpers/jobs/setup-resume/log"
  [[ ! -e $base/evidence/namespace-setup-option-failure.txt ]]
  mv -- "$base/evidence/namespace-setup.txt" "$base/evidence/namespace-setup-option-failure.txt"
fi
printf '%s  %s\n' 0fcb10a86eb935986326008e9cec64cc5f66541a54734e84f3b071d83714ed50 \
  /home/runner/app-source-056.tar.gz | sha256sum --check --strict
[[ $(git -C /home/runner/toolchains/flutter rev-parse HEAD) == ad70ec4617166f1c38e5d2bfd388af71fda14f06 ]]
printf '%s  %s\n' 836bb4cfe322a415cc9e2b1abe46d65cdc53cefac315764edb498380f8f28de5 \
  "$base/bootstrap/debootstrap_1.0.134ubuntu2_all.deb" | sha256sum --check --strict
cmp -- "$base/bootstrap/ubuntu-archive-keyring.gpg" /usr/share/keyrings/ubuntu-archive-keyring.gpg
[[ $(sha256sum "$base/bootstrap/ubuntu-archive-keyring.gpg" | cut -d ' ' -f 1) == $(cut -d ' ' -f 1 "$base/evidence/archive-keyring.sha256") ]]
gpgv --keyring "$base/bootstrap/ubuntu-archive-keyring.gpg" /var/lib/apt/lists/archive.ubuntu.com_ubuntu_dists_noble-updates_InRelease \
  > "$base/evidence/noble-package-index-signature-$attempt.txt" 2>&1
date -u +%FT%TZ > "$base/jobs/$attempt.started"
trap 'status=$?; date -u +%FT%TZ > "$base/jobs/$attempt.finished"; printf "%s\n" "$status" > "$base/jobs/$attempt.exit"' EXIT
sudo -n timeout --signal=TERM --kill-after=30s 3600 unshare --mount --propagation private \
  bash "$base/bootstrap/jammy-namespace.sh" setup

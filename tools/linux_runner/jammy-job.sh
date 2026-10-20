#!/usr/bin/env bash
# Detached, bounded phase launcher. Re-observe live jobs; never launch on a wait timeout.
set -euo pipefail
readonly mode=${1:?expected start or execute}
readonly phase=${2:?expected phase}
readonly helpers=/home/runner/jammy-helpers-20261016
readonly base=/home/runner/jammy-056-20261016
[[ $mode == start || $mode == execute ]]
[[ $phase == setup || $phase == setup-resume || $phase == setup-resume2 || $phase == build || $phase == gui || $phase == gui-softpipe || $phase == export || $phase == release ]]
[[ $(id -un) == runner && $(hostname) == bdk-linux-runner && $HOME == /home/runner ]]
[[ $(realpath -e "$helpers") == "$helpers" ]]
readonly jobs="$helpers/jobs"
[[ ! -L $jobs ]]
if [[ ! -e $jobs ]]; then
  mkdir -- "$jobs"
fi
[[ -d $jobs && $(realpath -e "$jobs") == "$jobs" ]]
readonly job="$jobs/$phase"
if [[ $mode == start ]]; then
  [[ ! -e $job && ! -L $job ]]
  mkdir "$job"
  nohup bash "$helpers/jammy-job.sh" execute "$phase" > "$job/log" 2>&1 < /dev/null &
  printf '%s\n' "$!" > "$job/supervisor.pid"
  printf 'started phase=%s supervisor_pid=%s log=%s\n' "$phase" "$!" "$job/log"
  exit 0
fi
[[ $(realpath -e "$job") == "$job" && ! -e $job/started ]]
date -u +%FT%TZ > "$job/started"
printf '%s\n' "$$" > "$job/execute.pid"
trap 'status=$?; date -u +%FT%TZ > "$job/finished"; printf "%s\n" "$status" > "$job/exit"' EXIT
if [[ $phase == setup || $phase == setup-resume || $phase == setup-resume2 ]]; then
  script=jammy-bootstrap.sh
  [[ $phase == setup ]] || script=jammy-resume-setup.sh
  printf 'timeout --signal=TERM --kill-after=30s 4200 bash %s/%s %s %s\n' "$helpers" "$script" "$helpers" "$phase" > "$job/command"
  timeout --signal=TERM --kill-after=30s 4200 bash "$helpers/$script" "$helpers" "$phase"
else
  case "$phase" in build|release) limit=1800 ;; gui|gui-softpipe) limit=1100 ;; export) limit=300 ;; esac
  printf 'timeout --signal=TERM --kill-after=30s %s sudo -n timeout --signal=TERM --kill-after=30s %s unshare --mount --propagation private bash %s/bootstrap/jammy-namespace.sh %s\n' \
    "$((limit + 60))" "$limit" "$base" "$phase" > "$job/command"
  timeout --signal=TERM --kill-after=30s "$((limit + 60))" sudo -n \
    timeout --signal=TERM --kill-after=30s "$limit" unshare --mount --propagation private \
    bash "$base/bootstrap/jammy-namespace.sh" "$phase"
fi

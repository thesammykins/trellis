#!/bin/bash
set -euo pipefail
# Run after closing one of two fixture tabs; obtain both PIDs with echo $$ first.
[[ $# -eq 2 && "$1" =~ ^[1-9][0-9]*$ && "$2" =~ ^[1-9][0-9]*$ && "$1" != "$2" ]] || {
  echo 'Usage: check-session-isolation.sh CLOSED_PID SURVIVING_PID' >&2; exit 2;
}
if kill -0 "$1" 2>/dev/null; then echo 'FAIL closed session still alive' >&2; exit 1; fi
kill -0 "$2"
ps -p "$2" -o pid=,ppid=,command=
echo 'PASS closed process absent; sibling process remains alive'

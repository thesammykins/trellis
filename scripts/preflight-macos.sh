#!/bin/bash
# Read-only development-host inspection. Does not install or change configuration.
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  printf '%s\n' 'This preflight requires macOS. No application build was attempted.' >&2
  exit 2
fi

printf '\n== macOS and architecture ==\n'
sw_vers
uname -m
printf '\n== Active developer directory ==\n'
xcode-select --print-path
printf '\n== Xcode ==\n'
xcodebuild -version
printf '\n== macOS SDK ==\n'
xcrun --sdk macosx --show-sdk-version
printf '\n== Swift ==\n'
xcrun swift --version
printf '\n== Optional installed tools ==\n'
for tool in zig codex opencode pi tmux; do
  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
    if [ "$tool" = "tmux" ]; then
      "$tool" -V || printf '%s\n' "Version check failed for $tool"
    else
      "$tool" --version || printf '%s\n' "Version check failed for $tool"
    fi
  else
    printf '%s\n' "$tool: not found in this shell's PATH"
  fi
done
printf '\n== System SSH ==\n'
/usr/bin/ssh -V 2>&1
printf '\nNo installation, login, remote connection or configuration change was performed.\n'

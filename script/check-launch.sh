#!/bin/bash
set -euo pipefail
if [[ $# != 1 ]]; then
    echo "Usage: $0 /absolute/path/to/SessionLaunch" >&2
    exit 2
fi
/usr/bin/python3 - "$1" <<'PY'
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile

helper = str(Path(sys.argv[1]).resolve(strict=True))
with tempfile.TemporaryDirectory(prefix="trellis-launch-") as temporary:
    root = Path(temporary).resolve()
    cwd = root / "space 'quotes' 東京"
    cwd.mkdir()
    envelope = root / "launch.json"
    arguments = ["space value", "'single'", '"double"', "東京", "$(touch injected); *", ""]
    script = 'printf "%s\\0" "$PWD" "$@" "${TRELLIS_LAUNCH_ENVELOPE-unset}" "${TRELLIS_LAUNCH_TEST-unset}"'
    valid = dict(executable="/bin/sh", arguments=["-c", script, "fixture", *arguments], workingDirectory=str(cwd))
    environment = dict(os.environ, TRELLIS_LAUNCH_ENVELOPE=str(envelope), TRELLIS_LAUNCH_TEST="inherited")

    def write(value, mode=0o600):
        envelope.write_text(json.dumps(value), encoding="utf-8")
        envelope.chmod(mode)

    def run(*args):
        return subprocess.run([helper, *args], env=environment, capture_output=True, timeout=5)

    def reject(label):
        result = run()
        assert result.returncode != 0 and b"Trellis launch failed:" in result.stderr, (label, result)
        print("PASS rejected", label)

    write(valid)
    result = run()
    expected = "\0".join([str(cwd), *arguments, "unset", "inherited", ""]).encode()
    assert result.returncode == 0 and result.stdout == expected, result
    assert not envelope.exists() and not (cwd / "injected").exists()
    print("PASS exact cwd, argv, inherited environment, cleared envelope and one-use consumption")
    reject("consumed envelope")

    for label, changes in [
        ("NUL argument", dict(arguments=["bad\0value"])),
        ("relative executable", dict(executable="bin/sh")),
        ("relative cwd", dict(workingDirectory="relative")),
        ("missing cwd", dict(workingDirectory=str(root / "missing"))),
        ("excess argument count", dict(arguments=[""] * 257)),
        ("oversized argument", dict(arguments=["a" * 16_385])),
        ("oversized envelope", dict(arguments=["a" * 65_536])),
    ]:
        write(dict(valid, **changes))
        reject(label)
    write(valid, mode=0o644)
    reject("public permissions")
    envelope.unlink()
    target = root / "target.json"
    target.write_text(json.dumps(valid))
    target.chmod(0o600)
    envelope.symlink_to(target)
    reject("symlink")
    assert target.exists()
    envelope.unlink()
    write(valid)
    assert run("unexpected").returncode != 0
    print("PASS rejected helper command-line argument")

    write(dict(valid, arguments=["-c", "kill -TERM $$"]))
    result = run()
    assert result.returncode == -signal.SIGTERM, result
    print("PASS exec replacement preserves signal termination")
print("All launch checks passed")
PY

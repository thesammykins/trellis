#!/usr/bin/env python3
"""Compare app payload bytes, modes and symlink targets without following links."""
import hashlib
import os
from pathlib import Path
import stat
import sys
import tempfile


def manifest(root):
    root = Path(root)
    result = {}
    for directory, folders, files in os.walk(root, followlinks=False):
        for name in folders + files:
            path = Path(directory, name)
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode): value = ("link", os.readlink(path))
            elif stat.S_ISREG(mode): value = ("file", hashlib.sha256(path.read_bytes()).hexdigest(), stat.S_IMODE(mode))
            elif stat.S_ISDIR(mode): value = ("directory", stat.S_IMODE(mode))
            else: raise ValueError("Unexpected app payload entry: " + str(path))
            result[str(path.relative_to(root))] = value
    if not result: raise ValueError("App payload is missing or empty: " + str(root))
    return result


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]:
        with tempfile.TemporaryDirectory() as temporary:
            left, right = [Path(temporary, name) for name in ("left", "right")]
            for root in (left, right):
                root.mkdir(); (root / "binary").write_bytes(b"release")
                (root / "Current").symlink_to(".")
            assert manifest(left) == manifest(right)
            (right / "binary").write_bytes(b"stale")
            assert manifest(left) != manifest(right)
            (right / "binary").write_bytes(b"release")
            (right / "Current").unlink(); (right / "Current").symlink_to("binary")
            assert manifest(left) != manifest(right)
        print("Payload checks passed: matching bytes, stale files and changed symlinks.")
    else:
        if len(sys.argv) != 3: raise SystemExit("usage: verify-app-payload.py source.app mounted.app")
        if manifest(sys.argv[1]) != manifest(sys.argv[2]): raise SystemExit("Mounted DMG payload differs from the requested app.")
        print("Mounted app payload matches source bytes, modes and symlinks.")

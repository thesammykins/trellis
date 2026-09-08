#!/usr/bin/env python3
"""Run the release builder with isolated GitHub Actions signing credentials."""
import base64
import os
from pathlib import Path
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile

SECRET_NAMES = (
    "DEVELOPER_ID_P12_BASE64", "DEVELOPER_ID_P12_PASSWORD", "SPARKLE_ED25519_PRIVATE_KEY",
    "ASC_NOTARY_KEY_ID", "ASC_NOTARY_ISSUER_ID", "ASC_NOTARY_PRIVATE_KEY_P8",
)


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true" or sys.platform != "darwin":
        raise SystemExit("This credential wrapper runs only on a macOS GitHub Actions runner.")
    if len(sys.argv) < 2:
        raise SystemExit("usage: with-release-credentials.py command [arguments...]")
    missing = [name for name in SECRET_NAMES if not os.environ.get(name)]
    if missing:
        raise SystemExit("Missing release secrets: " + ", ".join(missing))
    material = {name: os.environ.pop(name) for name in SECRET_NAMES}
    # Subprocesses receive file/profile references, never the original secret environment.
    environment = dict(os.environ)
    runner_temp = Path(environment["RUNNER_TEMP"]).resolve()
    if not runner_temp.is_dir() or runner_temp.is_relative_to(Path.cwd().resolve()):
        raise SystemExit("RUNNER_TEMP must be an existing directory outside the checkout.")
    os.umask(0o077)
    directory = Path(tempfile.mkdtemp(prefix="trellis-release-", dir=runner_temp))
    keychain = directory / "signing.keychain-db"
    original_keychains = []
    registered = False
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(128 + signum))

    def run(arguments, *, capture=True):
        result = subprocess.run(arguments, env=environment, check=False,
                                stdout=subprocess.PIPE if capture else None,
                                stderr=subprocess.PIPE if capture else None)
        if result.returncode:
            # Never include command arguments, secret values or raw credential-tool errors.
            raise RuntimeError(f"Release command {Path(arguments[0]).name} failed (exit {result.returncode}).")
        return result.stdout

    try:
        p12 = base64.b64decode(material["DEVELOPER_ID_P12_BASE64"], validate=True)
        if not 0 < len(p12) <= 32 * 1024:
            raise ValueError("Developer ID P12 is empty or exceeds 32 KiB.")
        signing_key = material["SPARKLE_ED25519_PRIVATE_KEY"].strip()
        if len(base64.b64decode(signing_key, validate=True)) not in (32, 64):
            raise ValueError("Unexpected Sparkle private key format.")
        notary_key = material["ASC_NOTARY_PRIVATE_KEY_P8"]
        if not 0 < len(notary_key.encode()) <= 16 * 1024 or "-----BEGIN PRIVATE KEY-----" not in notary_key:
            raise ValueError("Unexpected notarization P8 format.")
        p12_file, sparkle_file, notary_file = [directory / name for name in ("identity.p12", "sparkle.key", "notary.p8")]
        p12_file.write_bytes(p12)
        sparkle_file.write_text(signing_key)
        notary_file.write_text(notary_key)
        original_keychains = shlex.split(run(["security", "list-keychains", "-d", "user"]).decode())
        password = secrets.token_urlsafe(32)
        run(["security", "create-keychain", "-p", password, str(keychain)])
        run(["security", "set-keychain-settings", "-lut", "7200", str(keychain)])
        run(["security", "unlock-keychain", "-p", password, str(keychain)])
        run(["security", "import", str(p12_file), "-k", str(keychain), "-P", material["DEVELOPER_ID_P12_PASSWORD"], "-T", "/usr/bin/codesign"])
        run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, str(keychain)])
        registered = True
        run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *original_keychains])
        run(["xcrun", "notarytool", "store-credentials", "trellis-release", "--key", str(notary_file),
             "--key-id", material["ASC_NOTARY_KEY_ID"], "--issuer", material["ASC_NOTARY_ISSUER_ID"], "--keychain", str(keychain)])
        p12_file.unlink()
        notary_file.unlink()
        material.clear()
        environment.update(TRELLIS_UPDATE_PRIVATE_KEY_FILE=str(sparkle_file),
                           TRELLIS_NOTARY_PROFILE="trellis-release", TRELLIS_NOTARY_KEYCHAIN=str(keychain))
        print("Temporary Developer ID identity and notarization profile prepared.", flush=True)
        run(sys.argv[1:], capture=False)
    finally:
        if registered:
            subprocess.run(["security", "list-keychains", "-d", "user", "-s", *original_keychains],
                           env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        if keychain.exists():
            subprocess.run(["security", "delete-keychain", str(keychain)], env=environment,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        shutil.rmtree(directory)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError) as error:
        raise SystemExit(str(error)) from None

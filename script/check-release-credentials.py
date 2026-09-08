#!/usr/bin/env python3
"""Exercise release credential ownership without a real keychain, certificate or service."""
import base64
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_credentials", Path(__file__).with_name("with-release-credentials.py"))
credentials = importlib.util.module_from_spec(spec)
spec.loader.exec_module(credentials)


class ReleaseCredentialsCheck(unittest.TestCase):
    def exercise(self, fail_build=False, invalid_key=False, missing_secret=False):
        with tempfile.TemporaryDirectory() as temporary:
            environment = {
                "GITHUB_ACTIONS": "true", "RUNNER_TEMP": temporary, "PATH": "/fixture/bin",
                "DEVELOPER_ID_P12_BASE64": base64.b64encode(b"fixture certificate").decode(),
                "DEVELOPER_ID_P12_PASSWORD": "fixture password",
                "SPARKLE_ED25519_PRIVATE_KEY": base64.b64encode(b"f" * 32).decode(),
                "ASC_NOTARY_KEY_ID": "fixture-id", "ASC_NOTARY_ISSUER_ID": "fixture-issuer",
                "ASC_NOTARY_PRIVATE_KEY_P8": "-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----",
            }
            if invalid_key:
                environment["SPARKLE_ED25519_PRIVATE_KEY"] = "malformed"
            if missing_secret:
                del environment["ASC_NOTARY_PRIVATE_KEY_P8"]
            calls = []

            def run(arguments, **kwargs):
                calls.append(list(arguments))
                self.assertTrue(all(name not in kwargs.get("env", {}) for name in credentials.SECRET_NAMES))
                output = b""
                code = 0
                if arguments[:3] == ["security", "list-keychains", "-d"] and "-s" not in arguments:
                    output = b'"/fixture/login.keychain-db"\n'
                if arguments[:2] == ["security", "create-keychain"]:
                    Path(arguments[-1]).touch()
                if arguments[0] == "fixture-build":
                    configured = kwargs["env"]
                    private = Path(configured["TRELLIS_UPDATE_PRIVATE_KEY_FILE"])
                    self.assertEqual(private.stat().st_mode & 0o777, 0o600)
                    self.assertTrue(Path(configured["TRELLIS_NOTARY_KEYCHAIN"]).is_file())
                    self.assertFalse((private.parent / "identity.p12").exists())
                    self.assertFalse((private.parent / "notary.p8").exists())
                    code = 7 if fail_build else 0
                return subprocess.CompletedProcess(arguments, code, stdout=output, stderr=b"fixture diagnostic")

            with patch.dict(os.environ, environment, clear=True), patch.object(credentials.sys, "argv", ["wrapper", "fixture-build"]), \
                    patch.object(credentials.sys, "platform", "darwin"), patch.object(credentials.subprocess, "run", side_effect=run), \
                    patch.object(credentials.signal, "signal"):
                if fail_build:
                    with self.assertRaisesRegex(RuntimeError, "fixture-build failed"):
                        credentials.main()
                elif invalid_key:
                    with self.assertRaises(ValueError):
                        credentials.main()
                elif missing_secret:
                    with self.assertRaisesRegex(SystemExit, "ASC_NOTARY_PRIVATE_KEY_P8"):
                        credentials.main()
                else:
                    credentials.main()
            self.assertEqual(list(Path(temporary).iterdir()), [], "Private runner files survived cleanup")
            if invalid_key or missing_secret:
                self.assertEqual(calls, [], "Invalid credentials reached platform tools")
            else:
                self.assertEqual(calls[-2], ["security", "list-keychains", "-d", "user", "-s", "/fixture/login.keychain-db"])
                self.assertEqual(calls[-1][:2], ["security", "delete-keychain"])

    def test_success(self): self.exercise()
    def test_build_failure_cleans_up(self): self.exercise(fail_build=True)
    def test_invalid_key_fails_before_import(self): self.exercise(invalid_key=True)
    def test_missing_secret_fails_before_import(self): self.exercise(missing_secret=True)


if __name__ == "__main__":
    unittest.main()

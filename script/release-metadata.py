#!/usr/bin/env python3
"""Resolve release metadata before a runner can access signing material."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def validate(tag, project, previous):
    versions = set(re.findall(r"MARKETING_VERSION = ([^;]+);", project))
    builds = set(re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", project))
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag) or versions != {tag[1:]} or len(builds) != 1:
        raise ValueError("Tag must match every Xcode marketing version (vX.Y.Z).")
    build = next(iter(builds))
    if not build.isdigit() or not previous.isdigit() or int(build) <= int(previous):
        raise ValueError("Build number must increase beyond the latest distributed appcast.")


def main():
    tag = os.environ["REQUESTED_TAG"]
    repo = os.environ["TRELLIS_RELEASE_REPOSITORY"]
    def gh(*args):
        return subprocess.check_output(["gh", *args], text=True)
    releases = json.loads(gh("api", f"repos/{repo}/releases?per_page=100"))
    if any(item["tag_name"] == tag for item in releases):
        raise ValueError("A release or draft already exists for this tag; inspect it before retrying.")
    published = [item for item in releases if not item["draft"] and not item["prerelease"]]
    previous = "0"
    if published:
        latest = max(published, key=lambda item: item["published_at"])
        with tempfile.TemporaryDirectory() as directory:
            gh("release", "download", latest["tag_name"], "--repo", repo, "--pattern", "appcast.xml", "--dir", directory)
            feed = Path(directory, "appcast.xml")
            if feed.stat().st_size > 2 * 1024 * 1024:
                raise ValueError("Previous appcast exceeds 2 MiB.")
            versions = ET.parse(feed).findall(".//{http://www.andymatuschak.org/xml-namespaces/sparkle}version")
            if not versions or any(not (item.text or "").isdigit() for item in versions):
                raise ValueError("Previous appcast has no valid build number.")
            previous = str(max(int(item.text) for item in versions))
    validate(tag, Path("Trellis.xcodeproj/project.pbxproj").read_text(), previous)
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"tag={tag}\nprevious_build={previous}\n")
    print(f"Release metadata validated: {tag}, previous build {previous}.")


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["--check"]:
        project = "MARKETING_VERSION = 0.4.0; CURRENT_PROJECT_VERSION = 7;"
        validate("v0.4.0", project, "6")
        for tag, previous in [("v0.4.1", "6"), ("v0.4.0\ninvalid", "6"), ("v0.4.0", "7"), ("v0.4.0", "unknown")]:
            try: validate(tag, project, previous)
            except ValueError: pass
            else: raise AssertionError("Invalid release metadata accepted")
        print("Release metadata checks passed.")
    else:
        main()

#!/usr/bin/env python3
"""Prepare stable core updates and retry releases that have not been published."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.error
import urllib.request


UPSTREAM = "MetaCubeX/mihomo"
ASSET = "nikki_x86_64-openwrt-25.12.tar.gz"


def stable_version(tag):
    if not isinstance(tag, str) or not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError(f"Expected a stable Mihomo tag, got {tag!r}")
    return tuple(int(part) for part in tag[1:].split("."))


def make_value(text, name):
    matches = re.findall(rf"^{re.escape(name)}:=(.+)$", text, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError(f"Expected exactly one {name} in the Makefile")
    return matches[0].strip()


def github_json(path, missing_ok=False):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "nikki-stable-updater"}
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(f"https://api.github.com/repos/{path}", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if missing_ok and error.code == 404:
            return None
        raise


def source_checksum(tag, version):
    stable_version(tag)
    if tag != f"v{version}":
        raise ValueError("The source tag does not match the package version")
    original_umask = os.umask(0o022)
    try:
        with tempfile.TemporaryDirectory(prefix="nikki-mihomo-source-") as temporary:
            work = Path(temporary)
            source = work / "source"
            subprocess.run([
                "git", "clone", "--depth=1", "--branch", tag,
                f"https://github.com/{UPSTREAM}.git", str(source),
            ], check=True)
            subprocess.run(["git", "config", "core.abbrev", "8"], cwd=source, check=True)
            timestamp = subprocess.check_output([
                "git", "log", "-1", "--no-show-signature", "--format=@%ct",
            ], cwd=source, text=True).strip()
            raw = work / "source.tar"
            subprocess.run([
                "git", "archive", "--format=tar", "HEAD", f"--output={raw}",
            ], cwd=source, check=True)
            directory = work / f"mihomo-meta-{version}"
            directory.mkdir()
            subprocess.run([
                "tar", "--no-same-permissions", "-C", str(directory), "-xf", str(raw),
            ], check=True)
            if (directory / ".gitmodules").exists():
                raise ValueError("Mihomo now has submodules; source packing needs review")
            archive = work / "source.tar.gz"
            with archive.open("wb") as output:
                tar = subprocess.Popen([
                    "tar", "--numeric-owner", "--owner=0", "--group=0", "--mode=a-s",
                    "--sort=name", f"--mtime={timestamp}", "-c", directory.name,
                ], cwd=work, stdout=subprocess.PIPE)
                try:
                    subprocess.run(["gzip", "-nc"], stdin=tar.stdout, stdout=output, check=True)
                finally:
                    tar.stdout.close()
                    tar_status = tar.wait()
                if tar_status != 0:
                    raise RuntimeError("Failed to create the reproducible source archive")
            return hashlib.sha256(archive.read_bytes()).hexdigest()
    finally:
        os.umask(original_umask)


def release_ready(release):
    if not release or release.get("draft", True) or release.get("prerelease", True):
        return False
    assets = [asset for asset in release.get("assets", []) if asset.get("name") == ASSET]
    return len(assets) == 1 and assets[0].get("state") == "uploaded" and assets[0].get("size", 0) > 0


def prepare_update(root, repository, verify_source=False):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid destination repository")
    makefile = root / "mihomo-meta/Makefile"
    text = makefile.read_text(encoding="utf-8")
    current = make_value(text, "PKG_VERSION")
    current_tuple = stable_version(f"v{current}")
    latest = github_json(f"{UPSTREAM}/releases/latest")
    if latest.get("draft", True) or latest.get("prerelease", True):
        raise ValueError("The upstream latest release is not stable")
    latest_tag = latest["tag_name"]
    newer = stable_version(latest_tag) > current_tuple
    version = latest_tag[1:] if newer else current

    state_path = root / ".github/mihomo-release.json"
    old_state = state_path.read_text(encoding="utf-8")
    state = json.loads(old_state)
    if newer or state.get("version") != version:
        luci = (root / "luci-app-nikki/Makefile").read_text(encoding="utf-8")
        luci_version = make_value(luci, "PKG_VERSION")
        stable_version(f"v{luci_version}")
        state = {"version": version, "tag": f"v{luci_version}-mihomo-{version}"}
    tag = state["tag"]
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-mihomo-\d+\.\d+\.\d+)?", tag):
        raise ValueError("Invalid destination release tag")
    release = github_json(f"{repository}/releases/tags/{tag}", missing_ok=True)

    if newer or verify_source:
        checksum = source_checksum(f"v{version}", version)
        if not re.fullmatch(r"[0-9a-f]{64}", checksum):
            raise ValueError("Invalid source SHA256")
        if not newer and checksum != make_value(text, "PKG_MIRROR_HASH"):
            raise ValueError("The current source checksum differs from the pinned hash")
        for name, value in {
            "PKG_VERSION": version,
            "PKG_SOURCE_VERSION": f"v{version}",
            "PKG_BUILD_VERSION": f"v{version}",
            "PKG_MIRROR_HASH": checksum,
        }.items():
            make_value(text, name)
            text = re.sub(rf"^{name}:=.*$", f"{name}:={value}", text, flags=re.MULTILINE)

    new_state = json.dumps(state, indent=2) + "\n"
    changed = text != makefile.read_text(encoding="utf-8") or new_state != old_state
    if changed:
        makefile.write_text(text, encoding="utf-8")
        state_path.write_text(new_state, encoding="utf-8")
    return {
        "changed": changed,
        "build": changed or not release_ready(release),
        "version": version,
        "release_tag": tag,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--verify-source", action="store_true")
    args = parser.parse_args()
    if not args.repository:
        parser.error("--repository or GITHUB_REPOSITORY is required")
    result = prepare_update(args.root, args.repository, args.verify_source)
    print(json.dumps(result, indent=2))
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as stream:
            for name, value in result.items():
                rendered = str(value).lower() if isinstance(value, bool) else value
                stream.write(f"{name}={rendered}\n")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as stream:
            stream.write(f"Mihomo stable version: **{result['version']}**. ")
            stream.write("Build required.\n" if result["build"] else "Published packages are current.\n")


if __name__ == "__main__":
    main()

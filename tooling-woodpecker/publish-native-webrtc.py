#!/usr/bin/env python3
"""Publish a verified native artifact once; does not change the app update feed."""
import argparse
import configparser
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess
import urllib.request
import uuid
import zipfile


def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as stream:
        while chunk := stream.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def remote(host, code):
    return subprocess.check_output(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host,
         "python3 -c " + shlex.quote(code)], text=True
    ).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ssh-host", default="personal-vps")
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    third_party = Path(__file__).resolve().parents[1] / "packages/flutter_webrtc/third_party"
    ini = configparser.ConfigParser(interpolation=None)
    ini.read(third_party / "libwebrtc_version.ini")
    manifest = ini["libwebrtc"]
    version, revision = manifest["binary_version"], manifest["windows_artifact_revision"]
    for value in (version, revision):
        if not re.fullmatch(r"[A-Za-z0-9._-]+", value) or value in (".", ".."):
            raise ValueError("Unsafe native artifact version")
    asset = "libwebrtc-win-x64-release-fourfun-ducking.zip"
    archive = args.archive or third_party / "downloads" / asset
    expected = manifest["windows_archive_sha256_x64"]
    if digest(archive) != expected:
        raise ValueError("Archive SHA256 does not match the committed manifest")
    with zipfile.ZipFile(archive) as package:
        # Windows PowerShell Compress-Archive uses backslashes in member names.
        members = {name.replace("\\", "/"): name for name in package.namelist()}
        metadata = json.loads(package.read(members["fourfun-ducking-build.json"]))
        for field in ("binary_version", "webrtc_revision", "wrapper_revision"):
            if metadata[field] != manifest[field]:
                raise ValueError(f"Native artifact {field} mismatch")
        patch = third_party / "patches" / manifest["windows_ducking_patch"]
        dll_hash = hashlib.sha256(package.read(members["lib/libwebrtc.dll"])).hexdigest()
        if (metadata["architecture"] != "x64" or metadata["patch_sha256"] != digest(patch)
                or metadata["dll_sha256"] != dll_hash or dll_hash != manifest["windows_dll_sha256_x64"]
                or not package.read(members["lib/libwebrtc.dll.lib"])):
            raise ValueError("Native artifact architecture, patch or DLL mismatch")
    base = manifest["windows_download_url"].rstrip("/")
    if base != "https://updates.srv1849611.hstgr.cloud/native/libwebrtc":
        raise ValueError("Publication destination must match the configured VPS native directory")
    directory = f"/docker/updates/data/native/libwebrtc/{version}/{revision}"
    destination = f"{directory}/{asset}"
    temporary = f"{destination}.{uuid.uuid4().hex}.part"
    prepare = f"""
from pathlib import Path
import hashlib, os, pwd
account = pwd.getpwnam('updates-deploy')
directory = Path({directory!r})
for path in [Path('/docker/updates/data/native'), Path('/docker/updates/data/native/libwebrtc'), directory.parent, directory]:
    path.mkdir(exist_ok=True)
    os.chown(path, account.pw_uid, account.pw_gid)
    path.chmod(0o755)
destination = Path({destination!r})
if destination.exists():
    with destination.open('rb') as stream:
        actual = hashlib.sha256(stream.read()).hexdigest()
    if actual != {expected!r}:
        raise RuntimeError('Immutable native version already exists with different bytes')
    print('reuse')
else:
    print('upload')
"""
    if remote(args.ssh_host, prepare) == "upload":
        try:
            subprocess.run(["scp", "-o", "BatchMode=yes", str(archive),
                            f"{args.ssh_host}:{temporary}"], check=True)
            remote(args.ssh_host, f"""
from pathlib import Path
import fcntl, hashlib, os, pwd
directory = Path({directory!r})
temporary, destination = Path({temporary!r}), Path({destination!r})
with (directory / '.publish.lock').open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    with temporary.open('rb') as stream:
        actual = hashlib.sha256(stream.read()).hexdigest()
    if actual != {expected!r}:
        raise RuntimeError('Uploaded native archive hash mismatch')
    account = pwd.getpwnam('updates-deploy')
    os.chown(temporary, account.pw_uid, account.pw_gid)
    temporary.chmod(0o644)
    if destination.exists():
        with destination.open('rb') as stream:
            if hashlib.sha256(stream.read()).hexdigest() != {expected!r}:
                raise RuntimeError('Refusing to overwrite immutable native artifact')
    else:
        os.link(temporary, destination)
    temporary.unlink()
print('published')
""")
        finally:
            remote(args.ssh_host, f"from pathlib import Path; Path({temporary!r}).unlink(missing_ok=True)")
    url = f"{base}/{version}/{revision}/{asset}"
    hosted_hash = hashlib.sha256()
    with urllib.request.urlopen(url, timeout=60) as response:
        while chunk := response.read(1024 * 1024):
            hosted_hash.update(chunk)
    if hosted_hash.hexdigest() != expected:
        raise ValueError("Hosted HTTPS native archive hash mismatch")
    print(f"Verified immutable native artifact: {url}\nSHA256: {expected}")


if __name__ == "__main__":
    main()

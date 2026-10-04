#!/usr/bin/env python3
"""Check frozen MFCL source files and their archive without running a model."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import zipfile

MANIFEST_SHA256 = "10c4433ecd3bc54a7390efc5c35868fd071d84d680cae352eebf2c90340b128d"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(stream):
    result = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        result.update(chunk)
    return result.hexdigest()


def file_digest(path):
    with path.open("rb") as stream:
        return digest(stream)


def regular(path):
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode), f"not a regular file: {path}")
    return info


def verify(root):
    folder = root / "MFCL"
    require(stat.S_ISDIR(folder.lstat().st_mode), "MFCL must be a regular directory")
    manifest_path = folder / "manifest.json"
    regular(manifest_path)
    require(file_digest(manifest_path) == MANIFEST_SHA256, "fixed manifest hash mismatch")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    require(manifest["schema_version"] == 1, "unsupported manifest schema")
    entries = {entry["path"]: entry for entry in manifest["files"]}
    require(len(entries) == len(manifest["files"]), "duplicate manifest paths")
    for name, entry in entries.items():
        parts = PurePosixPath(name).parts
        require(len(parts) == 2 and parts[0] == "MFCL" and parts[1] not in (".", "..")
                and "\\" not in name, f"unsafe manifest path: {name}")
        path = root / name
        info = regular(path)
        require(info.st_size == entry["bytes"], f"byte count mismatch: {name}")
        require(stat.S_IMODE(info.st_mode) == int(entry["mode"], 8), f"mode mismatch: {name}")
        require(file_digest(path) == entry["sha256"], f"hash mismatch: {name}")

    expected_names = {PurePosixPath(name).name for name in entries} | {"manifest.json", "README.md", ".gitattributes"}
    require({path.name for path in folder.iterdir()} == expected_names, "unexpected MFCL inventory")
    regular(folder / "README.md")
    regular(folder / ".gitattributes")
    require((folder / ".gitattributes").read_bytes() == b"* -text\n", "native byte preservation attributes differ")

    assets = {asset["id"]: asset for asset in manifest["assets"]}
    for asset in assets.values():
        path = folder / asset["name"]
        require(regular(path).st_size == asset["bytes"] and file_digest(path) == asset["sha256"],
                f"source asset mismatch: {asset['id']}")
    checks = {}
    for line in (folder / assets[511034059]["name"]).read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        require(match is not None, "malformed source contents checksum")
        expected, member = match.groups()
        require(member not in checks, f"duplicate source checksum: {member}")
        checks[member] = expected
    zip_checksum = (folder / assets[511034060]["name"]).read_text(encoding="utf-8")
    require(zip_checksum == assets[511034058]["sha256"] + "  " + assets[511034058]["name"] + "\n",
            "original ZIP checksum line mismatch")

    with zipfile.ZipFile(folder / assets[511034058]["name"]) as archive:
        infos = archive.infolist()
        byname = {info.filename: info for info in infos}
        require(len(infos) == len(byname) == manifest["archive_member_count"],
                "archive member count or duplicate mismatch")
        require(set(byname) == set(checks), "archive and source checksum membership differ")
        for member, info in byname.items():
            parts = PurePosixPath(member).parts
            mode = info.external_attr >> 16
            require(not member.startswith("/") and ".." not in parts and "\\" not in member
                    and len(parts) == 2 and member.startswith(manifest["archive_prefix"]),
                    f"unsafe archive path: {member}")
            require(info.create_system == 3 and stat.S_ISREG(mode) and not info.flag_bits & 1,
                    f"non-regular or encrypted archive member: {member}")
            with archive.open(info) as stream:
                require(digest(stream) == checks[member], f"source member hash mismatch: {member}")
        for name, entry in entries.items():
            if "source_member" in entry:
                member = entry["source_member"]
                info = byname[member]
                require(info.file_size == entry["bytes"] and checks[member] == entry["sha256"]
                        and stat.S_IMODE(info.external_attr >> 16) == int(entry["mode"], 8),
                        f"source member pins mismatch: {name}")
                with (root / name).open("rb") as local, archive.open(info) as source:
                    while True:
                        left, right = local.read(1024 * 1024), source.read(1024 * 1024)
                        require(left == right, f"source member bytes differ: {name}")
                        if not left:
                            break
            elif "source_git" in entry:
                source = root / entry["source_git"]["path"]
                regular(source)
                require(file_digest(source) == entry["sha256"], f"original Git source differs: {name}")
            else:
                asset = assets[entry["source_asset"]]
                require(entry["path"] == "MFCL/" + asset["name"]
                        and entry["bytes"] == asset["bytes"] and entry["sha256"] == asset["sha256"],
                        f"source asset pins mismatch: {name}")
    print(f"Verified {len(entries)} frozen source files and all {len(byname)} source ZIP members; no model run.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1],
                        help="repository root (defaults to the parent of ci/)")
    args = parser.parse_args()
    try:
        verify(args.root)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, RuntimeError) as error:
        print(f"MFCL verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

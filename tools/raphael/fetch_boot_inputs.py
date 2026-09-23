#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Fetch pinned public inputs; install only when all four original locks pass."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tarfile
import tempfile
import urllib.request

REQUIRED = (
    "recovery-initramfs-7.1", "control-sm8150-xiaomi-raphael.dtb",
    "raphael-uboot-cache.img", "BOOTAA64.EFI",
)
REPOSITORY = "Embracecactus/raphael-linux-bringup"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(path, record):
    require(stat.S_ISREG(path.lstat().st_mode), f"not a regular file: {path.name}")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    with os.fdopen(os.open(path, flags), "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_size == record["bytes"],
                f"size/type mismatch: {path.name}")
        hasher = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
        digest = hasher.hexdigest()
    require(digest == record["sha256"], f"SHA-256 mismatch: {path.name}")


def checked_directory(path):
    # 不跟随目标目录的符号链接，避免写到 retained 目录之外。
    for part in reversed((path, *path.parents)):
        if part.exists() or part.is_symlink():
            require(not part.is_symlink() and part.is_dir(),
                    f"unsafe destination directory: {part}")


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        require(newurl.startswith("https://"), "non-HTTPS redirect rejected")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def download(record, target):
    # 无 GitHub CLI、Token、cookie 或 netrc 依赖；仅公开 HTTPS GET。
    opener = urllib.request.build_opener(HTTPSRedirect())
    req = urllib.request.Request(record["url"], headers={"User-Agent": "raphael-boot-inputs/1"})
    with opener.open(req, timeout=60) as response, target.open("xb") as output:
        require(response.status == 200, "download did not return HTTP 200")
        remaining = record["bytes"]
        while chunk := response.read(min(1024 * 1024, remaining + 1)):
            remaining -= len(chunk)
            require(remaining >= 0, "download exceeds pinned size")
            output.write(chunk)
    verify(target, record)


def unpack(archive, stage, names, lock):
    seen = set()
    # 只读取成员数据，不调用 extract/extractall，不创建链接或设备节点。
    with tarfile.open(archive, "r|gz") as bundle:
        for member in bundle:
            require(member.name in names and member.name not in seen,
                    f"unexpected/duplicate archive member: {member.name}")
            require(member.isfile() and not member.issparse() and not member.pax_headers,
                    f"non-regular or extended archive member: {member.name}")
            require(member.size == lock[member.name]["bytes"],
                    f"archive member size mismatch: {member.name}")
            source = bundle.extractfile(member)
            require(source is not None, "missing member content")
            with source, (stage / member.name).open("xb") as output:
                shutil.copyfileobj(source, output)
            verify(stage / member.name, lock[member.name])
            seen.add(member.name)
    require(seen == set(names), "archive is missing declared inputs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check all four retained files without downloading")
    parser.add_argument("--local-input-dir", type=Path, help="your own original locked inputs for files withheld from public distribution")
    parser.add_argument("--archive", type=Path, help="use an already downloaded archive, with all checks retained")
    parser.add_argument("--download-only", type=Path, metavar="FILE", help="save the verified public archive only; does not make packaging ready")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    lock = json.loads((root / "config/raphael/boot-inputs.lock.json").read_text())
    target = root / "artifacts/retained/raphael-boot-inputs"
    checked_directory(target)
    existing = set()
    for name in REQUIRED:
        path = target / name
        if path.exists() or path.is_symlink():
            verify(path, lock[name])  # 不静默覆盖任何不匹配的现有文件。
            existing.add(name)
    if args.check:
        require(existing == set(REQUIRED), "missing retained inputs: " + ", ".join(sorted(set(REQUIRED) - existing)))
        print("retained_inputs=PASS (4/4; original lock)")
        return
    if existing == set(REQUIRED) and not args.download_only:
        print("retained_inputs=PASS (4/4; already installed)")
        return
    release = json.loads((root / "config/raphael/boot-inputs.release.json").read_text())
    require(release["repository"] == REPOSITORY, "unexpected release repository")
    require(release["lock_file"] == "config/raphael/boot-inputs.lock.json", "unexpected lock file")
    require(release["tag"] not in ("", "latest") and "/" not in release["tag"], "release must use a fixed tag")
    record = release["archive"]
    names = record["inputs"]
    require(names and len(set(names)) == len(names) and set(names) <= set(REQUIRED), "invalid release input allowlist")
    expected_url = f'https://github.com/{REPOSITORY}/releases/download/{release["tag"]}/{record["name"]}'
    require(record["url"] == expected_url and "/" not in record["name"], "unexpected asset URL/name")
    supplied = {}
    for name in set(REQUIRED) - set(names) - existing:
        path = args.local_input_dir / name if args.local_input_dir else None
        if path is not None and (path.exists() or path.is_symlink()):
            verify(path, lock[name])
            supplied[name] = path
        elif not args.download_only:
            raise ValueError(f"{name} is withheld from this public release; see docs/boot-inputs-release.md. "
                             "Supply your own matching original with --local-input-dir, or use --download-only FILE "
                             "to retrieve the public subset. No retained files installed.")
    with tempfile.TemporaryDirectory(prefix="raphael-inputs-") as temp:
        work = Path(temp)
        archive = work / "download.tar.gz"
        if args.archive:
            verify(args.archive, record)
            shutil.copyfile(args.archive, archive)
            verify(archive, record)
        else:
            download(record, archive)
        stage = work / "verified"
        stage.mkdir()
        unpack(archive, stage, names, lock)
        if args.download_only:
            with args.download_only.open("xb") as output, archive.open("rb") as source:
                shutil.copyfileobj(source, output)
            print(f"public_archive=PASS ({len(names)}/4 inputs); retained_inputs=NOT_INSTALLED")
            return
        for name in set(REQUIRED) - set(names):
            shutil.copyfile(target / name if name in existing else supplied[name], stage / name)
        for name in REQUIRED:
            verify(stage / name, lock[name])
        checked_directory(target)
        target.mkdir(parents=True, exist_ok=True)
        # 同文件系统暂存，原子创建每个文件；若运行中断，可安全重跑。
        with tempfile.TemporaryDirectory(prefix=".verified-", dir=target) as install_temp:
            install = Path(install_temp)
            for name in REQUIRED:
                shutil.copyfile(stage / name, install / name)
                (install / name).chmod(0o644)
                verify(install / name, lock[name])
            for name in REQUIRED:
                try:
                    os.link(install / name, target / name)
                except FileExistsError:
                    verify(target / name, lock[name])
        for name in REQUIRED:
            verify(target / name, lock[name])
    print("retained_inputs=PASS (4/4; original lock)")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, EOFError, tarfile.TarError) as error:
        print(f"fetch_boot_inputs: {error}", file=sys.stderr)
        sys.exit(1)

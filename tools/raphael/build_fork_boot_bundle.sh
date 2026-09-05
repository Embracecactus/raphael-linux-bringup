#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Package a committed fork build with the retained Raphael boot inputs.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export UPSTREAM_TREE="${SOURCE_DIR:-$repo_root/linux}"
export BUILD_DIR="${BUILD_DIR:-$repo_root/artifacts/build/raphael-mainline}"
export OUTPUT_DIR="${OUTPUT_DIR:-$repo_root/artifacts/build/fastboot-raphael-mainline}"
inputs="$repo_root/artifacts/retained/raphael-boot-inputs"

python3 - "$repo_root" "$UPSTREAM_TREE" "$BUILD_DIR" "$inputs" <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root, source, build, inputs = map(Path, sys.argv[1:])
def require(condition, message):
    if not condition:
        sys.exit("build_fork_boot_bundle: " + message)

def sha(path):
    with path.open("rb") as f:
        h = hashlib.sha256()
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
        return h.hexdigest()

lock = json.loads((root / "config/raphael/boot-inputs.lock.json").read_text())
for name in ("recovery-initramfs-7.1", "control-sm8150-xiaomi-raphael.dtb",
             "raphael-uboot-cache.img", "BOOTAA64.EFI"):
    path = inputs / name
    require(path.is_file(), f"restore retained input: {path}")
    require(sha(path) == lock[name]["sha256"], f"retained input hash mismatch: {name}")
require(not subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"]),
        "commit source changes before packaging")
head = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
manifest = dict(line.split("=", 1) for line in (build / "build-manifest.txt").read_text().splitlines()
                if "=" in line)
require(manifest.get("source_content") == "git" and
        manifest.get("source_patch_sha256") == "none",
        "build must come from committed sources without temporary overlays")
require(manifest["source_commit"] == head, "source HEAD differs from the built commit; rebuild first")
for name, key in ((".config", "config_sha256"),
                  ("arch/arm64/boot/vmlinuz.efi", "vmlinuz_efi_sha256"),
                  ("arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb", "dtb_sha256")):
    require(sha(build / name) == manifest[key], f"build output changed: {name}")
PY

export STABLE_INITRAMFS="$inputs/recovery-initramfs-7.1"
export STABLE_INITRAMFS_RELEASE=7.1.0-raphael-fusion-f72bd7
export STABLE_LOADER="$inputs/raphael-uboot-cache.img"
export GRUB_EFI="$inputs/BOOTAA64.EFI"
# Keep the control DTB used by the recorded RPMh A/B/A experiment.
export CONTROL_DTB="$inputs/control-sm8150-xiaomi-raphael.dtb"
exec bash "$repo_root/tools/raphael/build_fastboot_boot_cache_bundle.sh"

# 从 Android 到 Raphael Linux：提取、备份、首次安装与恢复

本文把 2026 年 9 月 1–15 日范围内找回的 Raphael session 记录，与历史提交、
当前脚本交叉核对，串成一条首次安装流程。实际相关记录集中在 9 月 2–5 日，
共 35 个 session；没有发现 9 月 6–15 日以本项目为工作目录的新 session。
日期统一使用北京时间；原始 session 的 UTC 时间可能比这里早一天。

**9 月 3 日确实在原 Android 手机上完成过持久安装并进入 Debian 13。**
但这不代表另一台手机首次安装、当前脚本从零构建、完整回退 Android 都已验证。
本文整理于 9 月 24 日，本次仅查记录、核对代码和补文档，没有连接、刷写或重启手机。

阅读顺序：第 1–3 节确认路线与设备 → 第 4–5 节准备原厂恢复材料、提取备份 →
第 6–7 节构建并校验自己的镜像 → 第 8–10 节首次写入、回读与验收。
第 11 节是后续内核更新，第 12 节是失败处理，第 13 节列出历史证据及未验证项。

## 1. 先选择正确的路线

| 你的状态 | 使用路线 | 会改变什么 |
| --- | --- | --- |
| 仍是 Android，准备改装 Linux | 本文第 2–10 节 | recovery 换为 TWRP；userdata 改为 Linux；写 cache/boot，清空 dtbo |
| 已有本项目 Debian，只更新内核 | 第 11 节及[开发工作流](development.md) | 只更新 boot/cache，保留自己的 userdata |
| 只想编译、下载或了解流程 | 停在第 6–7 节 | 只操作主机文件 |
| 想恢复 Android | 第 12 节 | 先判断损坏范围；完整回退尚无实机验收记录 |

这是 Redmi K20 Pro 中国版 `raphael` 的 bring-up 流程，不是稳定 ROM 安装器。
原验收机是 **8 GB / 256 GB、Android 10、MIUI V12.0.6.0.QFKCNXM、非 A/B 分区**，
开始时普通和 critical 解锁状态都已为 unlocked，Android 没有 root。
其他容量、区域版本及 `raphaelin` 不能仅因备份脚本接受该名称就视为安装已验收。

首次安装会失去原 userdata 中的 Android 应用、账号和文件。原用户当时明确放弃
备份这些数据，这不是其他使用者的默认选择。先完成自己的 Android 数据导出，
再讨论解锁和分区写入。NV/校准备份不能代替照片、应用或加密 userdata 备份。

历史启动链为：

```text
原厂 ABL → boot 内 U-Boot → cache FAT16 内 GRUB EFI
        → Linux + initramfs + runtime DTB → userdata ext4 内 Debian
recovery 单独保留 TWRP，供检查、备份和故障处理
```

首次成功使用 c526 的 **7.0 服务器内核**。当前日常开发是 **7.3 fork**，
不能把两者的镜像、DTB、模块和验收结果随意混用。

## 2. 准备主机、自己的凭据和私有记录目录

以下命令面向 Linux Bash；WSL 也可用，但 USB 必须交给执行命令的那一侧。
命令块按章节逐步执行，不能把全文拼成一个无人值守刷机脚本。
所有设备命令都必须先确认目标；本文中的读取命令也不由文档自动执行。

```bash
git clone https://github.com/Embracecactus/raphael-linux-bringup.git
cd raphael-linux-bringup
export REPO="$PWD"
umask 077
export PRIVATE="$REPO/artifacts/device-private/my-first-install-$(date +%Y%m%dT%H%M%S)"
mkdir -m 700 -p "$PRIVATE"
git rev-parse HEAD > "$PRIVATE/repository-commit.txt"
```

已有 checkout 不必再次 clone。不要覆盖已有构建目录或他人的修改。
`artifacts/device-private/` 已被 Git 忽略，仍应将备份另存一份到自己控制的其他磁盘。
不要上传原始 session、序列号、NV、校准镜像、SSH 私钥或使用过的 rootdir。

ADB/Fastboot 从 [Android 官方 Platform Tools](https://developer.android.com/tools/releases/platform-tools)
获取，记录所用版本。历史成功组合是 Linux Fastboot 37.0.1 与 WSL USBIP；
这不是要求所有机器使用同一 USB BUSID 或照抄原电脑路径。

```bash
export ADB="$(command -v adb)"
export FASTBOOT="$(command -v fastboot)"
test -x "$ADB" && test -x "$FASTBOOT"
"$ADB" version
"$FASTBOOT" --version
```

WSL 下可在 Windows 用 `usbipd list` 查看连接，在管理员终端绑定确认的 BUSID，
再用 `usbipd attach --wsl --busid <实际 BUSID>` 交给 WSL。切换 Android、Fastboot、
TWRP、Linux USB 模式后可能重新枚举，必须重新检查；不要同时从 Windows 和 WSL 操作。
历史上 Linux USB 节点需要 root 权限；优先配置本机 udev 权限，若使用 sudo，
显式保留所需变量，不能因为权限问题改用不带序列号的命令。
Fastboot 停滞时先处理残留进程和 USB 归属，不要并发补发 erase/flash。

为自己的新系统准备公钥；私钥只留在自己的主机：

```bash
export KEY="$HOME/.ssh/raphael-my-device"
test ! -e "$KEY" && test ! -e "$KEY.pub" && \
  ssh-keygen -t ed25519 -f "$KEY" -C raphael-my-device
test -f "$KEY.pub"
ssh-keygen -lf "$KEY.pub"
export USER_NAME=raphael
```

如已有自己的密钥，将 `KEY` 设置为该路径即可，不要覆盖它。后续 rootfs 只接收
`$KEY.pub`。仓库旧日志中原设备私钥的位置不适用于你，也不需要向维护者索取私钥。

## 3. 在 Android 中提取基线并备份个人数据

先在 Android 导出照片、文档、应用支持的数据和需要的账号恢复信息，并在另一台
设备或磁盘检查能否读取。Android 加密 userdata 的裸镜像不等于可恢复的应用备份。
本项目的分区备份工具**不包含 userdata**。

开启 USB 调试，在手机上确认自己主机的授权。`adb devices -l` 的输出只保存在本地，
从中人工选择这台手机，不自动取列表第一项：

```bash
"$ADB" devices -l
read -r -p '输入已确认手机的 ADB 序列号: ' ADB_SERIAL
export ADB_SERIAL
test -n "$ADB_SERIAL"
"$ADB" -s "$ADB_SERIAL" shell getprop ro.product.device
"$ADB" -s "$ADB_SERIAL" shell getprop ro.build.version.incremental
"$ADB" -s "$ADB_SERIAL" shell getprop ro.build.version.release
"$ADB" -s "$ADB_SERIAL" shell getprop ro.build.version.security_patch
```

记录产品、区域、MIUI 版本和容量，用来选择**该手机匹配的原厂恢复包**。
避免直接公开 `getprop` 全量输出，其中可能有设备标识。
原机 Android 无 root，无法直接读 NV 分区；当时通过后面的 TWRP 获得只读提取能力，
没有通过安装 Magisk 或共享其他设备备份解决这个问题。

若 Bootloader 未解锁，先按 [TeamWin Raphael 页面中的 Xiaomi 官方解锁入口](https://twrp.me/xiaomi/xiaomimi9tpro.html)
完成 Mi Unlock 流程。解锁会清除个人数据；本文没有“原机执行解锁成功”的 session
证据，不提供未经该机型验证的通用 `fastboot flashing unlock` 替代步骤。
若解锁、账号或 critical 状态不满足要求，停在这里，不尝试改写引导链。

完成自己的数据备份后，手动进入 Fastboot（关机后音量下 + 电源），读取基线：

```bash
"$FASTBOOT" devices
read -r -p '输入已确认手机的 Fastboot 序列号: ' EXPECTED_FASTBOOT_SERIAL
export EXPECTED_FASTBOOT_SERIAL
test -n "$EXPECTED_FASTBOOT_SERIAL"
bash tools/raphael/read_fastboot_vars.sh "$FASTBOOT" > "$PRIVATE/fastboot-baseline.txt"
cat "$PRIVATE/fastboot-baseline.txt"
```

此脚本是只读查询，部分不支持的 getvar 允许失败，**退出码 0 并不代表所有条件满足**。
必须检查下面的值，不明或不一致就停止并重新评估：

| 项目 | 原验收机记录 |
| --- | --- |
| product / unlocked | `raphael` / `yes`；oem device-info 普通及 critical 均已解锁 |
| 分区布局 | 非 A/B；不是 fastbootd 用户空间模式 |
| anti | `1`；这只是该机基线，不是降低 anti-rollback 的许可 |
| boot | 134217728 字节，`0x08000000` |
| recovery | 67108864 字节，`0x04000000` |
| cache | 268435456 字节，`0x10000000` |
| dtbo | 33554432 字节，`0x02000000` |
| userdata | 247304531968 字节，`0x39947fb000` |
| max-download-size | 805306368 字节，768 MiB |

## 4. 先准备原厂恢复材料，再安装 TWRP

原机匹配的官方包是：

```text
raphael_images_V12.0.6.0.QFKCNXM_20201209.0000.00_10.0_cn_4589b26f0f.tgz
bytes: 3727922045
MD5: 4589b26f0fb147c93fa0c127abd31f0a
历史来源: https://bigota.d.miui.com/V12.0.6.0.QFKCNXM/<上述文件名>
历史完成下载所用镜像: https://bn.d.miui.com/V12.0.6.0.QFKCNXM/<上述文件名>
```

这些是原机来源证据，不保证旧下载地址永远可用，也不适用于所有区域 ROM。
先验证来源、包校验和及包内校验清单，在新的主机目录提取需要的 `images/` 文件。
归档展开前列出成员，检查绝对路径、`..` 和链接；不要执行包里的 `flash_all*` 脚本。
MD5 用于与历史包比对，不单独作为可信来源证明。原机提取结果如下：

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| boot.img | 134217728 | `85abc140e4a09d052611a0c8ba20cdbaeaa3c07c2971e0c1265c2f76e0015d73` |
| recovery.img | 67108864 | `5c19743339997ef104cab667a048b672f331b27494900b97a9a0345eee9deb8c` |
| dtbo.img | 33554432 | `352295b7e0e5e5994cc32ed382e96fed2cd26198b23fa64f1b18bfe85821762e` |
| vbmeta.img | 4096 | `7fc30936b64ef5ef09038efa3d684e423ba892bde071cedef33a1a4410a85ca7` |
| cache.img | 123028，Android sparse | `466ed7a12a4349debf364e18da4f38f377cdb3f25ce60f6c875b130aa5dd7e55` |

**sparse 文件大小不等于分区大小，不能直接 dd 到块设备，也不能与整分区原始哈希混比。**
原厂 recovery 必须在刷 TWRP **之前**保存；后面备份到的 recovery 已经是 TWRP。

已取得**上述相同原厂包**时，可用以下主机命令校验包并仅提取五项恢复材料。
它不执行包内程序、不使用归档里的路径作为输出路径、不恢复归档权限：

```bash
read -r -p '输入匹配的原厂 tgz 包绝对路径: ' STOCK_ROM
export STOCK_ROM
python3 - <<'PY'
import hashlib, os, shutil, tarfile
from pathlib import Path, PurePosixPath
rom = Path(os.environ['STOCK_ROM'])
if rom.stat().st_size != 3727922045:
    raise SystemExit('不是本文锁定的原厂包大小；停止')
h = hashlib.md5()
with rom.open('rb') as stream:
    for chunk in iter(lambda: stream.read(4*1024*1024), b''):
        h.update(chunk)
if h.hexdigest() != '4589b26f0fb147c93fa0c127abd31f0a':
    raise SystemExit('原厂包 MD5 不符；停止')
dest = Path(os.environ['PRIVATE'])/'stock-images'
dest.mkdir(mode=0o700, exist_ok=False)
expected = {'boot.img': 134217728, 'recovery.img': 67108864,
            'dtbo.img': 33554432, 'vbmeta.img': 4096, 'cache.img': 123028}
seen = set()
with tarfile.open(rom, 'r|gz') as archive:
    for member in archive:
        p = PurePosixPath(member.name)
        if p.name not in expected or p.parent.name != 'images':
            continue
        if p.is_absolute() or '..' in p.parts or not member.isfile():
            raise SystemExit('拒绝不安全的恢复镜像成员')
        if p.name in seen or member.size != expected[p.name]:
            raise SystemExit('恢复镜像重复或大小不符')
        with archive.extractfile(member) as src, (dest/p.name).open('xb') as out:
            shutil.copyfileobj(src, out, 4*1024*1024)
        seen.add(p.name)
if seen != set(expected):
    raise SystemExit('恢复镜像缺失；保留目录排查，不继续刷写')
for name in sorted(expected):
    p = dest/name
    h = hashlib.sha256()
    with p.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4*1024*1024), b''):
            h.update(chunk)
    print(p.stat().st_size, h.hexdigest(), name)
PY
```

逐项与上表的大小和 SHA-256 对比，全部一致才接受；同时保留完整原厂包和包内
校验清单。不同版本手机应重新建立自己的对应关系，不能修改以上常量来绕过不一致。

TWRP 使用 [TeamWin 官方下载页：twrp-3.7.1_12-1-raphael.img](https://dl.twrp.me/raphael/twrp-3.7.1_12-1-raphael.img.html)。
从该页获取镜像及校验/签名，不从本仓库寻找重新打包的 TWRP。
历史核对大小 67108864 字节，SHA-256：

```text
3f555e26847df70e4c61ae8c5fd7d27ca7013a21d72d548dc738354ea071c9b2
```

历史 detached signature 验证通过，TeamWin 密钥指纹为
`9570 7D42 307C 9D41 D09B F709 1D85 97D7 891A 43DF`。
下载时仍需通过官方渠道确认签名来源，不能把“有签名文件”当成验证通过。

**不要把 `fastboot boot TWRP.img` 当作本机已验证的临时恢复路线。**
历史上该命令返回 OKAY，却回到了无 root 的 Android；判断必须以实际 recovery
运行态为准。实际走通的是写入 recovery 后立即按键进入 TWRP。
只有原厂恢复文件已保存、目标和解锁状态已确认后，才执行此阶段唯一的分区写入：

```bash
read -r -p '输入已从官方取得的 TWRP 镜像绝对路径: ' TWRP
export TWRP
(
  set -euo pipefail
  test "$(stat -c %s "$TWRP")" = 67108864
  printf '%s  %s\n' \
    3f555e26847df70e4c61ae8c5fd7d27ca7013a21d72d548dc738354ea071c9b2 \
    "$TWRP" | sha256sum -c -
  read -r -p '已保存匹配原厂 recovery，确认只写 recovery？输入 WRITE_RECOVERY: ' answer
  test "$answer" = WRITE_RECOVERY
  "$FASTBOOT" -s "${EXPECTED_FASTBOOT_SERIAL:?}" flash recovery "$TWRP"
)
```

写入成功后，用音量上 + 电源立即进入 TWRP，不先正常启动 Android；原厂系统可能
覆盖 recovery。进入 TWRP 时选择保持系统只读，不执行 Format Data、Wipe 或刷 ZIP。
尚未开始 Linux 安装，不能因为 TWRP 无法解密 `/data` 就先格式化它。

## 5. TWRP 中提取两份关键备份和完整安全集

重新查询 ADB，按第 3 节方式确认并设置本模式下的 `ADB_SERIAL`，然后检查：

```bash
"$ADB" -s "${ADB_SERIAL:?}" shell id
"$ADB" -s "$ADB_SERIAL" shell getprop ro.twrp.version
"$ADB" -s "$ADB_SERIAL" shell getprop ro.product.device
BACKUP_ROOT="$PRIVATE/inventory" \
  bash tools/raphael/backup_recovery_partitions.sh --inventory > "$PRIVATE/partitions.tsv"
```

必须是 root adbd、TWRP 运行标记、正确产品，且分区清单可读。
脚本帮助文字仍称 “ephemeral TWRP”，实际门禁是 root/TWRP/产品检查，
不证明 RAM 临时启动。历史成功备份来自已写入 recovery 的 TWRP。

```bash
(
  set -euo pipefail
  BACKUP_ROOT="$PRIVATE/preservation-a" \
    bash tools/raphael/backup_recovery_partitions.sh --backup-preservation
  BACKUP_ROOT="$PRIVATE/preservation-b" \
    bash tools/raphael/backup_recovery_partitions.sh --backup-preservation
  BACKUP_ROOT="$PRIVATE/safety" \
    bash tools/raphael/backup_recovery_partitions.sh --backup-safety-set
)
```

这两份 preservation 是**两次独立设备读取**，不是复制第一份。
每次实际输出在 `BACKUP_ROOT/<UTC时间>-raphael/`，记录 `manifest.tsv`。

| 集合 | 分区 |
| --- | --- |
| preservation，7 项 | modemst1、modemst2、fsg、fsc、persist、persistbak、devinfo |
| safety 新增 12 项 | boot、cache、dtbo、vbmeta、recovery、vendor、cust、logo、splash、modem、bluetooth、dsp |

工具只读取，不写分区；检查长度并计算哈希，失败会保留 partial 并非零退出。
继续之前重新核验主机文件，并比较两次 preservation 的大小/哈希：

```bash
python3 - <<'PY'
import csv, hashlib, os
from pathlib import Path
root = Path(os.environ['PRIVATE'])
preserve = set('modemst1 modemst2 fsg fsc persist persistbak devinfo'.split())
safety = preserve | set('boot cache dtbo vbmeta recovery vendor cust logo splash modem bluetooth dsp'.split())
def verify(group, expected):
    manifests = list((root / group).glob('*/manifest.tsv'))
    if len(manifests) != 1:
        raise SystemExit(f'{group}: 应恰有一份清单，请为重试使用新的目录')
    manifest = manifests[0]
    with manifest.open() as stream:
        rows = list(csv.DictReader(stream, delimiter='\t'))
    if len(rows) != len(expected) or {r['partition'] for r in rows} != expected:
        raise SystemExit(f'{group}: 分区集合不匹配')
    result = {}
    for row in rows:
        p = manifest.parent / (row['partition'] + '.img')
        if row['status'] != 'ok' or p.is_symlink() or not p.is_file():
            raise SystemExit(f'{group}: {p.name} 不完整')
        h = hashlib.sha256()
        with p.open('rb') as stream:
            for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
                h.update(chunk)
        pair = (p.stat().st_size, h.hexdigest())
        if pair != (int(row['bytes']), row['sha256']):
            raise SystemExit(f'{group}: {p.name} 校验失败')
        result[row['partition']] = pair
    return result
a = verify('preservation-a', preserve)
b = verify('preservation-b', preserve)
verify('safety', safety)
if a != b:
    raise SystemExit('两次 preservation 不一致；停止，不覆盖任一份')
print('PASS: 两次 7 分区独立读取一致，19 分区安全集文件完整')
PY
```

任一步失败都先解决备份问题。把完整目录另存到独立磁盘，再校验一次。
这里的两份校准备份及 19 分区安全集在历史实机上都已完成。
其中 recovery 是 TWRP；第 4 节保存的原厂 recovery 是另一份恢复材料。
这些文件与具体手机绑定，不能公开，更不能把别人的 persist/NV 写到自己的手机。
仓库 builder 中的上游校准文件也不能替代自己的备份。

## 6. 取得启动输入，构建属于自己的服务器 rootfs

### 6.1 两种来源分别准备

固定 Release 提供四项输入，下载不需要 GitHub 登录：

```bash
python3 tools/raphael/fetch_boot_inputs.py
python3 tools/raphael/fetch_boot_inputs.py --check
bash tools/raphael/verify_git_tree.sh third_party/raphael-kernel-builder \
  ee3e9a20ba8b20b438ff649e4ced707d54611bb1
```

恢复目录是 `artifacts/retained/raphael-boot-inputs/`；具体固定 tag、附件及来源见
[启动输入交付](boot-inputs-release.md)。四项为 `recovery-initramfs-7.1`、
`control-sm8150-xiaomi-raphael.dtb`、`raphael-uboot-cache.img`、`BOOTAA64.EFI`。
它们不含 Debian userdata，也不是刷入四个同名分区的意思。

本节历史服务器构建路线**仅复用其中的 U-Boot**；服务器脚本从锁定的 7.0 deb
安装内核及模块，生成自己的 initramfs、EFI 和 runtime DTB。其 DTB 不是当前
boot/cache 打包用的锁定控制 DTB。不要手动把 Release 的 7.1 initramfs 混进 7.0 cache。

完整 builder 已随仓库交付，不需再次 clone；不要运行其中含清理/全局设置的上游
总构建脚本。服务器工具的四个本地辅助文件、来源和许可边界见
[rootfs 交付说明](rootfs-delivery.md)。没有“必须再从手机提取整机镜像”的构建依赖；
当前配方使用锁定 builder 中的固件/ALSA 材料。公开这些材料不代表适配、许可审计
和每台手机的校准问题都已解决，不能把构建结果默认当成可公开分发的通用镜像。

历史 kernel deb 的固定下载与校验：

```bash
(
  set -euo pipefail
  mkdir -p artifacts/downloads/community-audit/kernel-v7.0
  deb="$REPO/artifacts/downloads/community-audit/kernel-v7.0/linux-image-xiaomi-raphael.deb"
  expected=9f1a0ca50c7e0035c0ec8fea84e46dd9e5b04869e3f3506d7aae83ea9d7f230e
  if test ! -e "$deb"; then
    part=$(mktemp "${deb}.partial.XXXXXX")
    trap 'rm -f -- "$part"' EXIT
    curl --fail --location --proto '=https' --proto-redir '=https' \
      'https://github.com/GavinLiuOnline/xiaomi_raphael_build_kernel/releases/download/kernel-v7.0/linux-image-xiaomi-raphael.deb' \
      --output "$part"
    printf '%s  %s\n' "$expected" "$part" | sha256sum -c -
    test "$(stat -c %s "$part")" = 24065880
    mv -n -- "$part" "$deb"
  fi
  printf '%s  %s\n' "$expected" "$deb" | sha256sum -c -
)
```

下载失败、不足长度或哈希不同就停止，不能改脚本内历史哈希放行。

### 6.2 在隔离的 Linux 构建环境生成镜像

需要可用的 root/chroot、QEMU aarch64 binfmt 和足够磁盘。建议用专门构建 VM；
以下安装及构建命令只在主机运行。主机依赖示例：

```bash
sudo apt-get update
sudo apt-get install python3 curl git file mmdebstrap qemu-user-static binfmt-support \
  debian-archive-keyring device-tree-compiler mtools dosfstools e2fsprogs \
  openssh-client util-linux coreutils findutils gawk grep sed tar dpkg systemd
```

以脚本 `need` 检查及实际环境为准。配方使用 Debian/TUNA 的签名 trixie 仓库；
保存的 222 项包版本清单不是完整 APT 快照，历史 `apt-inrelease.sha256` 为空，
不能承诺今天构建得到同一镜像哈希。

```bash
export ROOTFS_OUT="$REPO/artifacts/build/my-server-rootfs-$(date +%Y%m%dT%H%M%S)"
(
  set -euo pipefail
  test ! -e "$ROOTFS_OUT"
  sudo env SSH_PUBLIC_KEY="$KEY.pub" USER_NAME="$USER_NAME" \
    KERNEL_DEB="$REPO/artifacts/downloads/community-audit/kernel-v7.0/linux-image-xiaomi-raphael.deb" \
    BUILDER_SOURCE="$REPO/third_party/raphael-kernel-builder" \
    OUTPUT_DIR="$ROOTFS_OUT" OUTPUT_UID="$(id -u)" OUTPUT_GID="$(id -g)" \
    ALLOW_CLEAN=0 RESUME_FROM_IMAGES=0 \
    bash tools/raphael/build_debian_trixie_server.sh
)
```

**本次没有执行该命令。** 历史最终镜像基于已核验 staging 续做，干净环境从零
重建仍未验收；若这里失败，就停在构建阶段，不使用原用户镜像绕过。
脚本保留 merged-/usr、模块 ABI 和 DTB 处理，不要另用 `dpkg-deb -x` 覆盖 rootdir
的 `/lib` 符号链接。输出目录必须在 `artifacts/build/` 下，失败重试也用新目录，
不要盲目开启 `ALLOW_CLEAN=1`。

成功应产生：

| 输出 | 用途 |
| --- | --- |
| `raphael-userdata-rootfs.img` | 自己公钥配置的 Debian 13 arm64 ext4，写 userdata |
| `raphael-cache-boot.img` | 256 MiB FAT16、4096 字节逻辑扇区，写 cache |
| `boot-staging/` | 本次 EFI、GRUB 配置和 runtime DTB |
| `manifest.txt` | 来源、ABI、DTB、策略、镜像大小与哈希 |
| `package-manifest.tsv`、`apt-inrelease.sha256` | 本次包版本及实际取得的仓库记录；检查是否为空 |

该服务器默认用户和 root 密码均锁定，禁用 root SSH/密码 SSH，只允许自己的公钥。
普通用户有 bring-up 阶段的 `NOPASSWD: ALL` sudo 权限；这不是面向公网的默认安全配置。
首次启动生成自己的 SSH host keys 和 machine-id。镜像内含你的公钥，rootdir、
manifest 和镜像都按个人构建材料保存，不默认上传。

## 7. 冻结本次刷入清单，在主机完成校验

先确认 `manifest.txt` 的内核是 `7.0.0-sm8150-gc526b7bf7ebc-dirty`，
cache 为 FAT16/4096，USB wrapper/core 都是 peripheral，移除了 role-switch
和两个 boot-display 标记。脚本 `prepare_runtime_dtb.sh` 实现这些处理。
历史最初的 FAT32/512 cache 在 U-Boot 报扇区不匹配；只改 USB 子节点也未恢复 UDC。

```bash
export ROOTFS_IMAGE="$ROOTFS_OUT/raphael-userdata-rootfs.img"
export CACHE_IMAGE="$ROOTFS_OUT/raphael-cache-boot.img"
export UBOOT_IMAGE="$REPO/artifacts/retained/raphael-boot-inputs/raphael-uboot-cache.img"
python3 tools/raphael/fetch_boot_inputs.py --check
cat "$ROOTFS_OUT/manifest.txt"
file "$ROOTFS_IMAGE" "$CACHE_IMAGE" "$UBOOT_IMAGE"
fsck.fat -n "$CACHE_IMAGE"
e2fsck -fn "$ROOTFS_IMAGE"
```

两项文件系统检查必须通过；不是对手机分区执行检查或修复。
再验证镜像与本次 manifest 一致：

```bash
python3 - <<'PY'
import hashlib, os
from pathlib import Path
root = Path(os.environ['ROOTFS_OUT'])
m = dict(line.split('=', 1) for line in (root/'manifest.txt').read_text().splitlines() if '=' in line)
if m.get('kernel_release') != '7.0.0-sm8150-gc526b7bf7ebc-dirty':
    raise SystemExit('内核路线不匹配')
if m.get('cache_filesystem') != 'fat16;logical_sector_bytes=4096':
    raise SystemExit('cache 格式不匹配')
for prefix, filename in [('rootfs', 'raphael-userdata-rootfs.img'), ('cache', 'raphael-cache-boot.img')]:
    p = root / filename
    h = hashlib.sha256()
    with p.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4*1024*1024), b''):
            h.update(chunk)
    if (p.stat().st_size, h.hexdigest()) != (int(m[prefix+'_bytes']), m[prefix+'_sha256']):
        raise SystemExit(prefix + ': 大小或哈希不符')
if (root/'raphael-cache-boot.img').stat().st_size != 268435456:
    raise SystemExit('cache 必须为完整 256 MiB 镜像')
print('PASS: 本次镜像与构建清单一致')
PY
```

用 `MTOOLS_SKIP_CHECK=1 mdir -i "$CACHE_IMAGE" ::/` 检查 FAT 目录。
这是 mtools 访问 4096 字节扇区镜像的设置，不是跳过 SHA 或文件系统校验。
继续使用 `MTOOLS_SKIP_CHECK=1 mcopy -i` 读出
`/EFI/BOOT/BOOTAA64.EFI`、`/EFI/BOOT/grub.cfg`、`/linux.efi`、`/initramfs`、
`/dtbs/qcom/sm8150-xiaomi-raphael.dtb` 到新的临时目录，逐项与 rootdir/boot-staging
比较，五项必须一致。服务器构建脚本检查文件存在，不等于完成全部逐字回读验收。

人工复核完成后，冻结用于传输及回读的哈希，不再修改镜像：

```bash
test ! -e "$PRIVATE/install-inputs.sha256" && \
  sha256sum "$ROOTFS_IMAGE" "$CACHE_IMAGE" "$UBOOT_IMAGE" > "$PRIVATE/install-inputs.sha256"
sha256sum -c "$PRIVATE/install-inputs.sha256"
```

原历史 userdata 的哈希不能作为你的新 rootfs 验收值：原镜像带原用户公钥，
没有作为公共模板发布。新公钥、包版本、构建时间都会使镜像发生变化。

## 8. 首次写入：userdata → cache → dtbo → boot

**本节会破坏原 Android userdata。到这里必须已经满足：**

- Android 个人数据已经另行导出并检查；接受原 userdata 被清除。
- 匹配的原厂恢复材料可用，TWRP 可再次进入。
- 两次 7 分区备份一致，19 分区安全集完整，已另存磁盘。
- 本次三项镜像、manifest、文件系统与 FAT 内容检查通过。
- 回到 ABL Fastboot 后，重新读取身份、解锁状态和分区大小，仍符合第 3 节基线。

当前 `flash_fastboot_boot_cache.sh` 是**已有 Debian 的更新工具**，要求完整
boot/cache 包，不负责创建 userdata 或清空 dtbo，不能代替本节首次安装。
以下保留历史成功写入顺序，所有命令显式选定同一手机；每条失败立即停止。
它只适用于上述已核验的 256 GB 基线，不能直接照搬到不同分区布局。

```bash
(
  set -euo pipefail
  : "${EXPECTED_FASTBOOT_SERIAL:?}" "${PRIVATE:?}"
  : "${ROOTFS_IMAGE:?}" "${CACHE_IMAGE:?}" "${UBOOT_IMAGE:?}"
  sha256sum -c "$PRIVATE/install-inputs.sha256"
  test "$(stat -c %s "$CACHE_IMAGE")" = 268435456
  test "$(stat -c %s "$UBOOT_IMAGE")" = 630784
  test "$(stat -c %s "$ROOTFS_IMAGE")" -le 247304531968
  bash tools/raphael/read_fastboot_vars.sh "$FASTBOOT"
  read -r -p '已人工复核目标/大小/解锁/备份，接受清除 Android 数据？输入 ERASE_ANDROID_USERDATA: ' answer
  test "$answer" = ERASE_ANDROID_USERDATA
  "$FASTBOOT" -s "$EXPECTED_FASTBOOT_SERIAL" erase userdata
  "$FASTBOOT" -s "$EXPECTED_FASTBOOT_SERIAL" -S 700M flash userdata "$ROOTFS_IMAGE"
  "$FASTBOOT" -s "$EXPECTED_FASTBOOT_SERIAL" erase cache
  "$FASTBOOT" -s "$EXPECTED_FASTBOOT_SERIAL" flash cache "$CACHE_IMAGE"
  "$FASTBOOT" -s "$EXPECTED_FASTBOOT_SERIAL" erase dtbo
  "$FASTBOOT" -s "$EXPECTED_FASTBOOT_SERIAL" erase boot
  "$FASTBOOT" -s "$EXPECTED_FASTBOOT_SERIAL" flash boot "$UBOOT_IMAGE"
)
```

这里 `boot` 的 630784 字节 U-Boot 输入与当前更新工具要求的 128 MiB 完整 boot
镜像是两种交付形式，不要互换入口。`-S 700M` 来自历史 768 MiB 下载上限；
新目标上限更小时不能照搬。

历史 userdata 传输出现过 `Invalid sparse file format at header magic`，随后完成
sparse 发送、写入并返回 OKAY。不能单凭这行就宣告失败，也不能单凭 OKAY 宣告启动
成功；还需后面的回读及系统验收。超时、非零退出或读回不符都必须停下来处理。

本阶段不写 recovery、vendor、cust、vbmeta、modem、bluetooth、dsp 和任何 NV/校准
分区。不刷 xbl/abl，不重锁 Bootloader，不用 `flash_all_lock`。
`dtbo erase` 是这条首次转换路线的历史步骤，后续只更新内核时不重复执行。

## 9. 回读与首次启动

先通过物理按键回到已保留的 TWRP，重新确认 ADB 序列号、root、产品及 TWRP 标记。
cache 不能处于挂载状态；在 TWRP 的 Mount 页面取消 cache 挂载后再读。
以下读取约 384 MiB，保存到新的私有目录；不会写手机：

```bash
(
  set -euo pipefail
  test ! -e "$PRIVATE/readback"
  mkdir -m 700 "$PRIVATE/readback"
  "$ADB" -s "${ADB_SERIAL:?}" exec-out \
    'dd if=/dev/block/by-name/cache bs=4194304 2>/dev/null' > "$PRIVATE/readback/cache.img"
  "$ADB" -s "$ADB_SERIAL" exec-out \
    'dd if=/dev/block/by-name/boot bs=4194304 2>/dev/null' > "$PRIVATE/readback/boot.img"
  test "$(stat -c %s "$PRIVATE/readback/cache.img")" = 268435456
  test "$(stat -c %s "$PRIVATE/readback/boot.img")" = 134217728
  cmp "$CACHE_IMAGE" "$PRIVATE/readback/cache.img"
  cmp -n "$(stat -c %s "$UBOOT_IMAGE")" "$UBOOT_IMAGE" "$PRIVATE/readback/boot.img"
)
```

cache 必须整块一致；短 U-Boot 输入只比较 boot 中对应的前缀，不声称尾部也与输入一致。
userdata 经 sparse 写入、首次启动扩容后不能拿整个分区与缩小的 ext4 文件比哈希。
以主机 ext4 检查、传输成功、正确根分区挂载及启动验收共同判断。

历史最终成功 cache 是在 TWRP 下确认未挂载后，先校验推送文件，再用 `dd` 写入并
整块回读一致的；因此“当前正确 FAT16 镜像一次 Fastboot 写入即完成首装”是整理后的
路线，不能冒称历史一次成功。若 Fastboot 后 cache 回读不一致，保留日志并停止；
不要继续启动或反复盲刷。TWRP 直接写块设备只能在重新确认输入哈希、目标别名、
完整分区大小和未挂载状态后单独处理，本文不提供自动兜底覆盖。

回读通过后，在 TWRP 选择 Reboot → System，观察 U-Boot、GRUB、Linux 控制台。
首次启动生成 host keys，并将 ext4 扩展到 userdata 大小，耐心等待，保留屏幕和日志。
黑屏不必然代表完全没启动，USB 网络和 SSH 也要检查；反之只有亮屏也不算系统验收。

## 10. USB 网络、自己的 SSH 与验收

历史服务器配方通过 USB 提供 NCM 网络及 ACM，手机地址 `172.16.42.1/24`，
主机通常从它的 DHCP 得到地址。若未自动获得，在主机确认**实际新出现的 USB 网卡**后
配置 `172.16.42.2/24`，不要改变默认网关或把地址配置到 Wi-Fi 网卡。
Windows 使用 USB NCM 网卡，WSL 网络不等同于 Windows 主机网络；选择实际能到达
手机的一侧运行 SSH。不能通过随意关闭防火墙或更换默认路由掩盖 USB 枚举问题。

首次 SSH 连接先通过自己手机的本地控制台，或在 TWRP 中只读查看新生成的
`/etc/ssh/ssh_host_ed25519_key.pub` 指纹，与 SSH 提示比较；不要读取 host 私钥。
该值是首次启动后生成的，不能用构建前不存在的 host key 做比较。
确认后接受并保存到自己的 known_hosts，不使用 `StrictHostKeyChecking=no`。

```bash
ssh -i "$KEY" "$USER_NAME@172.16.42.1"
```

在手机 SSH 会话执行只读验收：

```bash
uname -r
cat /etc/os-release
findmnt /
df -h /
systemctl --failed
systemctl is-active ssh
cat /var/lib/raphael-bringup/boot-ok
ls /sys/class/udc
ip -br addr show usb0
```

第 6 节服务器路线预期是 Debian 13、`7.0.0-sm8150-gc526b7bf7ebc-dirty`、
userdata ext4 读写挂载、扩容到目标分区、无失败服务、SSH active、
`RAPHAEL_LINUX_BOOT_OK` 标记、UDC `a600000.usb` 和 USB 地址可达。
标记只证明对应服务运行，必须和本次内核、根分区及服务状态共同核对。

回到主机，用自己的密钥采集，不采用工具中原设备的默认私钥路径：

```bash
SSH_KEY="$KEY" SSH_TARGET="$USER_NAME@172.16.42.1" \
  OUTPUT_DIR="$PRIVATE/runtime" \
  bash tools/raphael/collect_linux_acceptance_runtime.sh
```

采集器要求已确认的 host key，使用 `sudo -n`；它适配历史服务器的免密 sudo。
若你已更改 sudo 策略，需另行安排只读采集，不为执行工具恢复不需要的权限。
原始结果可能有机器标识和网络信息，只保留在私有目录。

历史验收通过：8 核、约 7.5 GiB RAM、userdata 扩容、1080×2340 控制台、USB NCM/SSH。
当时触摸事件为零，SLPI 多次崩溃，不能写成整机功能全部正常。
9 月 5 日后续版本增加 GT9886 16 ms 轮询并经用户确认可操作，另装 XFCE/Phosh；
这不是第 6 节服务器脚本自动提供的桌面状态。

## 11. 已有 Debian 后再更新当前 fork 内核与桌面

完成服务器首装后，需要转到当前 fork 时，按[开发工作流](development.md)准备
独立 `linux/` 源码，checkout `kernel-source.lock.json` 的完整提交并安装交叉编译依赖。
下载四项 retained 输入后继续原入口：

```bash
JOBS=16 bash tools/raphael/build_fork_kernel.sh
bash tools/raphael/build_fork_boot_bundle.sh
FASTBOOT="$(command -v fastboot)" bash tools/raphael/flash_fastboot_boot_cache.sh preflight
```

这三步只在主机生成和检查文件。实际更新前备份当前可用 boot/cache，并核对
`EXPECTED_FASTBOOT_SERIAL`、包路径和 manifest，再按部署文档执行显式双写；
不再格式化 userdata，也不重复清空 dtbo。
当前打包器保留严格输入锁、模块 ABI、容量和 FAT 回读检查，使用历史控制 DTB；
从源码编出的新候选 DTB 没有因此获得实机验收。

桌面配置分开参考 [XFCE/触摸记录](research/2026-09-05-xfce-gt9886.md) 和
[Phosh 记录](research/2026-09-05-phosh.md)。里面的原用户名、密码和配置上下文不能
直接变成他人的安装默认值。现有材料尚未形成从空白 rootfs 到同一桌面状态的完整配方。
软件重启可靠性、音频、相机等仍有未解决问题，不能称为完整稳定 ROM。

## 12. 失败停在哪里，如何准备恢复

| 失败位置 | 处理边界 |
| --- | --- |
| 未解锁、来源不明、分区不匹配 | 不继续写入；先补齐匹配原厂包和设备基线 |
| TWRP 未进入或 adbd 不为 root | 不备份、不格式化；核实是否回到了 Android，检查 recovery 启动方式 |
| 任一备份缺失或双读不同 | 保留两份及日志，重新只读排查；禁止以别人的备份补位 |
| 构建/哈希/文件系统/回读失败 | 停在该阶段，不改锁定哈希，不跳过检查 |
| U-Boot 报 FAT sector size mismatch | 核对 cache FAT16/4096；不是重新刷原厂 modem 或 NV 的理由 |
| Linux 黑屏、无 USB 或无法 SSH | 使用保留的 TWRP 和已知可用 boot/cache 处理，检查 DTB/USB/自身凭据 |
| 想恢复 Android | 先区分只换了 recovery，还是已经覆盖 userdata；见下文 |

**完整回退 Android 尚无本项目实机验收记录。** 以下是恢复材料及决策边界，
不是已经验证的一键回退脚本：

1. 仅写了 TWRP，Android 其他分区未改：匹配的原厂 `recovery.img` 是恢复 recovery
   的候选输入；先检查版本、大小和 SHA，再针对 recovery 操作。历史中观察到 MIUI
   可能重写 recovery，但不能依赖这一行为作为可控恢复流程。
2. 已安装 Linux：原 Android userdata 已被覆盖。只刷回 boot 不会恢复 Android。
   必须审查自己的原厂 ROM 与现存 vendor/system/cust 等是否匹配，再决定恢复
   boot、dtbo、cache、recovery 及 Android userdata 初始化方案；原厂 recovery 的
   factory reset 也会再次清数据。需单独完成匹配版本的恢复验证，不能宣称本文已保证。
3. `cache.img` 可能是 Android sparse，必须使用理解 sparse 的工具，不能直接 dd。
   原始分区备份与 ROM 稀疏镜像的哈希/长度比较方法不同。
4. modemst/fsg/fsc/persist/devinfo 等只在确认具体损坏及同一手机来源时单独研究恢复。
   不为“保险”全量覆盖，不共享、不跨手机恢复，不触碰 xbl/abl 或重锁。
5. 无法进入 Fastboot/TWRP 时，停止本流程，转到适合该设备的救援处理；本文没有
   EDL、test point 或授权维修工具的验证记录。

完整安装流程的文档已经串联，但独立设备安装、干净构建和完整 Android 回退验收
仍是交付缺口。没有保留恢复材料时，应停在安装前，而不是以“以后再下载”代替。

## 13. 证据索引与本次整理的验收范围

历史提交固定为 `8146d647067b18c08ee859023816f7ade2c009ae`。
以下旧文件已退出活动目录，通过固定提交查阅，不要求把原始 session 或整个归档公开：

| 证据 | 支持的事实 |
| --- | --- |
| [设备基线](https://github.com/Embracecactus/raphael-linux-bringup/blob/8146d647067b18c08ee859023816f7ade2c009ae/docs/verification/2026-09-02-raphael-device-baseline.md) | 原 Android、解锁状态、容量与分区 |
| [恢复材料](https://github.com/Embracecactus/raphael-linux-bringup/blob/8146d647067b18c08ee859023816f7ade2c009ae/docs/verification/2026-09-02-recovery-materials.md) | 原厂包、TWRP 来源和核验 |
| [ABL/recovery 门禁](https://github.com/Embracecactus/raphael-linux-bringup/blob/8146d647067b18c08ee859023816f7ade2c009ae/docs/research/2026-09-03-abl-and-recovery-gate.md) | 临时启动不成立，实际 recovery 路径 |
| [备份门禁记录](https://github.com/Embracecactus/raphael-linux-bringup/blob/8146d647067b18c08ee859023816f7ade2c009ae/logs/raphael/2026-09-03-recovery-gate.txt) | 双份校准备份、19 分区安全集 |
| [服务器构建方案](https://github.com/Embracecactus/raphael-linux-bringup/blob/8146d647067b18c08ee859023816f7ade2c009ae/docs/research/2026-09-03-domestic-rootfs-plan.md) | Debian 13、c526、构建依赖及 staging 边界 |
| [持久安装实机证据](https://github.com/Embracecactus/raphael-linux-bringup/blob/8146d647067b18c08ee859023816f7ade2c009ae/logs/raphael/2026-09-03-persistent-linux-boot.txt) | 分区转换、FAT/DTB 修正、Linux/显示/SSH 成功及失败外设 |
| [当前 rootfs 交付](rootfs-delivery.md) | 恢复脚本及辅助依赖、无公开 userdata 镜像 |
| [当前输入交付](boot-inputs-release.md) | 四项 Release 输入、来源和下载验证 |

旧记录中的设备身份、boot ID、私人路径和原用户名不构成新设备操作指令。
本页没有复制原始 session、个人密钥、公钥正文、序列号或 NV 数据。

| 验证项 | 状态 |
| --- | --- |
| 9 月 3 日原机从 Android 转换并持久启动 Debian 服务器 | 历史 PASS；经过 FAT/DTB 多轮修正 |
| 9 月 5 日当前 fork、触摸轮询及桌面状态 | 各自研究文档记录，不能并入最初服务器镜像 |
| 本次 session 与历史文件、当前脚本交叉核对 | 已执行 |
| 本文命令 Bash/Python 语法、引用路径检查 | 文档静态验证；不等于执行设备命令 |
| 本次全新主机 rootfs/内核完整构建 | NOT_RUN |
| 本次另一台手机首次安装与 Android 完整回退 | NOT_RUN |
| 本次实机启动 | `hardware_boot=NOT_RUN` |

**启动依赖已交付；rootfs 已交付历史服务器脚本、辅助依赖、包清单和本首装流程，
尚未交付干净公共镜像、完整桌面配方、可重放 APT 锁及独立首次安装/回退验收。**

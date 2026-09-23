# Raphael 开发工作流

本文主要面向源码构建及已有 Debian 的内核更新。仍运行 Android 的手机，先阅读
[从 Android 到 Linux 的提取、备份、首次安装与恢复流程](android-to-linux-install.md)，
完成自己的数据导出、恢复材料和设备备份；不能直接把 boot/cache 更新入口当成首装工具。

## 两个仓库

| 仓库 | 职责 |
| --- | --- |
| `Embracecactus/linux` | 上游 Linux 历史、Raphael 适配、独立修复提交、板级 defconfig |
| `Embracecactus/raphael-linux-bringup`（本工程） | 构建、打包、部署工具，来源锁定和调试证据 |

本地 `linux/` 是独立 Git checkout，父工程忽略它。父工程不重复提交内核
源码，也不提交构建产物、设备私钥或 NV/校准备份。
内核版本锁在 [`config/raphael/kernel-source.lock.json`](../config/raphael/kernel-source.lock.json)。
当前开发分支为 `raphael/dev`，`master` 保持原始上游内容。
启动依赖发布与边界见 [交付说明](boot-inputs-release.md)。

本轮基底为 `4d7d9486c04d917265f64c55bd23b2cc4fe7749c`，从用户 fork
取得，且与当时核验的 `torvalds/linux master` 相同。该提交的 Makefile
版本仍为 `7.3.0-rc1`。本地采用 shallow/no-tags 获取以节省磁盘；需要查看
旧历史时按需 fetch/deepen，远端 fork 的历史不受影响。

首次准备源码：

```sh
git clone --filter=blob:none --single-branch --branch raphael/dev \
  https://github.com/Embracecactus/linux.git linux
# 首次克隆后固定到本仓库 manifest 对应的完整提交：
git -C linux checkout --detach "$(python3 -c 'import json; print(json.load(open("config/raphael/kernel-source.lock.json"))["commit"])')"
git -C linux remote add upstream https://github.com/torvalds/linux.git
git -C linux fetch --no-tags upstream master
git -C linux branch master upstream/master
```

复现锁定版本时，读取 lock 的 `commit` 并 checkout 该完整提交；开发时在
`raphael/dev` 上修改和提交。更新上游后，应核验源树、重新构建并更新 lock，
不能只修改显示出来的版本号。

## 构建和打包

下载工具需要 Python 3.9+、HTTPS 网络，无需 GitHub 认证。

主机需要 GCC ARM64 交叉工具链、make、bison、flex、OpenSSL/ELF 开发库、
dtc、mtools、dosfstools、cpio、gzip、kmod 和 initramfs-tools。
历史构建使用 `aarch64-linux-gnu-gcc 11.4.0`。Debian/Ubuntu 主机可先安装：

```sh
sudo apt-get update
sudo apt-get install python3 build-essential gcc-aarch64-linux-gnu bison flex \
  libssl-dev libelf-dev bc rsync device-tree-compiler mtools dosfstools \
  cpio gzip kmod initramfs-tools file fastboot
```

全新克隆没有本机 Platform Tools，主机预检显式使用已安装的 Fastboot 路径：

```sh
FASTBOOT="$(command -v fastboot)" bash tools/raphael/flash_fastboot_boot_cache.sh preflight
```

该调用仅校验本地包；软件安装和完整内核编译未在本次隔离下载验证中执行。

```sh
JOBS=16 bash tools/raphael/build_fork_kernel.sh
bash tools/raphael/build_fork_boot_bundle.sh
bash tools/raphael/flash_fastboot_boot_cache.sh preflight
```

构建读取已提交的 `arch/arm64/configs/raphael_defconfig`，不再临时打补丁、
复制旧内核驱动或修改源树。输出集中在：

- `artifacts/build/raphael-mainline/`：唯一正在维护的内核构建目录。
- `artifacts/build/fastboot-raphael-mainline/`：boot/cache 镜像及打包清单。

Git checkout 的 `scripts/setlocalversion` 即使关闭 `LOCALVERSION_AUTO`
也可能追加 `+`。两步均显式传入空的 `LOCALVERSION=`，保持内核与模块 ABI
为 `7.3.0-rc1-raphael-mainline-dev`；后续版本从源树读取，不锁死 7.3。

打包前核验 source HEAD、干净工作树、配置和 EFI/DTB 哈希；模块逐个检查
ARM64 架构、vermagic 和容量。FAT 镜像中的文件须逐字回读一致。
这些命令只在主机生成文件。

## 启动输入和恢复材料

本地必须保留 `artifacts/retained/raphael-boot-inputs/`，其输入哈希锁在
[`boot-inputs.lock.json`](../config/raphael/boot-inputs.lock.json)。
缺失或哈希不符会停止打包；不能从任意旧构建目录自动替代。
Git clone 本身不含这些二进制。固定 Release `boot-inputs-20260924-v1` 提供四项原始输入；
无需 GitHub 登录，以下命令下载、校验并恢复到 retained 目录：

```sh
python3 tools/raphael/fetch_boot_inputs.py
python3 tools/raphael/fetch_boot_inputs.py --check
```

可用 `--download-only /tmp/raphael-boot-inputs-20260924-v1.tar.gz` 只保存归档，
随后用 `--archive FILE` 离线安装。两条路径均执行归档及原始逐文件哈希检查。

Release 提供 retained 二进制及对应源码/许可附件；当前内核、模块和候选 DTB
由锁定的内核源码构建。原 lock 哈希不变，完整说明见 [启动输入交付](boot-inputs-release.md)。
[rootfs 交付](rootfs-delivery.md) 是独立边界；已有 Debian 更新 boot/cache 与
新手机首次安装需要的 userdata、凭据和验证不同。

输入保留了 U-Boot、GRUB、7.1 恢复 initramfs 和 c526 控制 DTB。
打包时删去 initramfs 内唯一的旧模块 ABI，换成新内核的全部模块。
`initramfs-live-modules` 在切换根文件系统时将匹配模块保留在 tmpfs。

默认打包 **c526 控制 DTB**，即早先 RPMh A/B/A 的同一 DTB。
新源码里的 Raphael DTS 会编译，但尚未实机验收，不能将控制 DTB 的结果
当作新 DTS 的验证。haptics 节点在该候选 DTS 中启用，但本树没有对应的
legacy 主线驱动；SLPI 在候选 DTS 中禁用。

新包针对现有 Debian userdata，只包含 boot/cache，采用单默认内核菜单。
2026-09-05 清理后已授权完整刷写这两个分区，并核验整块回读哈希。
原多菜单 cache 与 boot 已完整备份；7.1 恢复包和旧 7.3 包另外保留。
新 fork 首次启动通过，但随后受控重启未在检测窗口内恢复 NCM；手动重启后已恢复。
当前验证边界见 [实机记录](research/2026-09-05-fork-full-flash.md)。

## 补丁状态与上游投稿

RPMh 回退独立为首个提交 `3891bf1e1a5c`。旧基底
`940de590b839` 上的 A/B/A 支持该方向：有回退时到达 7.3 用户态，
无回退时失败并返回 7.1；后续一次持久启动仍发生两次意外重启。
用户随后观察到进入系统后持续运行，启动阶段的两次重启原因仍未闭环。
详见 [RPMh 调试记录](research/2026-09-05-linux73-rpmh-readback-fix.md)。
新基底的构建和打包通过并不替代实机启动测试。
新 fork 已完成一次实机启动，连续软件重启验证仍未通过。

XFCE 桌面已通过实机显示与 FD640 硬件渲染验证。GTX8 16 ms 轮询恢复桌面操作，
用户确认触摸可用；IRQ 通知根因仍未确定，60 秒采集窗口不能作为完整输入事件验收。

`61192118e44c` 将轮询作为可选 bring-up 参数迁入树内，驱动默认继续使用 IRQ；
本机配置 `config/raphael/gt9886-polling.conf` 选择 16 ms。该提交的 Build ID
`624d1f332723d399e2b95a584d77b8e7c5da8faa` 已实机重启通过，taint 为 0，
参数 16 自动生效，`lijian` 已完成密码登录。Onboard 和 accessibility 依赖已安装，
greeter 及 XFCE 会话已配置屏幕键盘。具体边界见
[XFCE 与 GT9886 记录](research/2026-09-05-xfce-gt9886.md)。
Phosh 已作为默认 Wayland 会话验证重启、密码解锁、锁屏唤醒和 Wi-Fi 连接；
系统设置、密钥服务及相机应用的配置与外设限制见
[Phosh 记录](research/2026-09-05-phosh.md)。

供电、音频、SLPI、haptics 和设备树提交保留现有 development/WIP 状态。
供电驱动来自 `GavinLiuOnline/xiaomi_raphael_kernel` 的
`c526b7bf7ebc3fbfee244be252a2c1bd061ca749`，版权和许可证保留；
两处 1.95 A → 1.5 A 的旧脚本替换已经单独提交为开发期充电策略。
这些移植提交尚需按子系统拆分、绑定审查和外设实测，不能整套直接称作
上游就绪的补丁。

后续投稿从独立修复提交准备 patch，按 `MAINTAINERS` 查负责子系统，
在其要求的基底上验证并经人工审阅后发送邮件。向自己的 fork push 是
开发托管；向 Linux 上游投稿是另一项操作。
按当前内核 `Documentation/process/coding-assistants.rst`，本轮只加入
`Assisted-by: LLM`，没有代替人签署 `Signed-off-by`。

## 仓库精简和历史材料

旧版本构建、one-shot/HIL 实验入口、重复 DTS/patch 副本及过时文档已从
本仓库活动目录移除。本次恢复了历史服务器 rootfs 脚本及四个配套文件，日常内核仍使用上面的 fork 入口。
现用 U-Boot 构建脚本只保留 stable EFI 路径。

清理前所有 docs、logs、tools、patches、ports、upstream 和来源锁均归档到
`artifacts/archive/raphael-pre-fork-20260905.tar.gz`。包括尚未提交的外设研究；
归档不进入 Git，恢复时先解压到单独目录，避免覆盖现用工具。
旧的已提交文件也能从 bring-up 仓库的 `8146d647067b` 历史查阅。

原始 source archives、设备备份、7.1 恢复包、旧 7.3 运行包及 vmlinux、
Debian 基础镜像仍在本地。清理清单位于：

- `artifacts/research/retired-build-records-20260905/`
- `artifacts/research/retired-source-records-20260905/`
- `logs/raphael/2026-09-05-fork-repository-cleanup.json`

旧 `third_party/linux-upstream` 的两处未提交修改单独保存在
`logs/raphael/2026-09-05-retired-linux-upstream-local-changes.patch`；未混入 fork。
清理数量和验收见 [迁移记录](research/2026-09-05-fork-migration.md)。

## 部署及采集入口

`flash_fastboot_boot_cache.sh preflight` 不联系设备。后续实际部署需设置
`EXPECTED_FASTBOOT_SERIAL` 为确认属于该手机的值，再使用 `probe` 或
`flash --write-boot --write-cache`；`--reboot` 是显式可选动作。
新包是单菜单 boot/cache，部署前应核对上述恢复布局差异。

设备身份的四项查询合并为一次 Fastboot 调用，完整 cache、boot 写入和可选
reboot 也合并执行，避免本机 USBIP 上反复打开接口导致的停滞。
已验证组合为 Linux Platform Tools 37.0.1 与本机 WSL USBIP 路由；主机
Fastboot 需要有该手机 USB 节点的访问权限。身份、尺寸、哈希和显式双写
检查仍必须全部通过；传输失败不会打印 `flash=PASS`。

`read_fastboot_vars.sh /path/to/fastboot` 同样要求该序列号变量。
`backup_recovery_partitions.sh` 要求 `ADB_SERIAL`，只适用于已确认的
Raphael recovery。USB-NCM 日常采集使用
`collect_linux_acceptance_runtime.sh`，输出进入设备私有目录。
这些入口均不读取串口。

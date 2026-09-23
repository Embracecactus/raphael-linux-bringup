# 启动输入交付：2026-09-23

**目前只公开三文件安全子集，完整四文件恢复仍被固件分发授权阻塞。**
固定版本 `boot-inputs-20260923-v1`，这是 bring-up 依赖基线的部分交付，
不是稳定系统发行版、完整固件或 Debian rootfs。不能仅凭本 Release 首装新手机。

## 下载与恢复

Python 3.9+，无需 GitHub 登录或 Token：

```sh
# 任何人均可取得三个已审核输入；此命令只保存归档，不安装或声称打包就绪。
python3 tools/raphael/fetch_boot_inputs.py \
  --download-only /tmp/raphael-boot-inputs-public-subset-20260923-v1.tar.gz

# 只有自己已合法持有原始、哈希匹配的 recovery-initramfs-7.1 时：
python3 tools/raphael/fetch_boot_inputs.py --local-input-dir /path/to/your-original-inputs
python3 tools/raphael/fetch_boot_inputs.py --check
```

安装目录：`artifacts/retained/raphael-boot-inputs/`。
默认命令 `python3 tools/raphael/fetch_boot_inputs.py` 在已有四项正确时安全重跑；
新克隆缺少未公开的 initramfs 时明确失败，不会留下貌似完整的 retained 安装。
`--archive FILE` 可使用已下载归档，所有检查仍执行。

工具使用独立 [Release 清单](../config/raphael/boot-inputs.release.json) 的固定
HTTPS URL、附件大小和 SHA-256。下载临时文件，校验归档后再解析白名单普通成员；
拒绝路径穿越、额外/重复成员、链接、设备、稀疏和扩展成员。
公开三文件与自己提供的缺项必须全部通过
[原始锁文件](../config/raphael/boot-inputs.lock.json) 的大小与哈希校验才安装。
已有错误文件立即失败，不覆盖；中断后可重跑。不会编译、操作手机或执行附件内容。

历史 lock 还包含恢复 EFI 内核与两份配置，那三项不是当前打包入口的必需 retained
输入，不在本依赖发布范围内。源码构建会提供当前内核及模块，不能用恢复 EFI 替代。

## 四项原输入核验

| 文件 | 字节 | SHA-256 | 公开状态 |
| --- | ---: | --- | --- |
| recovery-initramfs-7.1 | 30745851 | `d5f237df4bfd198b6db708afb8b2d49306be90a973bf932a073b2f61b36db139` | 阻止上传 |
| control-sm8150-xiaomi-raphael.dtb | 108526 | `11a69f06a39c0096cf19fec43ba0739bce547f934ec6a834988293918d7ea211` | 安全子集 |
| raphael-uboot-cache.img | 630784 | `41b90496cf53c47e2bfebf20c28f6c62bbcafae07a023488f75b88a32669db42` | 安全子集 |
| BOOTAA64.EFI | 3551232 | `e9c9cddcba30163e0f17faba01eb8dbb8fcd073bb9f2ac6d8d4b8c11e84a3992` | 安全子集 |

本机四项均为普通文件，全部匹配原锁；未覆盖、清洗或更改它们。
数据归档仅含表中三个可公开的普通文件，无目录、链接或额外恢复包。
逐文件清单、压缩包校验文件、来源声明及单独的源码/许可证归档与数据附件一起提供。
已发布 tag/附件不覆盖，未来完整包必须使用新版本。

## 安全与分发审核

initramfs 在隔离临时目录以自有 newc 解析器读取，只物化普通文件为不可执行的
审阅副本；没有执行 `/init`、脚本或二进制，没有恢复链接或设备节点。
检查了 1613 个条目（1302 个普通文件）、配置、脚本、固件与模块清单，
并扫描私钥标记、公钥行、常见 Token、密码哈希、本机路径和 MAC 字符串。
未发现用户 SSH 私钥/主机私钥、个人公钥、密码哈希、Wi-Fi 配置、个人目录、
NV/校准文件或整机备份。4 处路径特征位于 ADSP/CDSP 厂商固件的构建字符串中；
未发现本工程用户路径。静态扫描不能证明任意二进制绝无隐藏秘密。

**明确阻塞：** initramfs 的 43 个 `usr/lib/firmware/qcom/` 文件与
[历史社区固件树](https://github.com/GavinLiuOnline/xiaomi_raphael_build_kernel/tree/128ac1fec88e7a141cebfab4193c6c4cc512a1d1/firmware-xiaomi-raphael)
全部按内容匹配。其中包含 ADSP、CDSP、IPA、Adreno 固件。该锁定源码树本地与
GitHub 递归目录均无 LICENSE/COPYING/copyright/WHENCE 文件；社区文档还记载
IPA 固件从 Android 线刷包提取。未找到适用于这些原字节的再分发授权。
公开仓库已有文件不等于获得再分发许可，Linux/Debian 的许可证也不能覆盖这些固件。
因此不上传原 initramfs，不删除固件后冒充原哈希。未来须补齐固件授权及整个
initramfs 的对应源码、配置和版权声明闭包，才能另发完整四文件版本。

其余三项已检查嵌入配置和可识别内容，未发现上述敏感模式：

- U-Boot：源码提交 `b5e36b80ecf58b00f4f4245cf411d73ed36832d5`，干净工作树。
  解开 Android 头与 gzip 后的代码和 DTB 均匹配原构建 manifest；固定环境没有设备身份。
  完整上游源码、GPL-2.0/例外、精确配置、环境及构建脚本随源码附件提供。
- GRUB：内嵌版本 `2.12-9+deb13u2`，230 个 ARM64 模块逐字匹配 Debian 官方包，
  唯一附加成员为通用 `grub.cfg`。完整对应 GRUB 源码、Debian 补丁、.dsc、GPL-3
  和 Debian copyright 随附件提供，源码大小/哈希与 .dsc 一致。
- 控制 DTB：c526 原源码的 41 文件 include/许可闭包、历史 builder DTS 补丁与
  runtime USB/display 补丁随附件提供。独立 cpp + dtc **确实复现了旧 DTB 的
  108526 字节与原 SHA-256**；没有全量重编内核，也没有替换当前候选 DTS。
  保留原 BSD/GPL 许可和全部作者版权声明。

来源和重建细节在附件 `BOOT-INPUTS-NOTICE-20260923-v1.md` 及源码包 README。
上游测试源码可能含公开测试样例；附件没有本机身份、私有日志或设备材料。

## 打包与验证边界

输入全部就绪后继续原入口，不另建打包流程：

```sh
JOBS=16 bash tools/raphael/build_fork_kernel.sh
OUTPUT_DIR="$PWD/artifacts/build/my-new-boot-bundle" bash tools/raphael/build_fork_boot_bundle.sh
BUNDLE="$PWD/artifacts/build/my-new-boot-bundle" bash tools/raphael/flash_fastboot_boot_cache.sh preflight
```

打包严格校验源码 HEAD、干净状态、build-manifest、配置、EFI、DTB、模块 ABI，
未放宽任何检查。`preflight` 仅检查本地文件，不联系手机。

本轮原环境的完整 `artifacts/build/raphael-mainline/` O 目录已于 9 月 6 日删除。
留下 `.config`、System.map、vmlinux、manifest 和已打好的 boot/cache；缺少可供
原入口 modules_install 的完整输出树及候选 DTB。源码 HEAD 和保留 manifest 均为
`61192118e44cd9618d4b8114f76266df8581d28f`，保留 .config 哈希一致。
使用独立 OUTPUT_DIR 调用原打包入口，因缺少原构建目录内 build-manifest.txt 失败。
没有伪造构建树、绕过校验或从旧 cache 中取控制 DTB 冒充候选产物。

旧成功包的当前本地 preflight 通过（不是本轮新打包通过）；boot/cache 哈希分别是
`03de919577ce8996d7309d2675f682b21b07bad3349b3f249990a030568439ed` /
`431eeb7d2ee779e475ce416ea7dfa499eddf419e889d9ea8858d5fb08748c77b`。

- 全新主机完整编译：NOT_RUN。
- 本轮复用产物重新打包：BLOCKED，完整 O 目录已删除。
- 本轮手机刷写/启动：`hardware_boot=NOT_RUN`。
- 公开下载与恢复验证：发布后另记，不能用本地 retained 拷贝代替。

历史实机范围与触摸轮询、软件重启、音频/相机等缺口仍以 README 链接的具体日期
记录为准；本轮没有增加实机验收结论。

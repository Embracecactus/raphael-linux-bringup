# 启动输入交付：2026-09-24

固定版本 [boot-inputs-20260924-v1](https://github.com/Embracecactus/raphael-linux-bringup/releases/tag/boot-inputs-20260924-v1)
提供原始锁定的四项输入。这是 bring-up 启动依赖，不是稳定系统、完整固件或 Debian
rootfs；没有 userdata，不能单凭本包完成新手机首装。旧三文件 Release 保持不变，
其审计及当时的阻塞记录保留在 [2026-09-23 报告](boot-inputs-release-20260923.md)。

## 下载、校验和恢复

更新 main 后运行，Python 3.9+，无需 GitHub 登录或 Token：

```sh
python3 tools/raphael/fetch_boot_inputs.py
python3 tools/raphael/fetch_boot_inputs.py --check
```

安装目录为 `artifacts/retained/raphael-boot-inputs/`。正确文件允许重跑；已有文件
大小或哈希不符则停止，不覆盖。只下载及随后离线安装可用：

```sh
python3 tools/raphael/fetch_boot_inputs.py --download-only /tmp/raphael-boot-inputs-20260924-v1.tar.gz
python3 tools/raphael/fetch_boot_inputs.py --archive /tmp/raphael-boot-inputs-20260924-v1.tar.gz
```

[Release 清单](../config/raphael/boot-inputs.release.json) 固定 tag、URL、附件大小与
SHA-256，不使用 latest。下载到临时文件，先校验归档，再检查成员路径、类型、白名单，
拒绝额外/重复成员、目录、链接、设备、路径穿越、稀疏和扩展成员。四项全部通过
[原始锁文件](../config/raphael/boot-inputs.lock.json) 的大小及哈希检查才安装。
不会自动编译、执行下载内容或操作手机。工具及原打包入口的严格检查均未放宽。

## 四项原始输入

| 文件 | 字节 | SHA-256 |
| --- | ---: | --- |
| recovery-initramfs-7.1 | 30745851 | `d5f237df4bfd198b6db708afb8b2d49306be90a973bf932a073b2f61b36db139` |
| control-sm8150-xiaomi-raphael.dtb | 108526 | `11a69f06a39c0096cf19fec43ba0739bce547f934ec6a834988293918d7ea211` |
| raphael-uboot-cache.img | 630784 | `41b90496cf53c47e2bfebf20c28f6c62bbcafae07a023488f75b88a32669db42` |
| BOOTAA64.EFI | 3551232 | `e9c9cddcba30163e0f17faba01eb8dbb8fcd073bb9f2ac6d8d4b8c11e84a3992` |

数据归档只包含上述四个普通文件，没有父目录、链接或额外历史包。本机原输入和历史
lock 均未改动。其他 lock 条目不是当前打包必需 retained 输入，不在本包内。
逐文件清单、SHA256SUMS 和来源声明作为独立附件提供，已发布版本不覆盖。

## 安全、来源与分发依据

2026-09-24 仓库维护者明确确认拥有 43 个厂商固件的公开再分发权，并授权发布。
本次发布据此进行；这不是独立核验的厂商许可文件，也不代表把固件改为 GPL/MIT。
历史固件树未找到许可文件的事实未变，不额外声明修改或再授权权利。

四项均重新核验普通文件类型、大小与 SHA-256。initramfs 在隔离临时目录内以 newc
解析器检查 1613 个条目、1302 个普通文件，审阅副本不可执行，没有执行 `/init`、
脚本或二进制，没有还原设备节点或链接。未发现用户/主机 SSH 私钥、个人公钥、
常见 Token、密码哈希、Wi-Fi 配置、个人目录、NV/校准文件或整机备份。
四处路径模式仍是 ADSP/CDSP 厂商构建字符串，不是本机用户路径。
静态扫描不能保证任意二进制绝无隐藏内容。

来源及配套材料：

- 43 个固件均匹配历史 builder 提交 `128ac1fec88e7a141cebfab4193c6c4cc512a1d1`
  的 `firmware-xiaomi-raphael`。逐成员 SHA-256 清单随 initramfs 材料包提供。
- 335 个普通文件匹配历史 Debian 软件包 MD5 清单，包括全部用户态 ELF 程序及共享库。
  这是来源证据，不把 MD5 当作安全签名。材料包提供实际成员 SHA-256、31 个包的
  确切版本、版权文件及固定 Debian snapshot 源码获取地址。
- 旧模块对应 `fusion-hxf/linux-k20-pro` 提交
  `f72bd7ed5d5d23f419bced5e823906a154d39053`，历史记录无额外源码补丁。
  提供确切内核配置、去除本机路径的构建 manifest、源码获取命令、原始启动脚本。
  材料包未重复内含完整内核/Debian 源码归档，通过固定来源获取；未宣称逐字重建通过。
- U-Boot、GRUB、控制 DTB 对应源码仍使用旧固定 Release 的
  `raphael-boot-inputs-sources-20260923-v1.tar.gz`，URL 与哈希保留在清单中。
  该包的历史说明仍记载当时 initramfs 未发布，以本次新增声明解释后续变化。

新附件 `raphael-initramfs-materials-20260924-v1.tar.gz` 和
`BOOT-INPUTS-NOTICE-20260924-v1.md` 说明具体来源、许可证及获取方法。
没有公开 rootdir、userdata、个人密钥或设备备份。

## 继续构建与验证边界

首次克隆的内核源码准备及依赖安装见 [开发工作流](development.md)。输入恢复后继续：

```sh
JOBS=16 bash tools/raphael/build_fork_kernel.sh
OUTPUT_DIR="$PWD/artifacts/build/my-new-boot-bundle" bash tools/raphael/build_fork_boot_bundle.sh
BUNDLE="$PWD/artifacts/build/my-new-boot-bundle" bash tools/raphael/flash_fastboot_boot_cache.sh preflight
```

`preflight` 仅检查本地文件，不联系手机。当前内核及模块来自锁定源码，Release 提供
retained 输入。原打包脚本替换 initramfs 旧模块 ABI，不另复制打包流程。

原环境完整内核 O 目录已在此前清理，仍不能复用它重新打包；没有为发布重复全量编译。
旧成功包的本地 preflight 通过不能算作本次新包验收。全新主机完整编译未执行，
`hardware_boot=NOT_RUN`。本轮下载及本机验收结果记录于
[2026-09-24 结构化记录](../logs/raphael/2026-09-24-boot-inputs-delivery.json)。

启动依赖与 [rootfs 构建/镜像](rootfs-delivery.md) 分开验收。rootfs 目前交付历史
服务器构建脚本、辅助文件及包清单，未公开镜像，未复现后续 Phosh/XFCE 桌面。
已有 Debian 更新内核与新手机首次安装不同，新设备使用自己的凭据和公钥。
历史实机验证范围及触摸轮询、软件重启、音频/相机等缺口仍以 README 的日期记录为准。

## 发布后验收

新 Release 已公开，标签固定在 `d08148f0a49ad9c6d2b2da6e0ae69c0432a3000a`。
禁用 Git 凭据助手和身份环境，从远端重新克隆该标签；五个附件均匿名下载并核对
大小/SHA-256。主包因普通连接较慢，使用同一固定 Release URL 的八段 HTTP Range，
逐段检查返回范围与总长，合并后再核对完整归档 SHA-256。随后用新克隆中的原工具
`--archive` 安装，四项原锁检查、重复运行和 `--check` 均通过。
未从本机 retained 目录复制输入，未使用 GitHub 身份凭据；普通慢速下载在分段
完整校验后停止，不把它记作一次已完成的默认流式下载。
标签保留发布时提交；本段及结构化记录是随后补入 main 的验收结果。

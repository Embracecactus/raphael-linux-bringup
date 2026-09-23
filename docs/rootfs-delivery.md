# rootfs 材料交付边界

**启动依赖目前交付三项公开输入；initramfs 因固件授权未完成而暂缓。
rootfs 目前交付历史服务器构建脚本、依赖闭包说明与包版本清单，没有交付镜像。**
四项启动输入本来也不包含 Debian userdata，不能命名为完整 ROM。

## 已核对与恢复的材料

从本仓库历史提交 `8146d647067b18c08ee859023816f7ade2c009ae` 恢复：

- `tools/raphael/build_debian_trixie_server.sh`
- `tools/raphael/verify_git_tree.sh`
- `tools/raphael/prepare_runtime_dtb.sh`
- `tools/raphael/raphael-hw-snapshot`
- `tools/raphael/raphael-hw-snapshot.service`

服务器构建脚本的全部四个本地辅助依赖已检查；shell 语法检查通过，
`verify_git_tree.sh` 在保留的 builder 源码上实跑，得到锁定树
`ee3e9a20ba8b20b438ff649e4ced707d54611bb1`。
本轮只修改 SSH 输入：要求显式 `SSH_PUBLIC_KEY`，使用构建者自己的 OpenSSH 公钥，
不创建或读取仓库原设备私钥。其余内容保留历史语义，包括默认禁止覆盖已有输出、
可选的清理/恢复模式。未运行 rootfs 构建、chroot、挂载或镜像写入。

参考过历史 `docs/research/2026-09-03-domestic-rootfs-plan.md` 和
`logs/raphael/2026-09-03-domestic-rootfs-build.txt`。可用 `git show <上述提交>:<路径>`
查阅，但其中本机私钥位置不是新用户的登录方案。

`config/raphael/rootfs-server-packages-20260903.tsv` 是原服务器阶段的 222 项
包名、版本、架构清单，无凭据或本机路径。Debian 包来自签名仓库的 TUNA 镜像，
基础系统是 Debian 13 trixie arm64，通过 mmdebstrap + QEMU user/binfmt 构建。
旧 `apt-inrelease.sha256` 文件为空：没有完整可重放的 APT 快照锁，当前镜像内容
会变化；该包清单是历史证据，不是完整确定性构建锁。

## 外部依赖闭包

| 输入 | 锁定来源/核验 | 当前边界 |
| --- | --- | --- |
| 历史 kernel deb | GavinLiuOnline/xiaomi_raphael_build_kernel 的 kernel-v7.0 Release；SHA-256 `9f1a0ca50c7e0035c0ec8fea84e46dd9e5b04869e3f3506d7aae83ea9d7f230e` | 对应 c526 社区 7.0 内核，不是当前 7.3 fork |
| kernel builder | commit `128ac1fec88e7a141cebfab4193c6c4cc512a1d1`，tree `ee3e9a20ba8b20b438ff649e4ced707d54611bb1` | 固件、ALSA 目录都被脚本消费；固件再分发授权未闭环 |
| Debian 包 | TUNA Debian / Debian Security，trixie | 保留包版本清单；尚未补全源包/签名快照锁 |
| GRUB | Debian `2.12-9+deb13u2` ARM64 | 原 EFI、源码与许可随启动安全子集发布 |
| U-Boot | b5e36b80，单独构建入口 | 不在 rootfs 脚本内构建 |

准备 builder 源码时使用锁定仓库提交的 archive（不要把父仓库误当成它的 Git root）：

```sh
git clone https://github.com/GavinLiuOnline/xiaomi_raphael_build_kernel.git /tmp/raphael-builder-source
mkdir -p third_party/raphael-kernel-builder
git -C /tmp/raphael-builder-source archive 128ac1fec88e7a141cebfab4193c6c4cc512a1d1 \
  | tar -x -C third_party/raphael-kernel-builder
bash tools/raphael/verify_git_tree.sh third_party/raphael-kernel-builder ee3e9a20ba8b20b438ff649e4ced707d54611bb1
```

上面的解包目录必须是新建空目录；已有原材料请保留，改用独立位置及 `BUILDER_SOURCE`。
仅取得上游材料不解决其中固件的分发授权问题，不要将其整体上传到自己的 Release。

历史脚本还依赖 mmdebstrap、qemu-user-static/binfmt-support、ARM64 chroot、
Debian archive keyring、dtc、mtools、dosfstools、e2fsprogs、OpenSSH 工具及脚本
`need` 列出的主机命令。未来在隔离构建环境完成依赖及固件使用许可核对后，
构建调用形式如下；**本轮没有执行，也不宣称干净重建已通过**：

```sh
sudo env SSH_PUBLIC_KEY=/path/to/your-key.pub \
  KERNEL_DEB=/path/to/hash-verified/linux-image-xiaomi-raphael.deb \
  BUILDER_SOURCE=/path/to/verified-builder-archive \
  OUTPUT_DIR="$PWD/artifacts/build/my-new-server-rootfs" \
  bash tools/raphael/build_debian_trixie_server.sh
```

这是构建命令，不是首次安装说明。它产生含构建者公钥的个人镜像，不可默认公开。
新设备生成自己的 SSH host keys，使用自己的用户凭据、公钥与私钥，绝不复制原设备私钥。

## 基础模板和当前桌面的区别

本机保留 `artifacts/retained/debian13-base/raphael-userdata-rootfs.img`，
1138638848 字节，本轮只读重新计算与历史构建清单一致，hash 为
`b6f55322aac6edd088a2dcce395c66a6f102da299d2d1a5f52ae537b026e94ac`。
只读 debugfs 检查发现 `/home/raphael/.ssh/authorized_keys`（103 字节），
因此它不是无个人身份的公开基础模板。未输出密钥正文，没有修改或上传镜像。
`/etc/ssh` 未见 host 私钥；这不等于完成整个镜像的敏感数据和许可审计。
没有确认到可直接公开的干净模板。

历史服务器 rootfs 使用 locked accounts、key-only SSH、USB NCM/ACM、first-boot
host key 生成与 Qualcomm 服务。原报告记录使用已验证 staging 续做镜像，
完整从零 clean rebuild 当时也仍是待办。
之后在设备上加入 XFCE/LightDM、Onboard、Phosh/Wayland、Squeekboard、
GNOME Keyring/PAM、密码登录与触摸轮询配置；这些由现有
[XFCE](research/2026-09-05-xfce-gt9886.md)、
[Phosh](research/2026-09-05-phosh.md) 文档记录，未汇成可复现桌面镜像配方。
原 userdata、使用过的 rootdir 和原设备镜像本轮均不公开。

首次安装新手机仍缺无个人数据模板、完整固件/源包许可闭包、干净重建和独立设备
安装验收。已有 Debian 设备更新内核则使用当前 fork 的 boot/cache 打包入口，
保留自己的 userdata。这两种流程不能混称“首次安装可复现”。

# Raphael Linux bring-up

Redmi K20 Pro（`raphael`）的 Linux 构建和部署工具。
内核源码与适配提交维护在 [Embracecactus/linux](https://github.com/Embracecactus/linux)
的 `raphael/dev` 分支；本仓库负责把该源码构建为可核验的启动包。

## 启动输入交付

[固定 Release：boot-inputs-20260924-v1](https://github.com/Embracecactus/raphael-linux-bringup/releases/tag/boot-inputs-20260924-v1)
提供 **原始恢复 initramfs、U-Boot、GRUB EFI、历史控制 DTB 四项启动输入**。
厂商固件按仓库维护者确认的公开再分发权发布，详细依据及源码获取说明见下方文档。
没有 userdata，不是完整稳定 ROM，不能仅凭本包首次安装新手机。

```sh
python3 tools/raphael/fetch_boot_inputs.py
python3 tools/raphael/fetch_boot_inputs.py --check
```

下载后四项均恢复到 `artifacts/retained/raphael-boot-inputs/`，大小与 SHA-256
必须匹配原锁。无需 GitHub 登录；已有不匹配文件会停止，不覆盖。

[输入核验、下载与限制](docs/boot-inputs-release.md) ·
[rootfs 构建材料与缺口](docs/rootfs-delivery.md)。

## 当前入口

```sh
JOBS=16 bash tools/raphael/build_fork_kernel.sh
bash tools/raphael/build_fork_boot_bundle.sh
bash tools/raphael/flash_fastboot_boot_cache.sh preflight
```

以上三条命令只构建和校验本地文件。首次准备源码、主机依赖、保留输入
及部署说明见 [开发工作流](docs/development.md)。

| 路径 | 内容 |
| --- | --- |
| `linux/` | 独立内核 checkout，父仓库忽略 |
| `third_party/raphael-kernel-builder/` | 随 Git 提供的完整历史 builder，613 文件；[来源及校准数据说明](third_party/raphael-kernel-builder.NOTICE.md) |
| `config/raphael/` | 内核提交号、启动输入哈希 |
| `tools/raphael/` | 构建、下载、打包、部署及历史 rootfs 工具 |
| `docs/` | 开发说明、RPMh 回归证据、迁移验收 |
| `logs/raphael/` | 本轮构建验收及关键 A/B/A 记录 |
| `artifacts/` | 本地构建、恢复材料和历史归档，不进入 Git |

## 验证状态

新 fork 基于 `4d7d9486c04d`，首次刷写与下述启动验证对应 `08de36271e6a`。
内核、模块、Raphael DTB 已完成主机编译；913 个模块 ABI、initramfs 容量、
FAT 文件回读及 Fastboot 镜像预检通过。清理后已完整刷写 boot/cache，
两分区整块回读 SHA-256 一致；手机运行的 Build ID 与新 fork 编译结果一致。
首次启动观察到 448 秒，8 核在线、USB-NCM/SSH 正常、失败服务为 0。

随后一次受控软件重启未在 180 秒检测窗口内恢复 NCM，手动重启后已恢复同一新内核；
原因待确认，连续重启验证未通过。显示、蓝牙、音频等外设仍有待处理日志，当前不能标为
完整稳定版本。实机使用保留的 c526 控制 DTB，新候选 DTS 尚未验收。

XFCE 已在手机屏幕显示，Mesa 使用 Adreno 640 硬件加速。GT9886 经 16 ms 轮询
恢复桌面操作，用户已确认触摸可用；IRQ 通知根因仍未解决，完整输入事件验收仍待完成。

开发提交 `61192118e44c` 的树内可选轮询已实机重启通过，Build ID 为
`624d1f332723d399e2b95a584d77b8e7c5da8faa`、taint 为 0，模块参数 `16` 自动生效。
驱动默认仍使用 IRQ，由本机配置 `config/raphael/gt9886-polling.conf` 选择轮询。
密码登录保持启用；Onboard 已配置为 greeter 和 `lijian` XFCE 会话中的屏幕键盘。
Phosh 已作为默认手机桌面重启并解锁，使用 Wayland 与 Squeekboard；XFCE 保留为备用会话。

- [RPMh 回退与 A/B/A 证据](docs/research/2026-09-05-linux73-rpmh-readback-fix.md)
- [本轮迁移、清理与验收](docs/research/2026-09-05-fork-migration.md)
- [全量 boot/cache 刷写与实机验证](docs/research/2026-09-05-fork-full-flash.md)
- [XFCE 与 GT9886 触摸验证](docs/research/2026-09-05-xfce-gt9886.md)
- [Phosh 手机桌面](docs/research/2026-09-05-phosh.md)
- [确切内核版本](config/raphael/kernel-source.lock.json)

## USB 连接

```sh
ssh -i /path/to/your-own-private-key your-user@172.16.42.1
```

新设备使用自己的用户凭据和公钥；示例路径须换为你自己的私钥，不能索取或复用原设备私钥。

只读状态采集使用 `tools/raphael/collect_linux_acceptance_runtime.sh`。
Fastboot/ADB 操作须显式指定已确认手机的序列号。私钥、原始设备信息、
NV/校准备份、旧工作文件归档均保留在本地忽略目录中。

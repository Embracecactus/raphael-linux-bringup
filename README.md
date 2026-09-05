# Raphael Linux bring-up

Redmi K20 Pro（`raphael`）的 Linux 构建和部署工具。
内核源码与适配提交维护在 [Embracecactus/linux](https://github.com/Embracecactus/linux)
的 `raphael/dev` 分支；本仓库负责把该源码构建为可核验的启动包。

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
| `config/raphael/` | 内核提交号、启动输入哈希 |
| `tools/raphael/` | 10 个现用构建、打包、部署及采集文件 |
| `docs/` | 开发说明、RPMh 回归证据、迁移验收 |
| `logs/raphael/` | 本轮构建验收及关键 A/B/A 记录 |
| `artifacts/` | 本地构建、恢复材料和历史归档，不进入 Git |

## 验证状态

新 fork 基于 `4d7d9486c04d`，内核提交为 `08de36271e6a`。
内核、模块、Raphael DTB 已完成主机编译；913 个模块 ABI、initramfs 容量、
FAT 文件回读及 Fastboot 镜像预检通过。清理后已完整刷写 boot/cache，
两分区整块回读 SHA-256 一致；手机运行的 Build ID 与新 fork 编译结果一致。
首次启动观察到 448 秒，8 核在线、USB-NCM/SSH 正常、失败服务为 0。

随后一次受控软件重启未在 180 秒检测窗口内恢复 NCM，手动重启后已恢复同一新内核；
原因待确认，连续重启验证未通过。显示、蓝牙、音频等外设仍有待处理日志，当前不能标为
完整稳定版本。实机使用保留的 c526 控制 DTB，新候选 DTS 尚未验收。

- [RPMh 回退与 A/B/A 证据](docs/research/2026-09-05-linux73-rpmh-readback-fix.md)
- [本轮迁移、清理与验收](docs/research/2026-09-05-fork-migration.md)
- [全量 boot/cache 刷写与实机验证](docs/research/2026-09-05-fork-full-flash.md)
- [确切内核版本](config/raphael/kernel-source.lock.json)

## USB 连接

```sh
ssh -i artifacts/device-private/raphael-linux-id_ed25519 raphael@172.16.42.1
```

只读状态采集使用 `tools/raphael/collect_linux_acceptance_runtime.sh`。
Fastboot/ADB 操作须显式指定已确认手机的序列号。私钥、原始设备信息、
NV/校准备份、旧工作文件归档均保留在本地忽略目录中。

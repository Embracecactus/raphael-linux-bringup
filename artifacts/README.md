# 本地材料（不提交二进制）

- `build/raphael-mainline/`：当前 fork 的内核、模块及 DTB。
- `build/fastboot-raphael-mainline/`：当前 fork 的 boot/cache 包。
- `retained/raphael-boot-inputs/`：按 `config/raphael/boot-inputs.lock.json` 核验的输入。
- `retained/validated-7.3-symbols/`：此前手机运行内核的 vmlinux。
- `retained/debian13-base/`：Debian 基础安装镜像。
- `device-private/`：私钥、原始运行记录、NV/校准及恢复备份。
- `downloads/`：原始源码归档、固件、工具链和恢复材料。
- `archive/`：退役工作文件及 Fusion 参考源码的压缩归档。
- `research/retired-*-records-20260905/`：清理清单及旧构建配置/符号映射。

`build/` 中还保留一个旧 7.3 运行包和一个 7.1 恢复包；它们不是当前开发源码。
活动源码只有项目根目录的 `linux/`。完整使用说明见 `docs/development.md`。

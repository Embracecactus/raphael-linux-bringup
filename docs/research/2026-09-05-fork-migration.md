# Linux fork 迁移与 bring-up 仓库精简（2026-09-05）

## 已完成

内核仓库 `Embracecactus/linux` 的本地 `raphael/dev` 分支含 11 个独立提交，
HEAD 为 `08de36271e6a23f98712a0719614d2d0a60f1556`，基底为 `4d7d9486c04d917265f64c55bd23b2cc4fe7749c`。
`master` 保持基底内容，另配置 `upstream` 指向 `torvalds/linux`。
修改直接存在于内核提交中，现用构建不再应用临时 overlay。

bring-up 仓库移走 284 个旧脚本、文档、日志、重复补丁和候选源码文件，
保留 10 个工具文件、两个输入锁、开发说明和必要回归证据。
现用入口和目录见 [开发工作流](../development.md)。

## 主机验证

| 检查 | 结果 |
| --- | --- |
| 完整 Image.gz、vmlinuz.efi、modules、Raphael DTB 构建 | PASS |
| 配置来源 | 旧已运行 7.3 配置经新基底 olddefconfig/savedefconfig；新增 AIROHA_CPU_PM_DOMAIN 默认项 |
| 内核 release | `7.3.0-rc1-raphael-mainline-dev` |
| 内核 Build ID | `3a76eddf6eab35445aa5c7d382d8963018497898` |
| 模块 | 913 个 ARM64，逐个 vermagic 核验 |
| initramfs 模块目录 | 45514752 bytes，低于 128 MiB handoff 预算 |
| boot/cache | 完整 128 MiB / 256 MiB；FAT16 文件逐字回读与 fsck 通过 |
| Fastboot preflight | PASS；主机检查，无设备交互 |
| 错误 source HEAD / overlay manifest | 均在打包前拒绝 |
| shell syntax、Git whitespace | PASS |
| 新基底实机启动 | NOT_RUN |

EFI SHA-256：`6df2fb87e46a8992088ef996b5a9565b44d8d3c4016b80840ff3606613c93e57`。

cache SHA-256：`b67344ef921e3d8fbf3c816b4bdb66c21bc0fe2815b9e5a0ba4f2305404a55db`。

包内使用原 c526 控制 DTB `11a69f06a39c0096cf19fec43ba0739bce547f934ec6a834988293918d7ea211`，
不是本次构建的候选 DTB。新 DTS 仅完成编译，外设功能尚未全部验收。

11 个提交的 checkpatch 使用 `--no-signoff`：0 errors，21 warnings。
回退提交本身为 0 errors / 0 warnings。其余警告属于移植代码的既有风格、
新增文件维护者登记、短 Kconfig help、长行及 binding/实现尚未细拆。
为保持移植对照没有夹带供电驱动的风格重写；这些提交仍属 development/WIP，
正式投稿前应逐子系统处理，而非整套发送上游。
没有代替用户添加 DCO 签名；新增提交含 `Assisted-by: LLM`。

完整编译日志压缩保留在 `artifacts/archive/2026-09-05-fork-kernel-build.log.gz`。
构建摘要、打包、checkpatch、负向身份校验和预检结果位于
`logs/raphael/2026-09-05-fork-*`，机器可读总表为
`2026-09-05-fork-migration-summary.json`。

## 清理与保留

删除前逐项核验并记录的旧源码/构建占用合计 **49,409,998,190 bytes（约 46.0 GiB）**。
这是退役文件的统计；新 fork、新构建和归档也占用空间，不将其当作文件系统净释放值。
完整记录保存在 `artifacts/research/retired-*-records-20260905/`。

清理前工作文件归档：`artifacts/archive/raphael-pre-fork-20260905.tar.gz`，
5,299,572 bytes，SHA-256 `daf309996e645072d492cafca150a24c809e954e65a4a57f45b97950a286da8e`。
它包含清理前未提交的外设研究、旧来源锁和脚本，可单独解压查阅。
Fusion 7.1 参考源码也已单独归档并删除展开目录。
已提交的旧内容还可从 bring-up 的 `8146d647067b` 历史读取。

保留当前 fork 的构建、一个旧 7.3 运行包及 vmlinux、一个 7.1 恢复包、
Debian 基础镜像、原始下载和所有设备私有备份。没有操作 COM 端口，
没有刷写、重启手机或改变其当前运行系统。

## 发布和运行边界

本记录描述本地提交与主机验收。尚未向两个 GitHub 仓库 push，
没有创建上游 PR 或发送邮件。
先检查本次提交，再发布 `linux:raphael/dev` 与 bring-up 对应提交，
两者以 `config/raphael/kernel-source.lock.json` 关联。

此前 940 基底加 RPMh 回退的实机结果独立保留在
[RPMh 记录](2026-09-05-linux73-rpmh-readback-fix.md)。用户确认其进入系统后
持续运行；先前两次中间重启仍未定位，新基底不能直接标为稳定实机版本。

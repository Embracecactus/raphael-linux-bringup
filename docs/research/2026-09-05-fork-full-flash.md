# 清理后完整 boot/cache 刷写与实机验证（2026-09-05）

完整刷写和镜像回读通过，新 fork 内核两次到达 Debian 用户态；其间一次
受控软件重启停在 GRUB 启动内核后的画面，用户手动重启后恢复。
**连续重启验证未通过，不能将此版本标为稳定。**

## 镜像与写入范围

| 项目 | 身份或结果 |
| --- | --- |
| 内核源码 | `Embracecactus/linux:raphael/dev`，`08de36271e6a23f98712a0719614d2d0a60f1556` |
| 上游基底 | `4d7d9486c04d917265f64c55bd23b2cc4fe7749c` |
| release | `7.3.0-rc1-raphael-mainline-dev` |
| 运行内核 Build ID | `3a76eddf6eab35445aa5c7d382d8963018497898`，两次成功启动均匹配 |
| boot | 完整 134217728 bytes，Fastboot 写入和整块回读通过 |
| cache | 完整 268435456 bytes，Fastboot 写入和整块回读通过 |
| boot SHA-256 | `03de919577ce8996d7309d2675f682b21b07bad3349b3f249990a030568439ed` |
| cache SHA-256 | `b67344ef921e3d8fbf3c816b4bdb66c21bc0fe2815b9e5a0ba4f2305404a55db` |
| EFI SHA-256 | `6df2fb87e46a8992088ef996b5a9565b44d8d3c4016b80840ff3606613c93e57` |
| 实际使用 DTB | c526 控制 DTB：`11a69f06a39c0096cf19fec43ba0739bce547f934ec6a834988293918d7ea211` |

“全量”指本包 boot/cache 两个分区的完整镜像。userdata 继续使用原 Debian，
没有擦除或重刷 userdata、基带/NV、固件、校准、recovery、dtbo 或 vbmeta。
旧 boot 与 cache 在写入前完整读取、压缩备份，并解压验证字节数和哈希。
旧 boot 本来就与保留 U-Boot 镜像相同；本次仍完整写入，并重新验证。
旧 cache 的 SHA-256 为 `23a7aa602c18dd9a83be901b610ae831d236929a027a2ce3e70e32e591eeb581`。

新 cache 内 `/EFI/BOOT/grub.cfg` 只有一个默认内核，`timeout=0`，没有 one-shot
标志或自动回退入口。实机回读该配置和 EFI/DTB 文件哈希均匹配。
本次使用控制 DTB 的结果不构成对新源码候选 DTS 的实机验收。

## 启动与重启观察

| 顺序 | 操作与证据 | 结果 |
| --- | --- | --- |
| 1 | 完整刷写后 Fastboot reboot；boot ID `7f103d66-d000-42bf-a602-eb2304d81bc6` | 新 Build ID 匹配；运行至 448.51 秒，8 核在线、tainted=0、systemd running、失败服务 0、NCM/SSH active |
| 2 | 在上述用户态执行一次 `systemctl reboot` | 180 秒检测窗口内没有恢复 NCM；原计划第二次软件重启未执行 |
| 3 | 用户提供停滞画面后手动重启；boot ID `27e40fae-e19c-42b4-95fd-92141e5896d3` | 相同新 Build ID；观察至 277.37 秒，状态正常，两分区整块哈希仍匹配 |

用户的第 2 次画面重新出现 U-Boot、UFS 枚举、GRUB 的
`Booting 'Debian Raphael Linux 7.3 persistent'` 和 `No RNG device`。
因此手机确已重新经过引导程序；最后可见字符串不能定位为 RNG/EFI 故障，
也不能排除内核启动后未能更新屏幕。只有一次失败样本，不能据此断定所有
软件重启必现、所有手动重启必成，或归因于多内核菜单。

恢复后 journal 的前一启动是顺序 1，其尾部记录正常停止服务并进入
systemd-shutdown；顺序 2 未留下新的 journal boot ID。
当前 `/sys/fs/pstore` 为空，`/var/lib/systemd/pstore/dmesg-ramoops-0` 是旧
`7.0.0-sm8150-gc526b7bf7ebc-dirty` 的显示快照崩溃记录，明确排除作为此次证据。
`watchdog did not stop` 后有 systemd-shutdown 接管 30 秒 watchdog 的记录，
单独这行也不能证明此次失败由 watchdog 引起。没有根据这些不充分证据修改内核。

手机时钟仍停在 2026-04-14 附近，不能用其墙钟计算跨启动耗时；采用主机
事件记录、boot ID 和内核运行时间区分本次操作。以上是有限次数观察，
不是长时间压力、休眠、冷启动或完整外设验收。

## 运行验收与未完成项

- 8 核在线，CPU 频率驱动工作；新 ABI 的 913 个模块位于 128 MiB tmpfs，
  `/usr/lib/modules` 挂载来源为 `raphael-modules`。
- USB-NCM、SSH 可用，root 为原 userdata 的可写 ext4，cache 以只读 FAT 挂载。
- DRM 报告 DSI connected、`msmdrmfb` 1080×2340；GPU 驱动绑定，modem/CDSP/ADSP
  remoteproc 为 running。这些是状态采集，不代表画面、GPU 渲染或通信功能验收。
- 两次成功启动日志未出现此前 RPMh 写入超时 / Call trace，内核 tainted=0。
- 仍有显示 SMMU context fault、缺少蓝牙 `qca/crbtfw21.tlv`、缺少
  `regulatory.db`、SLIMbus QMI timeout、SoundWire 端口不匹配等日志。
  ALSA 未枚举声卡；Wi-Fi 未关联，未测试蓝牙、音频、触摸和相机。

下一步需针对软件重启后的早期启动保留有效证据并定位根因；本轮已完成
用户要求的清理后刷写验证，但该稳定性问题保持未解决状态。手机保留在恢复后的
新 fork 内核运行态，未继续重复重启。

## 刷写工具改动与记录

WSL USBIP 路由下，分开执行 getvar 曾在重新打开接口后停滞。
现将四项身份查询合并执行，cache/boot 写入与可选 reboot 也在同次调用中完成。
同一已确认手机的产品、解锁、尺寸及主机镜像哈希门全部保留，查询超时为 20 秒。
实机 Platform Tools 37.0.1 的实际两分区写入与回读通过；10 项主机模拟用例
覆盖拒绝错误身份、缺少返回值、错误尺寸、缺少双写开关和错误退出处理。
模拟测试仅检验脚本行为，实际传输由实机记录证明。

没有访问任何 COM 端口，也没有操作其他物理设备。
原始设备日志、分区备份及 pstore 均保存在忽略目录
`artifacts/device-private/20260905-fork-full-flash/`。

- [机器可读验证摘要](../../logs/raphael/2026-09-05-fork-full-flash-summary.json)
- [脱敏刷写结果](../../logs/raphael/2026-09-05-fork-full-flash.log)
- [主机脚本门检查](../../logs/raphael/2026-09-05-fork-flash-gate-validation.json)

本记录不改变构建时清单中历史的 `hardware_boot=NOT_RUN`；部署后的结论单独
记录。代码与记录保存在本地，未向两个 GitHub 仓库 push，也未提交上游 PR。

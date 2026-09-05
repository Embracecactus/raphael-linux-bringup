# Raphael 7.3 RPMh 回退证据

## 当前结论

在 Redmi K20 Pro / SM8150 上，回退 regulator 自动 RPMh 读回后，旧
`940de590b839f71d6dc846160534bf202401b8b7` 基底的 7.3 多次到达用户态。
A/B/A 支持这条修复方向；随后一次持久启动中途仍重启两次。
用户后来确认进入系统后持续运行，不能据此倒推启动阶段已完全修复。

内核 fork 的独立回退提交是 `3891bf1e1a5c`。它移除 regulator 的自动
voltage/enable/mode 读取，保留写投票和独立 BOB bypass 修复。
回退是 downstream workaround，硬件/固件读响应机制和普适修复尚未证明。

上游接入读回的提交为 `09d99ff7fc3c802c9b31ded9ffdf992d966a0835`
（`regulator: qcom-rpmh: readback voltage/bypass/mode set during bootup`）。
regulator 注册时的 sysfs 可见性检查可调用 voltage getter，进入同步读路径；
另一路来自 probe 初始模式读取。详见 [提交来源](2026-09-05-regulator-rpmh-readback-subcommit.md)。

## 同源 A/B/A

三次使用同一 940 基底、配置、c526 控制 DTB、cmdline、U-Boot/GRUB 和
Debian 根文件系统，实验变量是 regulator 读回回退。

| 测试 | 读回回退 | 最终运行结果 | boot ID |
| --- | --- | --- | --- |
| A1 | 有 | 7.3，8 核，失败服务 0 | `5cc250a6-fb76-49d0-adb8-64192272d1a6` |
| B | 无 | 候选失败，重启返回 7.1 | `d332d451-3982-4d92-9051-ca4bbfab0470` |
| A2 | 有，同一产物 | 7.3，8 核，失败服务 0 | `a964be5d-bca5-4d2d-af1f-9f4be599befb` |

三份原始观察保留在 `logs/raphael/`：

- `2026-09-05-73-readback-repair-current-monitor.jsonl`
- `2026-09-05-73-clean-control-monitor.jsonl`
- `2026-09-05-73-readback-repair-repeat-monitor.jsonl`

其中 PASS 表示观察到了相应用户态，不表示连续启动稳定性验收通过。
原有完整回归过程、旧实验命令和 0022 补丁原件已归入
`artifacts/archive/raphael-pre-fork-20260905.tar.gz`。

## 已测试身份

| 项目 | SHA-256 / Build ID |
| --- | --- |
| 原始补丁 0022 | `ba7cd749bf966b3849fd39dc222adf552c12bc16fc6ae8a8419e81671f325f31` |
| 配置 | `cf66624bb856ef5f70577f414ee9df3314f5fbf6cc16d6a75805c6b25fc64c5e` |
| 控制 DTB | `11a69f06a39c0096cf19fec43ba0739bce547f934ec6a834988293918d7ea211` |
| 修复 EFI | `d2837d24ca50fc85f0ca12f9732773617c0ca3d1cfa4095d327a45c2e4949ae2` |
| 修复 initramfs | `dde58eeb17aee3ddb7ebd94fc19067dca18bbadf272c50a140c03c7f7fb8213a` |
| 修复 Build ID | `541475b8c32e49e0c45dd4afbd809352b576424b` |
| 无回退对照 Build ID | `af70153c78c287f36779adba204d4d30c67a2f17` |

旧 7.3 可启动包保留在 `artifacts/build/fastboot-linux-7.3-rpmh-readback-repair/`，
符号文件保留在 `artifacts/retained/validated-7.3-symbols/vmlinux`。
基底源码与完整 O 目录已退役，配置、System.map 和构建清单另行保留。
新 fork 基底 `4d7d9486c04d` 的构建结果与这些旧实机结果分别记录。

## 下一次实机验收

读取确切内核 Build ID、新 boot ID、8 核在线、失败服务及 RPMh/IRQ 日志；
同时观察是否发生中间整机重启。一次最终 SSH 成功不足以关闭启动稳定性。
GRUB 多菜单只选择一个内核；已消费标记本身不证明重启原因。
本次迁移没有执行手机重启、刷写或修改 watchdog 配置。

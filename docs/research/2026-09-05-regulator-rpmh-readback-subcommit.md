# regulator RPMh 启动 readback 的单独提交

`b3438e5ca785565a65ef231bc03cd5a05c3be5c7`（`regulator-v7.3` merge）中，把 RPMh resource read 接入 regulator 启动路径的是单个提交 [`09d99ff7fc3c802c9b31ded9ffdf992d966a0835`](http://mirrors.hust.edu.cn/git/linux.git/commit/?id=09d99ff7fc3c802c9b31ded9ffdf992d966a0835)：`regulator: qcom-rpmh: readback voltage/bypass/mode set during bootup`。

作者是 Kamal Wadhwa，作者时间 `2026-08-01 13:30:29 +0530`，第一父为 `abd14bebb87e0fa2749371272c8b31d6ee5f0a36`。公开原始补丁为 [HUST cgit patch](http://mirrors.hust.edu.cn/git/linux.git/patch/?id=09d99ff7fc3c802c9b31ded9ffdf992d966a0835)，提交消息中的原始 Link 为 <https://patch.msgid.link/20260801-b4-read-rpmh-v5-v6-3-9fcb54928523@oss.qualcomm.com>。

其第一父 diff 只有一个文件，并同时加入 voltage readback、mode/bypass readback 和 `rpmh_regulator_determine_initial_mode()`；后者在 regulator 注册后调用。`rpmh_regulator_vrm_get_voltage_sel()` 通过新 helper 调 `rpmh_read()`。因此这两个启动路径不是两个提交。完整提交说明见 `artifacts/research/bisect-history/09d99ff7-full-message.txt`，原始 diff 见 `rawdiff-abd14beb-to-09d99ff7.patch`。

消息仅描述 bootloader 设置的 voltage/mode/bypass 和避免重复写入；没有声明适用的 SoC 或 RSC 版本，不能由此推断 SM8150/Raphael 的适用性。该提交依赖同一 regulator merge 所含的 API 提交 `edbafe65eef2b58625db1e113fbbfb1fe10c0291`（`soc: qcom: rpmh: Add support to read back resource settings`）。

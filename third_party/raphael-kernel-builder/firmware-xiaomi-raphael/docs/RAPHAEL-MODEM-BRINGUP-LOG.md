# Xiaomi Raphael (K20 Pro) — Linux 7.0 Modem 调通记录与总结

> 设备：Xiaomi Raphael (SM8150)  
> 内核：`7.0.0-sm8150-gc526b7bf7ebc-dirty`  
> 记录日期：2026-06-17  
> SSH：`user@172.16.42.1`（sshpass 调试）

---

## 1. 最终状态一览

| 层级 | 状态 | 说明 |
|------|------|------|
| modem.mdt 固件加载 | ✅ | PAS 启动，`modem is now up` |
| GLINK / RPMSG | ✅ | Modem 上 10+ 通道（IPCRTR、DATA*、DS 等） |
| qrtr_smd 桥接 | ✅ | 3 个 IPCRTR 已绑定（ADSP/CDSP/Modem） |
| QMI 通信 | ✅ | `qrtr://0` 为 modem 节点，IMEI 可读 |
| SIM / 搜网 | ⏸️ | 测试时未插卡，`no-atr-received` 属正常 |
| IPA 数据面 | ❌ | 加载 `ipa` 后 modem IPA HWP 崩溃 |
| 蜂窝网卡 `rmnet_ipa0` | ❌ | 依赖 IPA 握手成功，当前未出现 |
| 蜂窝上网 | ❌ | 需 IPA + SIM + WDS 拨号 |

**一句话：控制面（QMI）已通，数据面（IPA/rmnet）未通。**

---

## 2. 用户侧已安装 / 配置的内容

### 2.1 固件

路径：`/lib/firmware/qcom/sm8150/Xiaomi/raphael/`

| 文件 | 作用 |
|------|------|
| `modem.mdt` + `modem.b00`–`modem.b31` | MPSS modem 主固件（MDT 多镜像） |
| `adsp.mdt`、`cdsp.mdt` | ADSP/CDSP 固件 |
| `modemr.jsn`、`modemuw.jsn` | ServReg 域描述 |
| `modem_pr/mcfg/` | 运营商 MBN 配置（VoLTE/APN 等） |

IPA 固件（通用 mainline）：

| 文件 | 路径 |
|------|------|
| `ipa_fws.mdt` + `ipa_fws.b00`–`b04` | `/lib/firmware/qcom/` |
| `ipa_uc.mdt` + `ipa_uc.b00`–`b02` | `/lib/firmware/qcom/` |

### 2.2 内核模块（设备上已有）

```
/lib/modules/7.0.0-sm8150-gc526b7bf7ebc-dirty/kernel/drivers/net/ipa/ipa.ko
```

配置片段（`raphael.config`）：

```kconfig
CONFIG_QRTR=y
CONFIG_QRTR_SMD=y
CONFIG_QCOM_IPA=m
CONFIG_QCOM_Q6V5_PAS=m          # 实际运行时已加载
CONFIG_QCOM_RMTFS_MEM=y
```

### 2.3 用户态：自编译 libqmi（带 QRTR）

在 `~/libqmi-main` 编译安装：

```bash
rm -rf build
meson setup build \
  --prefix=/usr \
  -Dqrtr=true \
  -Dcollection=basic \
  -Dintrospection=false \
  -Dgtk_doc=false
ninja -C build
sudo ninja -C build install
sudo ldconfig
```

验证：

```bash
pkg-config --variable=qmi_qrtr_supported qmi-glib   # 应输出 1
qmicli --version                                   # 1.32.0
```

> 系统自带的 `libqmi-utils` **无 QRTR 支持**，`qmicli -d qrtr:0` 会报 `URI is not a local file path`。必须用自编译版。

### 2.4 开机模块加载（用户配置）

```bash
# /etc/modules-load.d/qrtr.conf
qrtr_smd
qcom_pd_mapper
```

> **注意：暂不要将 `ipa` 写入 modules-load.d**，见第 5 节。

---

## 3. 远程调试操作记录（Agent 通过 SSH 执行）

连接方式：`sshpass -p '***' ssh user@172.16.42.1`

### 3.1 诊断命令与结果

| 操作 | 结果 |
|------|------|
| 检查 `ipa.ko` 是否存在 | ✅ 已在 `/lib/modules/.../ipa.ko` |
| `lsmod \| grep ipa` | `ipa` 已加载（233472 bytes） |
| `ls /sys/bus/rpmsg/devices/` | 27 个 RPMSG 设备，含 modem `4080000...IPCRTR` |
| remoteproc 状态 | modem/adsp/cdsp 均为 `running` |
| `ip link show \| grep rmnet` | 无结果 |
| `modprobe qrtr_smd` | 成功，3 个 IPCRTR 绑定到 `qcom_smd_qrtr` |
| `modprobe qcom_pd_mapper` | 成功 |

### 3.2 IPA 加载实验

| 步骤 | 现象 |
|------|------|
| 首次 `modprobe ipa` | 驱动初始化成功；sysfs 曾出现 `rmnet_ipa0` |
| 未先加载 `qrtr_smd` 时 | `error -110 awaiting init driver response`（QMI 超时） |
| `rmmod ipa` → 再 `modprobe ipa` | `unexpected init_completed response` |
| 重启 modem + 加载 ipa | modem 约 3 秒后崩溃（见下） |
| **加载 `ipa` 后稳定复现** | modem fatal：`ipa_hwp_init_rsp_timer_cb: didnt rx any ind frm HWP` |
| `rmmod ipa` | 停止加载 ipa 后 modem 可恢复稳定运行 |

### 3.3 崩溃日志（关键）

```
qcom_q6v5_pas 4080000.remoteproc: fatal error received:
  ipa_hwp_init.c:414:IPA Assert: 0 failed:
  ipa_hwp_init_rsp_timer_cb: didnt rx any ind frm HWP
remoteproc remoteproc0: crash detected in modem: type fatal error
ipa 1e40000.ipa: received modem crashed event
```

### 3.4 收尾操作

- 执行 `rmmod ipa`，避免 modem 持续崩溃循环
- **未修改** 设备上内核/DT/固件文件（只读诊断 + modprobe 实验）

---

## 4. 架构与数据流（为何没有网卡）

### 4.1 完整链路

```
┌─────────────────────────────────────────────────────────────┐
│  控制面（已完成 ✅）                                          │
│  modem.mdt → PAS → GLINK → IPCRTR → qrtr_smd → qrtr://0     │
│  → qmicli (DMS/NAS/UIM/WDS 命令)                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  数据面（未完成 ❌）                                          │
│  ipa.ko → IPA↔Modem QMI 握手 → rmnet_ipa0 网卡              │
│  → WDS 拨号 → dhclient → 蜂窝上网                            │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 网卡如何产生

Mainline 上蜂窝网卡名 **`rmnet_ipa0`**，由 `drivers/net/ipa/ipa_modem.c` 在以下条件满足后创建：

1. `ipa` 驱动 probe 成功（`1e40000.ipa`）
2. IPA 与 modem 完成 QMI 握手（`INIT_DRIVER` / `DRIVER_INIT_COMPLETE`）
3. `ipa_modem_start()` → `register_netdev("rmnet_ipa0")`

**仅 `modprobe ipa` 不够**；握手失败则没有 `rmnet_ipa0`。

### 4.3 为何 `ip link` 只有 lo / usb0 / wlan0

| 接口 | 来源 |
|------|------|
| `lo` | 回环 |
| `usb0` | USB 网络 |
| `wlan0` | WiFi（ath10k） |
| `rmnet_ipa0` | **缺失** — IPA 数据面未就绪 |

QMI 通了 **不会** 自动创建网络接口；必须有 IPA + rmnet。

---

## 5. 无网卡根因分析

### 5.1 直接原因

加载 `ipa` 内核模块后，modem 固件内 IPA 硬件处理器（HWP）初始化超时崩溃，AP 侧无法完成 IPA QMI 握手，**`rmnet_ipa0` 无法注册**。

### 5.2 对比实验

| 条件 | modem | rmnet_ipa0 |
|------|-------|------------|
| 不加载 `ipa` | ✅ 稳定，QMI 正常 | ❌ 不存在 |
| 加载 `ipa`（任意顺序） | ❌ ~3s 后 HWP 崩溃 | ❌ 不存在 |

### 5.3 可能原因（待进一步验证）

1. **启动顺序**：IPA 应在 modem 之前加载；晚加载可能导致握手超时（曾见 `-110`）
2. **IPA 固件**：设备上路径为 `/lib/firmware/qcom/ipa_fws.*`（DT：`firmware-name = "qcom/ipa_fws.mdt"`），不是 `sm8150/Xiaomi/raphael/` 子目录
3. **设备树**：`ipa_fw_mem` / `ipa_gsi_mem` 保留内存是否与下游一致
4. **mainline IPA 驱动** 与 Xiaomi MPSS 固件组合尚未在 Raphael 上完全验证

### 5.4 排除项

- ❌ 不是因为没插 SIM（无卡只影响拨号，不影响网卡设备节点出现）
- ❌ 不是因为 `ipa.ko` 未安装（已存在且能 probe）
- ❌ 不是因为 QRTR 未通（`qrtr://0` QMI 已验证）
- ❌ 不是因为 GLINK 未通（IPCRTR/DATA* 通道已存在）

---

## 6. QMI 使用备忘（已验证）

### 6.1 模块加载顺序（日常使用）

```bash
sudo modprobe qrtr_smd
sudo modprobe qcom_pd_mapper
# 暂不: sudo modprobe ipa
```

### 6.2 qmicli 命令（需自编译 libqmi，QRTR 支持）

```bash
# Modem 节点 = qrtr://0（不是 qrtr://1）
qmicli -d qrtr://0 --dms-get-capabilities
qmicli -d qrtr://0 --dms-get-ids
qmicli -d qrtr://0 --uim-get-card-status      # 需插卡
qmicli -d qrtr://0 --nas-get-serving-system   # 需插卡+注册
```

### 6.3 无卡时的正常输出

```
Card state: 'error: no-atr-received (3)'   # 两卡槽均无卡
Registration state: 'not-registered-searching'
```

### 6.4 错误用法（勿用）

```bash
qmicli -d qrtr:0 ...          # 错误：缺 //
qmicli -d qrtr://0 -u ...     # 错误：无 -u 选项
# 系统 apt 版 qmicli            # 无 QRTR，报 URI is not a local file path
```

---

## 7. 后续处理计划

### 阶段 A：稳定控制面（当前可做）

- [x] modem 固件部署
- [x] qrtr_smd + pd_mapper 开机加载
- [x] 自编译 libqmi（`-Dqrtr=true`）
- [x] 验证 `qrtr://0` QMI
- [ ] 插卡复测 UIM / NAS
- [ ] **保持 `ipa` 不自动加载**，避免 modem 崩溃

### 阶段 B：修复 IPA 数据面（阻塞上网）

**优先级 1 — 启动顺序**

1. 在 initramfs 或 early init 中 **先于 modem** 加载 `ipa`
2. 测试是否仍出现 HWP 崩溃

```bash
# 实验脚本（重启后按顺序执行，观察 dmesg）
sudo modprobe qrtr_smd
sudo modprobe ipa
sleep 2
# 若 modem 尚未自启：
echo start | sudo tee /sys/class/remoteproc/remoteproc0/state
sleep 10
dmesg | grep -iE 'ipa|rmnet|fatal|hwp'
ip link show | grep rmnet
```

**优先级 2 — IPA 固件**

- 从 Android 线刷包提取 Raphael 专用 `ipa_fws.*`，覆盖到 `/lib/firmware/qcom/`（DT 已是 `qcom/ipa_fws.mdt`）

**优先级 3 — 设备树核对**

对照 downstream 检查：

- `ipa_fw_mem @ 0x98f00000`（64KB）
- `ipa_gsi_mem @ 0x98f10000`（20KB）
- `&ipa { qcom,gsi-loader = "self"; memory-region = <&ipa_fw_mem>; }`

**优先级 4 — 跟踪上游**

- postmarketOS SM8150：`https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux`
- 关注 `drivers/net/ipa/` 与 SM8150 相关 patch

### 阶段 C：有 rmnet_ipa0 之后

```bash
# 1. 插 SIM
qmicli -d qrtr://0 --uim-get-card-status

# 2. WDS 拨号（APN 按运营商）
qmicli -d qrtr://0 --wds-start-network=apn=cmnet --client-no-release-cid

# 3. 拉起网卡
sudo ip link set rmnet_ipa0 up
sudo dhclient rmnet_ipa0

# 4. 可选：ModemManager（需 QRTR 插件）
sudo systemctl start ModemManager
mmcli -L
```

---

## 8. 文件与命令速查

| 项目 | 路径/命令 |
|------|-----------|
| Modem 固件 MDT | `/lib/firmware/qcom/sm8150/Xiaomi/raphael/modem.mdt` |
| IPA 模块 | `/lib/modules/$(uname -r)/kernel/drivers/net/ipa/ipa.ko` |
| IPA 平台设备 | `/sys/bus/platform/devices/1e40000.ipa/` |
| Modem remoteproc | `/sys/class/remoteproc/remoteproc0/` |
| RPMSG 设备列表 | `/sys/bus/rpmsg/devices/` |
| QRTR 驱动绑定 | `/sys/bus/rpmsg/drivers/qcom_smd_qrtr/` |
| 内核文档（MDT 流程） | `docs/RAPHAEL-MODEM-LINUX-7.0.md` |

---

## 9. 时间线摘要

| 阶段 | 现象 | 结论 |
|------|------|------|
| 初诊 | GLINK 通道“未创建” | 检查时机过早或方法不对 |
| RPMSG 列表 | 27 设备，含 IPCRTR | GLINK 实际已通 |
| QRTR 无节点 | `qrtr_smd` 未加载 | `modprobe qrtr_smd` 解决 |
| qmicli 失败 | 系统 libqmi 无 QRTR | 自编译 `-Dqrtr=true` |
| QMI 成功 | `qrtr://0` IMEI 正常 | 控制面完成 |
| 无网卡 | 无 `rmnet_ipa0` | 需 IPA 模块 |
| IPA 实验 | modem HWP 崩溃 | **数据面阻塞点** |
| 收尾 | `rmmod ipa` | modem 恢复稳定 |

---

## 10. 结论

**Raphael 在 Linux 7.0 mainline 上已实现：**

- Modem 固件加载与启动
- GLINK 全通道通信
- QRTR / QMI 控制面（`qrtr://0`）

**尚未实现：**

- IPA 数据面与 `rmnet_ipa0` 蜂窝网卡
- 蜂窝上网

**当前建议：**

1. 日常使用加载 `qrtr_smd`、`qcom_pd_mapper`，**不要加载 `ipa`**
2. 使用自编译 `qmicli` 与 `qrtr://0` 做 QMI 测试
3. 按第 7 节阶段 B 排查 IPA，优先尝试 **IPA 先于 modem 启动** 与 **设备专用 IPA 固件**

---

*本文档由调试会话整理，配合 `RAPHAEL-MODEM-LINUX-7.0.md` 阅读。*

# Raphael 无法开机 — 紧急恢复

## 原因

`raphael-ipa-load.service` 在开机时自动 `modprobe ipa`。若 `/lib/modules/.../ipa.ko` 为调试版或加载时机不对，modem 会反复崩溃：

```
ipa_hwp_init_rsp_timer_cb: didnt rx any ind frm HWP
remoteproc remoteproc0: crash detected in modem
```

整机可能卡死、反复重启或无法进入 SSH。

## 恢复步骤（任选一种能进 shell 的方式）

### 方式 A：rEFInd 启动菜单

1. 开机进入 rEFInd，选择 Linux 内核启动。
2. 若仍卡死，尝试带 `init=/bin/bash` 的内核条目（若有），或从 recovery 分区启动。

### 方式 B：能短暂 SSH 时（抢时间执行）

```bash
sudo systemctl disable raphael-ipa-load.service
sudo systemctl mask raphael-ipa-load.service
sudo rmmod ipa 2>/dev/null || true
sudo mv /lib/modules/$(uname -r)/kernel/drivers/net/ipa/ipa.ko \
        /lib/modules/$(uname -r)/kernel/drivers/net/ipa/ipa.ko.disabled
sudo reboot
```

### 方式 C：挂载 root 分区（另一台电脑 / live 环境）

在 rootfs 上执行：

```bash
# 禁止开机加载 IPA
rm -f /mnt/etc/systemd/system/multi-user.target.wants/raphael-ipa-load.service
# 或编辑 service 加上 ConditionPathExists（见固件包新版）

# 移走有问题的模块
mv /mnt/lib/modules/*/kernel/drivers/net/ipa/ipa.ko \
   /mnt/lib/modules/*/kernel/drivers/net/ipa/ipa.ko.disabled 2>/dev/null || true
```

## 恢复后验证

```bash
# modem 应稳定 running，且无 ipa 模块
cat /sys/class/remoteproc/remoteproc0/state   # running
lsmod | grep ipa                              # 无输出
qmicli -d qrtr://0 --dms-get-ids               # 可读 IMEI
```

## 再次启用 IPA（仅手动调试时）

```bash
sudo mkdir -p /etc/raphael
sudo touch /etc/raphael/enable-ipa
sudo systemctl enable raphael-ipa-load.service
# 确认 ipa.ko 正确后再 systemctl start raphael-ipa-load.service
```

**禁止**在运行中的系统上 `rmmod ipa` / 热替换 `ipa.ko`（会触发 modem crash 循环）。

---
title: BBB bringup 与刷写基线
date: 2026-11-22 20:00:00
tags:
  - BBB(BeagleBone Black)
  - SOC
  - bring up
  - kernel
  - uboot
---
# BBB bringup 与刷写基线

# 要做什么与为什么要做
**要做什么**
笔者准备救赎一块吃灰的BBB板子，希望基于这块板子做一个从0到1的bringup。要求不假设任何非官方的信息输入，以最少的第三方依赖点亮它，然后制做成一个完全受控的实验平台。
**为什么要做**
作为一个嵌入式工程师，笔者偶尔会对自己产生灵魂拷问：如果给你一个完全陌生的板子，你现在是否有能力完成开荒。对比MCU，开荒SOC的经验是笔者所缺乏的。
为此，选中了BBB作为这个假设需要开荒的target了。BBB与笔者的渊源很深，我很早就有这块板子，并且BBB在各大工具的支持都非常好，说是开荒，其实是在各个主线良好支持的情况下假装开荒了。但是真缺主线支持的开荒，好像也不是个人开发者业务时间能吃得消的。
闲言少叙，开工~

## 关于BBB
BeagleBone Black也叫BBB，是社区里广泛使用的开源卡片电脑，生态位类似树莓派，又有一些差异。BBB的详细介绍可以参见[What is BeagleBone® Black?](https://www.beagleboard.org/boards/beaglebone-black)。包括原理图、手册等也可以从官方网站上获得，全部开源。
关系BBB的详细信息从[BBB官方主页](https://docs.beagle.cc/boards/beaglebone/black/index.html)可以获得，这里简单提几个和我们的用途直接相关的内容：

- CPU：**TI AM3358**，1GHz ARM® Cortex-A8
- DRAM：512MB DDR3L 800MHZ
- Memory：4GB eMMC
- SD卡槽
- 串口、USB网桥（供电、USB网卡）

# 前置条件
动手之前，我们需要先确认具备如下内容。
## 开发环境
**所需硬件**
- BBB * 1
- 32G SD卡 * 1
- SD卡读卡器 * 1
- USB转串口线 * 1
- miniUSB 线 * 1
- Linux Host机 * 1 （笔者使用的是一个零刻eq59的NUC，运行Debian 12系统）

**硬件拓扑**
```
                         +-----------------------------+
                         | Linux Host                  |
                         | NUC EQ59 / Debian 12        |
                         +--+----------+------------+--+
                            |          |            |
                  USB-A     |  USB-A   |  USB-A     |
                            |          |            |
               +------------v--+  +----v-----+  +---v-----------+
               | USB-to-serial |  | miniUSB  |  | USB SD reader |
               | adapter       |  | cable    |  | (offline)     |
               +-------+-------+  +----+-----+  +-------+-------+
                       |               |                |
                 UART  |               | USB            +--> [32G SD]
             GND/TX/RX |               | power +             (offline
                       |               | RNDIS/fastboot       only)
                       |               |
               +-------v---------------v----------------------+
               |              BeagleBone Black                |
               |  J1 UART          miniUSB          microSD   |
               |                                   [32G SD]   |
               +----------------------------------------------+
```
**软件环境**
因为涉及的步骤和软件还挺多的，这里不就不一一列举了，实际执行的时候缺什么补什么吧。

## BBB的启动选项
BBB板上的BOOT按键是S2，最终体现为AM335x SYSBOOT配置位的采样结果。S2 并不是普通GPIO：它拉低其中一个SYSBOOT 配置位，BootROM在上电时采样这组配置位，决定启动顺序。

| 场景 | 启动顺序 |
|---|---|
| 不按 S2，插 SD | eMMC → SD → UART0 → USB0 |
| 不按 S2，不插 SD | eMMC → UART0 → USB0 |
| 按 S2，插 SD | SD 直接启动 |
| 按 S2，不插 SD | USB0 → UART0 |

需要注意的是：

- 这里的按下和不按S2指的都是重新上电时的采样结果，reset按钮按下是热重启，不会影响boot mode。
- 表格里的顺序是“前一项不可启动时继续下一项”，不是每项都会并行尝试。
- 插SD并且按S2，是在前期没有可信任框架时可以快速直接修改启动介质内容的手段。
- 关于启动模式的信源可以参考[文档](https://docs.beagleboard.org/beaglebone-black.pdf)
- 同时，这里的SD卡准确说应该是可启动的SD卡，也就是包含MLO等的可启动镜像

# U-Boot
一般而言，SOC运行Linux在启动时都需要经过类似的流程：BootROM -> first-stage bootloader -> U-Boot -> Linux kernel。

- BootROM，有时也叫BROM，是芯片内部固化的一段ROM代码，这段代码完成最基本的系统Boot，并按启动介质和镜像格式加载下一阶段。
- first-stage bootloader是一个角色，不是所有厂商统一的阶段名。Uboot里叫SPL；TI AM335x/BBB把SPL镜像命名为MLO，Xilinx Zynq叫FSBL，Intel/Altera叫Preloader。NXP i.MX6则常用IVT+DCD的形式，由 BootROM应用DCD配置DDR，不一定有独立的SPL。这一级通常负责时钟、引脚、PMIC和DDR初始化，然后把U-Boot proper加载到DDR。片内SRAM通常放不下完整的U-Boot proper，所以需要先在SRAM中运行这一级小型loader。
- U-Boot，DDR初始化完成之后进入U-Boot，系统基本上就进入守序宇宙了，U-Boot负责加载 kernel、DTB、initrd，并决定Linux 的启动选项
- Linux kernel 启动。

## 目标
在这一章节，目标使用主线U-Boot，将启动链进行到U-Boot环节。

## 操作与现象
使用主线的U-Boot包，笔者选择了u-boot-2027.01-rc2，可以从[这里](https://github.com/u-boot/u-boot/archive/refs/tags/v2027.01-rc2.tar.gz) 获得，下载后正常解压即可。
- 下载代码（本文中所有开源主线代码统一放在$HOME/opensource目录下）
``` bash
cd $HOME/opensource
wget https://github.com/u-boot/u-boot/archive/refs/tags/v2027.01-rc2.tar.gz
tar zxvf v2027.01-rc2.tar.gz
```
- 编译U-Boot（本文中所有编译产物统一放在$HOME/build目录下）
``` bash
rm -rf $HOME/build/bringup-uboot
mkdir -p $HOME/build/bringup-uboot
make -C $HOME/opensource/u-boot-2027.01-rc2 \
  O=$HOME/build/bringup-uboot \
  ARCH=arm \
  CROSS_COMPILE=arm-linux-gnueabihf- \
  am335x_evm_defconfig
make -C $HOME/opensource/u-boot-2027.01-rc2 \
  O=$HOME/build/bringup-uboot \
  ARCH=arm \
  CROSS_COMPILE=arm-linux-gnueabihf- \
  -j4
```
- 确认产物，包含u-boot.img 和 MLO
```
ls -lh $HOME/build/bringup-uboot/MLO
ls -lh $HOME/build/bringup-uboot/u-boot.img
```
- 将产物写进SD卡
首先，将SD卡与读卡器插入NUC，通过```lsblk```确认SD卡对应的盘符是/dev/sdb 。（**一定不要搞错盘符，不然有可能把host的存储搞坏**）
``` bash
# 1. 卸载这张卡上所有已挂载分区
sudo umount /mnt/sd 2>/dev/null || true
sudo umount /dev/sdb* 2>/dev/null || true

# 2. 擦除整张卡上的旧分区表和文件系统签名
#    如果这里仍然报 Device or resource busy：
#    sudo fuser -vm /dev/sdb
#    找出占用进程并关闭后再重试
sudo wipefs -a /dev/sdb

# 3. 重新创建分区表：p1 = 64M FAT32
sudo sfdisk --wipe always /dev/sdb <<'EOF'
label: dos
unit: sectors
start=2048, size=131072, type=c, bootable
EOF

# 4. 让内核重新读取分区表
sudo partprobe /dev/sdb || true
sudo udevadm settle

# 5. 防止新分区被桌面自动挂载
sudo umount /dev/sdb1 2>/dev/null || true

# 6. 格式化 p1
sudo mkfs.vfat -F 32 -n BOOT /dev/sdb1

# 7. 挂载 p1
sudo mkdir -p /mnt/sd
sudo mount /dev/sdb1 /mnt/sd

# 8. 写入 U-Boot 最终产物
sudo cp $HOME/build/bringup-uboot/MLO /mnt/sd/MLO
sudo cp $HOME/build/bringup-uboot/u-boot.img /mnt/sd/u-boot.img

# 9. 落盘并卸载
sync
sudo umount /mnt/sd

# 10. 查看结果
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT /dev/sdb
```
- 使用SD卡启动
将制作好的SD卡插入BBB，按住S2后上电启动，观察串口现象。
```
U-Boot 2027.01-rc2 (Nov 22 2026 - 04:33:29 -0500)

CPU  : AM335X-GP rev 2.1
Model: TI AM335x BeagleBone Black
DRAM:  512 MiB
Core:  218 devices, 21 uclasses, devicetree: separate
WDT:   Started wdt@0 with servicing every 1000ms (60s timeout)
NAND:  0 MiB
MMC:   OMAP SD/MMC: 0, OMAP SD/MMC: 1
Unable to read "uboot.env" from mmc0:1...
<ethaddr> not set. Validating first E-fuse MAC
Net:   eth2: switch@0using musb-hdrc, OUT ep1out IN ep1in STATUS ep2in
MAC de:ad:be:ef:00:01
HOST MAC de:ad:be:ef:00:00
RNDIS ready
, eth3: usb_ether

Hit any key to stop autoboot: 2
```
符合预期，使用任意键可以停住U-Boot。
## U-Boot内部逻辑
这里不展开了，挖个坑以后慢慢填吧。

# 最小化内核
有了uboot环境之后，下一步就可以搓个内核然后引导了。为了最小化我们的初版内核，我们将会从allnoconfig开始，增加上串口的支持，这就是我们的最小内核了(ARCH_OMAP2PLUS 本身还会 select PM/PINCTRL/GPIOLIB 等，所以这是可启动的最小集合，不是字面最小)。
## 获取代码
``` bash
cd $HOME/opensource
wget https://github.com/torvalds/linux/archive/refs/tags/v7.4-rc4.tar.gz
tar zxvf ./v7.4-rc4.tar.gz
```
## 编译内核
``` bash
# 生成最小配置
make -C $HOME/opensource/linux-7.4-rc4 O=$HOME/build/bringup-kernel ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- allnoconfig
# 追加最小选项
tee -a "$HOME/build/bringup-kernel/.config" >/dev/null <<'EOF'
# --- ARMv7 platform + SoC ---
CONFIG_MMU=y
CONFIG_ARCH_MULTI_V7=y
CONFIG_SOC_AM33XX=y
CONFIG_USE_OF=y
# stop AM33xx from pulling the whole "Typical OMAP" bundle
# CONFIG_ARCH_OMAP2PLUS_TYPICAL is not set

# --- serial console ---
CONFIG_TTY=y
CONFIG_PRINTK=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_OMAP=y

# --- early debug: only active if bootargs has earlycon/earlyprintk ---
CONFIG_DEBUG_KERNEL=y
CONFIG_DEBUG_LL=y
CONFIG_DEBUG_AM33XXUART1=y
CONFIG_EARLY_PRINTK=y

# --- groundwork for stage C (userspace / initramfs) ---
CONFIG_BINFMT_ELF=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y
EOF
# 新配置作用后重建.config
make -C $HOME/opensource/linux-7.4-rc4 O=$HOME/build/bringup-kernel ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig
# 编译内核
make -C $HOME/opensource/linux-7.4-rc4 O=$HOME/build/bringup-kernel ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j4 zImage
# 编译设备树
make -C $HOME/opensource/linux-7.4-rc4 O=$HOME/build/bringup-kernel ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j4 ti/omap/am335x-boneblack.dtb
# 验收产物
ls -alF $HOME/build/bringup-kernel/arch/arm/boot/zImage
ls -alF $HOME/build/bringup-kernel/arch/arm/boot/dts/ti/omap/am335x-boneblack.dtb 
```
## 烧写镜像
将SD 卡插回host，在保持uboot环境不变的情况下，将kernel的zImage 与 设备树文件写入p1分区
``` bash
sudo mkdir -p /mnt/sd 
sudo umount /dev/sdb* 2>/dev/null || true
sudo mount /dev/sdb1 /mnt/sd

sudo cp $HOME/build/bringup-kernel/arch/arm/boot/zImage /mnt/sd
sudo cp $HOME/build/bringup-kernel/arch/arm/boot/dts/ti/omap/am335x-boneblack.dtb /mnt/sd

sync

sudo ls -alF /mnt/sd
sudo umount /mnt/sd 
```
## 通过uboot引导镜像
将SD卡插回BBB，在按下S2的情况下重新上电，看到uboot进入。使用any key打断，之后执行如下命令
```bash
load mmc 0:1 ${kernel_addr_r} /zImage
load mmc 0:1 ${fdt_addr_r} /am335x-boneblack.dtb
setenv bootargs console=ttyS0,115200n8
bootz ${kernel_addr_r} - ${fdt_addr_r}
```
可以看到现象
```
U-Boot 2027.01-rc2 (Nov 22 2026 - 04:33:29 -0500)

CPU  : AM335X-GP rev 2.1
Model: TI AM335x BeagleBone Black
DRAM:  512 MiB
Core:  218 devices, 21 uclasses, devicetree: separate
WDT:   Started wdt@0 with servicing every 1000ms (60s timeout)
NAND:  0 MiB
MMC:   OMAP SD/MMC: 0, OMAP SD/MMC: 1
Unable to read "uboot.env" from mmc0:1...
<ethaddr> not set. Validating first E-fuse MAC
Net:   eth2: switch@0using musb-hdrc, OUT ep1out IN ep1in STATUS ep2in
MAC de:ad:be:ef:00:01
HOST MAC de:ad:be:ef:00:00
RNDIS ready
, eth3: usb_ether

Hit any key to stop autoboot: 0
=> load mmc 0:1 ${kernel_addr_r} /zImage
1749392 bytes read in 115 ms (14.5 MiB/s)
=> load mmc 0:1 ${fdt_addr_r} /am335x-boneblack.dtb
98486 bytes read in 8 ms (11.7 MiB/s)
=> setenv bootargs console=ttyS0,115200n8
=> bootz ${kernel_addr_r} - ${fdt_addr_r}
Kernel image @ 0x82000000 [ 0x000000 - 0x1ab190 ]
## Flattened Device Tree blob at 88000000
   Booting using the fdt blob at 0x88000000
Working FDT set to 88000000
   Loading Device Tree to 8ffe4000, end 8ffff0b5 ... OK
Working FDT set to 8ffe4000

Starting kernel ...

Booting Linux on physical CPU 0x0
Linux version 7.4.0-rc4 (tengfei@debian) (arm-linux-gnueabihf-gcc (Debian 12.2.0-14) 12.2.0, GNU ld (GNU Binutils for Debian) 2.40) #19 Wed Nov 25 09:31:24 EST 2026
CPU: ARMv7 Processor [413fc082] revision 2 (ARMv7), cr=50c5387d
CPU: PIPT / VIPT nonaliasing data cache, VIPT aliasing instruction cache
OF: fdt: Machine model: TI AM335x BeagleBone Black
Memory policy: Data cache writeback
OF: reserved mem: Reserved memory: No reserved-memory node in the DT
CPU: All CPU(s) started in SVC mode.
AM335X ES2.1 (sgx neon)
Zone ranges:
  Normal   [mem 0x0000000080000000-0x000000009fefffff]
Movable zone start for each node
Early memory node ranges
  node   0: [mem 0x0000000080000000-0x000000009fefffff]
Initmem setup node 0 [mem 0x0000000080000000-0x000000009fefffff]
On node 0, zone Normal: 256 pages in unavailable ranges
Kernel command line: console=ttyS0,115200n8
printk: log buffer data + meta data: 131072 + 409600 = 540672 bytes
Dentry cache hash table entries: 65536 (order: 6, 262144 bytes, linear)
Inode-cache hash table entries: 32768 (order: 5, 131072 bytes, linear)
Built 1 zonelists, mobility grouping on.  Total pages: 130816
mem auto-init: stack:all(zero), heap alloc:off, heap free:off
SLUB: HWalign=16, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
NR_IRQS: 16, nr_irqs: 16, preallocated irqs: 16
IRQ: Found an INTC at 0x(ptrval) (revision 5.0) with 128 interrupts
clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 19112604462750000 ns
TI gptimer clocksource: always-on /ocp/interconnect@44c00000/segment@200000/target-module@31000
sched_clock: 32 bits at 24MHz, resolution 41ns, wraps every 89478484971ns
clocksource: dmtimer: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 79635851949 ns
TI gptimer clockevent: 24000000 Hz at /ocp/interconnect@48000000/segment@0/target-module@40000
Console: colour dummy device 80x30
Calibrating delay loop... 996.14 BogoMIPS (lpj=4980736)
CPU: Testing write buffer coherency: ok
CPU0: Spectre v2: using BPIALL workaround
pid_max: default: 32768 minimum: 301
Mount-cache hash table entries: 1024 (order: 0, 4096 bytes, linear)
Mountpoint-cache hash table entries: 1024 (order: 0, 4096 bytes, linear)
VFS: Finished mounting rootfs on nullfs
Setting up static identity map for 0x80100000 - 0x80100054
Memory: 512688K/523264K available (2048K kernel code, 478K rwdata, 528K rodata, 1024K init, 181K bss, 9624K reserved, 0K cma-reserved)
devtmpfs: initialized
posixtimers hash table entries: 512 (order: 0, 2048 bytes, linear)
futex hash table entries: 256 (3072 bytes on 1 NUMA nodes, total 3 KiB, linear).
DMA: preallocated 256 KiB pool for atomic coherent allocations
/ocp/interconnect@48000000/segment@300000/target-module@e000/lcdc@0: Fixed dependency cycle(s) with /ocp/interconnect@44c00000/segment@200000/target-module@b000/i2c@0/tda19988@70
/ocp/interconnect@44c00000/segment@200000/target-module@b000/i2c@0/tda19988@70: Fixed dependency cycle(s) with /ocp/interconnect@48000000/segment@300000/target-module@e000/lcdc@0
clocksource: Switched to clocksource dmtimer
workingset: timestamp_bits=30 (anon: 25) max_order=17 bucket_order=0 (anon: 0)
target-module@4b000000:target-module@140000:pmu@0:fck: device ID is greater than 24
Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
omap_voltage_late_init: Voltage driver support not added
printk: console [ttyS0] disabled
44e09000.serial: ttyS0 MMIO:0x44e09000 (irq = 18, base_baud = 3000000) is a 8250
printk: console [ttyS0] enabled
/ocp/interconnect@44c00000/segment@200000/target-module@10000/scm@0/pinmux@800: Fixed dependency cycle(s) with /ocp/interconnect@44c00000/segment@200000/target-module@10000/scm@0/pinmux@800/clkout2s
48000000.interconnect:segment@200000:target-module@0:mpu@0:fck: device ID is greater than 24
ti-sysc 44e31000.target-module: Failed to create device link (0x180) with supplier ocp for /ocp/interconnect@44c00000/segment@200000/target-module@31000/timer@0
ti-sysc 48040000.target-module: Failed to create device link (0x180) with supplier ocp for /ocp/interconnect@48000000/segment@0/target-module@40000/timer@0
omap_prm 44e00d00.prm: sync_state() pending due to 44d00000.cpu
clk: Disabling unused clocks
PM: genpd: Disabling unused power domains
List of all partitions:
No filesystem could mount root, tried:

Kernel panic - not syncing: VFS: Unable to mount root fs on "" or unknown-block(0,0)
CPU: 0 UID: 0 PID: 1 Comm: swapper/0 Not tainted 7.4.0-rc4 #19 VOLUNTARY
Hardware name: Generic AM33XX (Flattened Device Tree)
Call trace:
 unwind_backtrace from show_stack+0xa/0xc
 show_stack from vpanic+0x96/0x1e8
 vpanic from warn_slowpath_fmt+0x0/0x6c
 warn_slowpath_fmt from 0x636f6c62
---[ end Kernel panic - not syncing: VFS: Unable to mount root fs on "" or unknown-block(0,0) ]---
```
可以看到，kernel启动已经被引导起来了，但是很快panic了，因为没有rootfs给它用。

# initramfs 与rootfs
## initramfs
在内核缺少rootfs的情况下，先搞initramfs比较容易。考虑使用busybox静态链接。
### 获取busybox源码
``` bash
wget https://www.busybox.net/downloads/busybox-1.38.0.tar.bz2
tar xjvf busybox-1.38.0.tar.bz2
```
### 静态编译busybox
``` bash
rm -rf $HOME/build/bringup-busybox
mkdir -p $HOME/build/bringup-busybox
make -C $HOME/opensource/busybox-1.38.0 O=$HOME/build/bringup-busybox ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- defconfig
sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' $HOME/build/bringup-busybox/.config
make -C $HOME/opensource/busybox-1.38.0 O=$HOME/build/bringup-busybox ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- oldconfig </dev/null
make -C $HOME/opensource/busybox-1.38.0 O=$HOME/build/bringup-busybox ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j4

file $HOME/build/bringup-busybox/busybox
strings $HOME/build/bringup-busybox/busybox | grep -m1 'BusyBox v'
grep -E '^CONFIG_(SH_IS_ASH|MOUNT|MDEV|CAT|LS|PS|GREP|CP|MKDIR|SYNC|UNAME|LN|RM|MV|SLEEP|UMOUNT|DMESG|ECHO)=' $HOME/build/bringup-busybox/.config
```
### 制作initramfs
``` bash
rm -rf "$HOME/build/bringup-initramfs"
mkdir -p "$HOME/build/bringup-initramfs/bin" \
         "$HOME/build/bringup-initramfs/dev" \
         "$HOME/build/bringup-initramfs/proc" \
         "$HOME/build/bringup-initramfs/sys" \
         "$HOME/build/bringup-initramfs/tmp"

cp "$HOME/build/bringup-busybox/busybox" "$HOME/build/bringup-initramfs/bin/busybox"
chmod 755 "$HOME/build/bringup-initramfs/bin/busybox"
for a in sh mount umount cat echo ls ps mdev dmesg sleep grep cp mkdir sync uname ln rm mv setsid cttyhack; do
  ln -sf busybox "$HOME/build/bringup-initramfs/bin/$a"
done

cat > "$HOME/build/bringup-initramfs/init" <<'EOF'
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
exec </dev/ttyS0 >/dev/ttyS0 2>&1

echo
echo "===== BRINGUP SERIAL SHELL ====="
cat /proc/version
echo "cmdline: $(cat /proc/cmdline)"
echo "serial : $(cat /proc/device-tree/serial-number)"
echo "================================"
echo
# PID 1 先变成 session leader，cttyhack 才能把 ttyS0 设成控制终端
exec setsid cttyhack /bin/sh
EOF
chmod 755 "$HOME/build/bringup-initramfs/init"
```
### 重新生成kernel
``` bash
tee -a "$HOME/build/bringup-kernel/.config" >/dev/null <<'EOF'
# BusyBox 是 gnueabihf 硬浮点，用户态会执行 VFP/NEON 指令
CONFIG_VFP=y
CONFIG_NEON=y
# /init 是 shell 脚本
CONFIG_BINFMT_SCRIPT=y
EOF

$HOME/opensource/linux-7.4-rc4/scripts/config \
  --file "$HOME/build/bringup-kernel/.config" \
  --set-str INITRAMFS_SOURCE "$HOME/build/bringup-initramfs"

make -C $HOME/opensource/linux-7.4-rc4 O=$HOME/build/bringup-kernel ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig
make -C $HOME/opensource/linux-7.4-rc4 O=$HOME/build/bringup-kernel ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j4 zImage

grep '^CONFIG_INITRAMFS_SOURCE=' $HOME/build/bringup-kernel/.config
ls -lh $HOME/build/bringup-kernel/usr/initramfs_data.cpio
```
### 烧录验证
重新生成的kernel中已经带了initramfs，而DTB仅与DTS相关不需更新，直接替换掉SD卡中的kernel即可。
``` bash
sudo mkdir -p /mnt/sd
sudo umount /dev/sdb* 2>/dev/null || true
sudo mount /dev/sdb1 /mnt/sd

sudo cp $HOME/build/bringup-kernel/arch/arm/boot/zImage /mnt/sd/zImage
sync

sha256sum $HOME/build/bringup-kernel/arch/arm/boot/zImage
sudo sha256sum /mnt/sd/zImage

sudo umount /mnt/sd
```
与前面类似，进uboot后any key打断
``` bash
load mmc 0:1 ${kernel_addr_r} /zImage
load mmc 0:1 ${fdt_addr_r} /am335x-boneblack.dtb
setenv bootargs console=ttyS0,115200n8
bootz ${kernel_addr_r} - ${fdt_addr_r}
```
可以看到现象，kernel正常启动，并且进入initramfs
```
U-Boot SPL 2027.01-rc2 (Nov 22 2026 - 04:33:29 -0500)
Trying to boot from MMC1


U-Boot 2027.01-rc2 (Nov 22 2026 - 04:33:29 -0500)

CPU  : AM335X-GP rev 2.1
Model: TI AM335x BeagleBone Black
DRAM:  512 MiB
Core:  218 devices, 21 uclasses, devicetree: separate
WDT:   Started wdt@0 with servicing every 1000ms (60s timeout)
NAND:  0 MiB
MMC:   OMAP SD/MMC: 0, OMAP SD/MMC: 1
Unable to read "uboot.env" from mmc0:1...
<ethaddr> not set. Validating first E-fuse MAC
Net:   eth2: switch@0using musb-hdrc, OUT ep1out IN ep1in STATUS ep2in
MAC de:ad:be:ef:00:01
HOST MAC de:ad:be:ef:00:00
RNDIS ready
, eth3: usb_ether

Hit any key to stop autoboot: 0
=>
=>
=>
=>
=> load mmc 0:1 ${kernel_addr_r} /zImage
2825904 bytes read in 186 ms (14.5 MiB/s)
=> load mmc 0:1 ${fdt_addr_r} /am335x-boneblack.dtb
98486 bytes read in 9 ms (10.4 MiB/s)
=> setenv bootargs console=ttyS0,115200n8
=> bootz ${kernel_addr_r} - ${fdt_addr_r}
Kernel image @ 0x82000000 [ 0x000000 - 0x2b1eb0 ]
## Flattened Device Tree blob at 88000000
   Booting using the fdt blob at 0x88000000
Working FDT set to 88000000
   Loading Device Tree to 8ffe4000, end 8ffff0b5 ... OK
Working FDT set to 8ffe4000

Starting kernel ...

Booting Linux on physical CPU 0x0
Linux version 7.4.0-rc4 (tengfei@debian) (arm-linux-gnueabihf-gcc (Debian 12.2.0-14) 12.2.0, GNU ld (GNU Binutils for Debian) 2.40) #21 Thu Nov 26 08:14:24 EST 2026
CPU: ARMv7 Processor [413fc082] revision 2 (ARMv7), cr=50c5387d
CPU: PIPT / VIPT nonaliasing data cache, VIPT aliasing instruction cache
OF: fdt: Machine model: TI AM335x BeagleBone Black
Memory policy: Data cache writeback
OF: reserved mem: Reserved memory: No reserved-memory node in the DT
CPU: All CPU(s) started in SVC mode.
AM335X ES2.1 (sgx neon)
Zone ranges:
  Normal   [mem 0x0000000080000000-0x000000009fefffff]
Movable zone start for each node
Early memory node ranges
  node   0: [mem 0x0000000080000000-0x000000009fefffff]
Initmem setup node 0 [mem 0x0000000080000000-0x000000009fefffff]
On node 0, zone Normal: 256 pages in unavailable ranges
Kernel command line: console=ttyS0,115200n8
printk: log buffer data + meta data: 131072 + 409600 = 540672 bytes
Dentry cache hash table entries: 65536 (order: 6, 262144 bytes, linear)
Inode-cache hash table entries: 32768 (order: 5, 131072 bytes, linear)
Built 1 zonelists, mobility grouping on.  Total pages: 130816
mem auto-init: stack:all(zero), heap alloc:off, heap free:off
SLUB: HWalign=16, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
NR_IRQS: 16, nr_irqs: 16, preallocated irqs: 16
IRQ: Found an INTC at 0x(ptrval) (revision 5.0) with 128 interrupts
clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 19112604462750000 ns
TI gptimer clocksource: always-on /ocp/interconnect@44c00000/segment@200000/target-module@31000
sched_clock: 32 bits at 24MHz, resolution 41ns, wraps every 89478484971ns
clocksource: dmtimer: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 79635851949 ns
TI gptimer clockevent: 24000000 Hz at /ocp/interconnect@48000000/segment@0/target-module@40000
Console: colour dummy device 80x30
Calibrating delay loop... 996.14 BogoMIPS (lpj=4980736)
CPU: Testing write buffer coherency: ok
CPU0: Spectre v2: using BPIALL workaround
pid_max: default: 32768 minimum: 301
Mount-cache hash table entries: 1024 (order: 0, 4096 bytes, linear)
Mountpoint-cache hash table entries: 1024 (order: 0, 4096 bytes, linear)
VFS: Finished mounting rootfs on nullfs
Setting up static identity map for 0x80100000 - 0x80100054
Memory: 511664K/523264K available (2048K kernel code, 479K rwdata, 532K rodata, 2048K init, 180K bss, 10648K reserved, 0K cma-reserved)
devtmpfs: initialized
VFP support v0.3: implementor 41 architecture 3 part 30 variant c rev 3
posixtimers hash table entries: 512 (order: 0, 2048 bytes, linear)
futex hash table entries: 256 (3072 bytes on 1 NUMA nodes, total 3 KiB, linear).
DMA: preallocated 256 KiB pool for atomic coherent allocations
/ocp/interconnect@48000000/segment@300000/target-module@e000/lcdc@0: Fixed dependency cycle(s) with /ocp/interconnect@44c00000/segment@200000/target-module@b000/i2c@0/tda19988@70
/ocp/interconnect@44c00000/segment@200000/target-module@b000/i2c@0/tda19988@70: Fixed dependency cycle(s) with /ocp/interconnect@48000000/segment@300000/target-module@e000/lcdc@0
clocksource: Switched to clocksource dmtimer
workingset: timestamp_bits=30 (anon: 25) max_order=17 bucket_order=0 (anon: 0)
target-module@4b000000:target-module@140000:pmu@0:fck: device ID is greater than 24
Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
omap_voltage_late_init: Voltage driver support not added
printk: console [ttyS0] disabled
44e09000.serial: ttyS0 MMIO:0x44e09000 (irq = 18, base_baud = 3000000) is a 8250
printk: console [ttyS0] enabled
/ocp/interconnect@44c00000/segment@200000/target-module@10000/scm@0/pinmux@800: Fixed dependency cycle(s) with /ocp/interconnect@44c00000/segment@200000/target-module@10000/scm@0/pinmux@800/clkout2s
48000000.interconnect:segment@200000:target-module@0:mpu@0:fck: device ID is greater than 24
ti-sysc 44e31000.target-module: Failed to create device link (0x180) with supplier ocp for /ocp/interconnect@44c00000/segment@200000/target-module@31000/timer@0
ti-sysc 48040000.target-module: Failed to create device link (0x180) with supplier ocp for /ocp/interconnect@48000000/segment@0/target-module@40000/timer@0
omap_prm 44e00d00.prm: sync_state() pending due to 44d00000.cpu
clk: Disabling unused clocks
PM: genpd: Disabling unused power domains
Warning: unable to open an initial console.
Freeing unused kernel image (initmem) memory: 2048K
Run /init as init process

===== BRINGUP SERIAL SHELL =====
Linux version 7.4.0-rc4 (tengfei@debian) (arm-linux-gnueabihf-gcc (Debian 12.2.0-14) 12.2.0, GNU ld (GNU Binutils for Debian) 2.40) #21 Thu Nov 26 08:14:24 EST 2026
cmdline: console=ttyS0,115200n8
serial : 3816BBBK05DD
================================

~ #
~ #
```
### boot.scr
虽然已经成功启动kernel了，但是每次load都依赖在uboot里打断，这样不够方便，还是写一个boot脚本让它自动从指定的initramfs启动比较好。
``` bash
cat > $HOME/build/boot.cmd <<'EOF'
echo "== bringup: loading zImage + DTB from SD =="
load mmc 0:1 ${kernel_addr_r} /zImage
load mmc 0:1 ${fdt_addr_r} /am335x-boneblack.dtb
setenv bootargs 'console=ttyS0,115200n8'
bootz ${kernel_addr_r} - ${fdt_addr_r}
EOF

$HOME/build/bringup-uboot/tools/mkimage -A arm -O linux -T script -C none \
  -n "bringup boot" -d $HOME/build/boot.cmd $HOME/build/boot.scr

sudo mount /dev/sdb1 /mnt/sd
sudo cp $HOME/build/boot.scr /mnt/sd/boot.scr
sync
sudo umount /mnt/sd
```
可以看到现象
```
U-Boot SPL 2027.01-rc2 (Nov 22 2026 - 04:33:29 -0500)
Trying to boot from MMC1


U-Boot 2027.01-rc2 (Nov 22 2026 - 04:33:29 -0500)

CPU  : AM335X-GP rev 2.1
Model: TI AM335x BeagleBone Black
DRAM:  512 MiB
Core:  218 devices, 21 uclasses, devicetree: separate
WDT:   Started wdt@0 with servicing every 1000ms (60s timeout)
NAND:  0 MiB
MMC:   OMAP SD/MMC: 0, OMAP SD/MMC: 1
Unable to read "uboot.env" from mmc0:1...
<ethaddr> not set. Validating first E-fuse MAC
Net:   eth2: switch@0using musb-hdrc, OUT ep1out IN ep1in STATUS ep2in
MAC de:ad:be:ef:00:01
HOST MAC de:ad:be:ef:00:00
RNDIS ready
, eth3: usb_ether

Hit any key to stop autoboot: 0
** Invalid partition 2 **
switch to partitions #0, OK
mmc0 is current device
Scanning mmc 0:1...
Found U-Boot script /boot.scr
290 bytes read in 1 ms (283.2 KiB/s)
## Executing script at 80000000
== bringup: loading zImage + DTB from SD ==
2826000 bytes read in 185 ms (14.6 MiB/s)
98486 bytes read in 9 ms (10.4 MiB/s)
Kernel image @ 0x82000000 [ 0x000000 - 0x2b1f10 ]
## Flattened Device Tree blob at 88000000
   Booting using the fdt blob at 0x88000000
Working FDT set to 88000000
   Loading Device Tree to 8ffe4000, end 8ffff0b5 ... OK
Working FDT set to 8ffe4000

Starting kernel ...

Booting Linux on physical CPU 0x0
Linux version 7.4.0-rc4 (tengfei@debian) (arm-linux-gnueabihf-gcc (Debian 12.2.0-14) 12.2.0, GNU ld (GNU Binutils for Debian) 2.40) #22 Thu Nov 26 08:44:18 EST 2026
CPU: ARMv7 Processor [413fc082] revision 2 (ARMv7), cr=50c5387d
CPU: PIPT / VIPT nonaliasing data cache, VIPT aliasing instruction cache
OF: fdt: Machine model: TI AM335x BeagleBone Black
Memory policy: Data cache writeback
OF: reserved mem: Reserved memory: No reserved-memory node in the DT
CPU: All CPU(s) started in SVC mode.
AM335X ES2.1 (sgx neon)
Zone ranges:
  Normal   [mem 0x0000000080000000-0x000000009fefffff]
Movable zone start for each node
Early memory node ranges
  node   0: [mem 0x0000000080000000-0x000000009fefffff]
Initmem setup node 0 [mem 0x0000000080000000-0x000000009fefffff]
On node 0, zone Normal: 256 pages in unavailable ranges
Kernel command line: console=ttyS0,115200n8
printk: log buffer data + meta data: 131072 + 409600 = 540672 bytes
Dentry cache hash table entries: 65536 (order: 6, 262144 bytes, linear)
Inode-cache hash table entries: 32768 (order: 5, 131072 bytes, linear)
Built 1 zonelists, mobility grouping on.  Total pages: 130816
mem auto-init: stack:all(zero), heap alloc:off, heap free:off
SLUB: HWalign=16, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
NR_IRQS: 16, nr_irqs: 16, preallocated irqs: 16
IRQ: Found an INTC at 0x(ptrval) (revision 5.0) with 128 interrupts
clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 19112604462750000 ns
TI gptimer clocksource: always-on /ocp/interconnect@44c00000/segment@200000/target-module@31000
sched_clock: 32 bits at 24MHz, resolution 41ns, wraps every 89478484971ns
clocksource: dmtimer: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 79635851949 ns
TI gptimer clockevent: 24000000 Hz at /ocp/interconnect@48000000/segment@0/target-module@40000
Console: colour dummy device 80x30
Calibrating delay loop... 996.14 BogoMIPS (lpj=4980736)
CPU: Testing write buffer coherency: ok
CPU0: Spectre v2: using BPIALL workaround
pid_max: default: 32768 minimum: 301
Mount-cache hash table entries: 1024 (order: 0, 4096 bytes, linear)
Mountpoint-cache hash table entries: 1024 (order: 0, 4096 bytes, linear)
VFS: Finished mounting rootfs on nullfs
Setting up static identity map for 0x80100000 - 0x80100054
Memory: 511664K/523264K available (2048K kernel code, 479K rwdata, 532K rodata, 2048K init, 180K bss, 10648K reserved, 0K cma-reserved)
devtmpfs: initialized
VFP support v0.3: implementor 41 architecture 3 part 30 variant c rev 3
posixtimers hash table entries: 512 (order: 0, 2048 bytes, linear)
futex hash table entries: 256 (3072 bytes on 1 NUMA nodes, total 3 KiB, linear).
DMA: preallocated 256 KiB pool for atomic coherent allocations
/ocp/interconnect@48000000/segment@300000/target-module@e000/lcdc@0: Fixed dependency cycle(s) with /ocp/interconnect@44c00000/segment@200000/target-module@b000/i2c@0/tda19988@70
/ocp/interconnect@44c00000/segment@200000/target-module@b000/i2c@0/tda19988@70: Fixed dependency cycle(s) with /ocp/interconnect@48000000/segment@300000/target-module@e000/lcdc@0
clocksource: Switched to clocksource dmtimer
workingset: timestamp_bits=30 (anon: 25) max_order=17 bucket_order=0 (anon: 0)
target-module@4b000000:target-module@140000:pmu@0:fck: device ID is greater than 24
Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
omap_voltage_late_init: Voltage driver support not added
printk: console [ttyS0] disabled
44e09000.serial: ttyS0 MMIO:0x44e09000 (irq = 18, base_baud = 3000000) is a 8250
printk: console [ttyS0] enabled
/ocp/interconnect@44c00000/segment@200000/target-module@10000/scm@0/pinmux@800: Fixed dependency cycle(s) with /ocp/interconnect@44c00000/segment@200000/target-module@10000/scm@0/pinmux@800/clkout2s
48000000.interconnect:segment@200000:target-module@0:mpu@0:fck: device ID is greater than 24
ti-sysc 44e31000.target-module: Failed to create device link (0x180) with supplier ocp for /ocp/interconnect@44c00000/segment@200000/target-module@31000/timer@0
ti-sysc 48040000.target-module: Failed to create device link (0x180) with supplier ocp for /ocp/interconnect@48000000/segment@0/target-module@40000/timer@0
omap_prm 44e00d00.prm: sync_state() pending due to 44d00000.cpu
clk: Disabling unused clocks
PM: genpd: Disabling unused power domains
Warning: unable to open an initial console.
Freeing unused kernel image (initmem) memory: 2048K
Run /init as init process

===== BRINGUP SERIAL SHELL =====
Linux version 7.4.0-rc4 (tengfei@debian) (arm-linux-gnueabihf-gcc (Debian 12.2.0-14) 12.2.0, GNU ld (GNU Binutils for Debian) 2.40) #22 Thu Nov 26 08:44:18 EST 2026
cmdline: console=ttyS0,115200n8
serial : 3816BBBK05DD
================================

~ #
```
## rootfs
initramfs其实是捆在内核里的rootfs，因为和内核绑定，所以可以在没有存储驱动的时候拿到用户态。但是initramfs下电即失，真实的环境肯定还是依赖非易失存储上的rootfs。
- 重建内核
``` bash
# 整个目录删掉，从零开始
rm -rf $HOME/build/bringup-kernel

make -C $HOME/opensource/linux-7.4-rc4 \
  O=$HOME/build/bringup-kernel \
  ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
  allnoconfig

tee -a $HOME/build/bringup-kernel/.config >/dev/null <<'EOF'
# ---- ARMv7 / SoC ----
CONFIG_MMU=y
CONFIG_ARCH_MULTI_V7=y
CONFIG_SOC_AM33XX=y
CONFIG_USE_OF=y
# 不让 SOC_AM33XX 把 TYPICAL 一揽子带进来
# CONFIG_ARCH_OMAP2PLUS_TYPICAL is not set

# ---- 串口控制台 ----
CONFIG_PRINTK=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_OMAP=y

# ---- 早期调试（可选）----
CONFIG_DEBUG_KERNEL=y
CONFIG_DEBUG_LL=y
CONFIG_DEBUG_AM33XXUART1=y
CONFIG_EARLY_PRINTK=y

# ---- 用户态 ABI：gnueabihf BusyBox + /init 脚本 ----
CONFIG_VFP=y
CONFIG_NEON=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y

# ---- /dev /proc /sys ----
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y

# ---- SD/MMC + ext4 ----
CONFIG_MMC=y
CONFIG_MMC_BLOCK=y
CONFIG_MMC_SDHCI=y
CONFIG_MMC_SDHCI_PLTFM=y
CONFIG_MMC_SDHCI_OMAP=y
CONFIG_DMADEVICES=y
CONFIG_TI_EDMA=y
CONFIG_PINCTRL_SINGLE=y
CONFIG_EXT4_FS=y

# ---- I2C / PMIC / regulator ----
CONFIG_I2C=y
CONFIG_I2C_OMAP=y
CONFIG_REGULATOR=y
CONFIG_REGULATOR_FIXED_VOLTAGE=y
CONFIG_MFD_TPS65217=y
CONFIG_REGULATOR_TPS65217=y
EOF

make -C $HOME/opensource/linux-7.4-rc4 \
  O=$HOME/build/bringup-kernel \
  ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig

make -C $HOME/opensource/linux-7.4-rc4 \
  O=$HOME/build/bringup-kernel \
  ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j4 zImage

make -C $HOME/opensource/linux-7.4-rc4 \
  O=$HOME/build/bringup-kernel \
  ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j4 ti/omap/am335x-boneblack.dtb

grep -E '^CONFIG_(ARCH_MULTI_V7|SOC_AM33XX|MMC|MMC_SDHCI_OMAP|EXT4_FS|VFP|NEON|INITRAMFS_SOURCE)=' \
  $HOME/build/bringup-kernel/.config
```
- 修改分区
``` bash
sudo umount /dev/sdb1 2>/dev/null || true

# 在 p1 之后追加 p2：1G，Linux 类型
echo 'start=133120, size=2097152, type=83' | sudo sfdisk --append /dev/sdb

sudo partprobe /dev/sdb || true
sudo udevadm settle

# 格式化 p2
sudo mkfs.ext4 -L ROOTFS -F /dev/sdb2

lsblk -f /dev/sdb
```
- 制作rootfs
``` bash
rm -rf $HOME/build/bringup-rootfs
mkdir -p $HOME/build/bringup-rootfs/bin \
         $HOME/build/bringup-rootfs/dev \
         $HOME/build/bringup-rootfs/proc \
         $HOME/build/bringup-rootfs/sys \
         $HOME/build/bringup-rootfs/tmp \
         $HOME/build/bringup-rootfs/root \
         $HOME/build/bringup-rootfs/etc \
         $HOME/build/bringup-rootfs/var/log \
         $HOME/build/bringup-rootfs/run

cp $HOME/build/bringup-busybox/busybox $HOME/build/bringup-rootfs/bin/busybox
chmod 755 $HOME/build/bringup-rootfs/bin/busybox

for a in sh mount umount cat echo ls ps mdev dmesg sleep grep cp mkdir sync uname ln rm mv setsid cttyhack; do
  ln -sf busybox $HOME/build/bringup-rootfs/bin/$a
done

cp $HOME/build/bringup-initramfs/init $HOME/build/bringup-rootfs/init
chmod 755 $HOME/build/bringup-rootfs/init

sudo mkdir -p /mnt/rootfs
sudo mount /dev/sdb2 /mnt/rootfs
sudo cp -a $HOME/build/bringup-rootfs/. /mnt/rootfs/
sudo chown -R root:root /mnt/rootfs
sudo chmod 1777 /mnt/rootfs/tmp
sync

ls -la /mnt/rootfs
ls -l /mnt/rootfs/bin
file /mnt/rootfs/bin/busybox
head -1 /mnt/rootfs/init

sudo umount /mnt/rootfs
```
- 切换 boot.scr 到 rootfs
``` bash
cat > $HOME/build/boot-rootfs.cmd <<'EOF'
echo "== bringup: rootfs from SD p2 =="
load mmc 0:1 ${kernel_addr_r} /zImage
load mmc 0:1 ${fdt_addr_r} /am335x-boneblack.dtb
setenv bootargs 'console=ttyS0,115200n8 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/init'
bootz ${kernel_addr_r} - ${fdt_addr_r}
EOF

$HOME/build/bringup-uboot/tools/mkimage -A arm -O linux -T script -C none \
  -n "bringup rootfs" -d $HOME/build/boot-rootfs.cmd $HOME/build/boot-rootfs.scr

sudo mkdir -p /mnt/sd
sudo mount /dev/sdb1 /mnt/sd
sudo cp $HOME/build/bringup-kernel/arch/arm/boot/zImage /mnt/sd/zImage
sudo cp $HOME/build/bringup-kernel/arch/arm/boot/dts/ti/omap/am335x-boneblack.dtb /mnt/sd/am335x-boneblack.dtb
sudo cp $HOME/build/boot-rootfs.scr /mnt/sd/boot.scr
sync

sha256sum $HOME/build/bringup-kernel/arch/arm/boot/zImage
sudo sha256sum /mnt/sd/zImage
sudo umount /mnt/sd
```

- 板上验证
``` bash
# 第一次启动
cat /proc/cmdline
grep ' / ' /proc/mounts
busybox df -h /

echo hello-from-rootfs > /root/persist
sync
cat /root/persist

busybox reboot -f
# 第二次启动
cat /root/persist
```
```
U-Boot 2027.01-rc2 (Nov 22 2026 - 04:33:29 -0500)

CPU  : AM335X-GP rev 2.1
Model: TI AM335x BeagleBone Black
DRAM:  512 MiB
Core:  218 devices, 21 uclasses, devicetree: separate
WDT:   Started wdt@0 with servicing every 1000ms (60s timeout)
NAND:  0 MiB
MMC:   OMAP SD/MMC: 0, OMAP SD/MMC: 1
Unable to read "uboot.env" from mmc0:1...
<ethaddr> not set. Validating first E-fuse MAC
Net:   eth2: switch@0using musb-hdrc, OUT ep1out IN ep1in STATUS ep2in
MAC de:ad:be:ef:00:01
HOST MAC de:ad:be:ef:00:00
RNDIS ready
, eth3: usb_ether

Hit any key to stop autoboot: 0
switch to partitions #0, OK
mmc0 is current device
Scanning mmc 0:1...
Found U-Boot script /boot.scr
338 bytes read in 1 ms (330.1 KiB/s)
## Executing script at 80000000
== bringup: rootfs from SD p2 ==
2146448 bytes read in 141 ms (14.5 MiB/s)
98486 bytes read in 9 ms (10.4 MiB/s)
Kernel image @ 0x82000000 [ 0x000000 - 0x20c090 ]
## Flattened Device Tree blob at 88000000
   Booting using the fdt blob at 0x88000000
Working FDT set to 88000000
   Loading Device Tree to 8ffe4000, end 8ffff0b5 ... OK
Working FDT set to 8ffe4000

Starting kernel ...

Booting Linux on physical CPU 0x0
Linux version 7.4.0-rc4 (tengfei@debian) (arm-linux-gnueabihf-gcc (Debian 12.2.0-14) 12.2.0, GNU ld (GNU Binutils for Debian) 2.40) #1 Sat Nov 28 03:10:22 EST 2026
CPU: ARMv7 Processor [413fc082] revision 2 (ARMv7), cr=50c5387d
CPU: PIPT / VIPT nonaliasing data cache, VIPT aliasing instruction cache
OF: fdt: Machine model: TI AM335x BeagleBone Black
Memory policy: Data cache writeback
OF: reserved mem: Reserved memory: No reserved-memory node in the DT
CPU: All CPU(s) started in SVC mode.
AM335X ES2.1 (sgx neon)
Zone ranges:
  Normal   [mem 0x0000000080000000-0x000000009fefffff]
Movable zone start for each node
Early memory node ranges
  node   0: [mem 0x0000000080000000-0x000000009fefffff]
Initmem setup node 0 [mem 0x0000000080000000-0x000000009fefffff]
On node 0, zone Normal: 256 pages in unavailable ranges
Kernel command line: console=ttyS0,115200n8 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/init
printk: log buffer data + meta data: 131072 + 409600 = 540672 bytes
Dentry cache hash table entries: 65536 (order: 6, 262144 bytes, linear)
Inode-cache hash table entries: 32768 (order: 5, 131072 bytes, linear)
Built 1 zonelists, mobility grouping on.  Total pages: 130816
mem auto-init: stack:all(zero), heap alloc:off, heap free:off
SLUB: HWalign=16, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
NR_IRQS: 16, nr_irqs: 16, preallocated irqs: 16
IRQ: Found an INTC at 0x(ptrval) (revision 5.0) with 128 interrupts
clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 19112604462750000 ns
TI gptimer clocksource: always-on /ocp/interconnect@44c00000/segment@200000/target-module@31000
sched_clock: 32 bits at 24MHz, resolution 41ns, wraps every 89478484971ns
clocksource: dmtimer: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 79635851949 ns
TI gptimer clockevent: 24000000 Hz at /ocp/interconnect@48000000/segment@0/target-module@40000
Console: colour dummy device 80x30
Calibrating delay loop... 996.14 BogoMIPS (lpj=4980736)
CPU: Testing write buffer coherency: ok
CPU0: Spectre v2: using BPIALL workaround
pid_max: default: 32768 minimum: 301
Mount-cache hash table entries: 1024 (order: 0, 4096 bytes, linear)
Mountpoint-cache hash table entries: 1024 (order: 0, 4096 bytes, linear)
VFS: Finished mounting rootfs on nullfs
Setting up static identity map for 0x80100000 - 0x80100054
Memory: 511652K/523264K available (3072K kernel code, 490K rwdata, 664K rodata, 1024K init, 181K bss, 10660K reserved, 0K cma-reserved)
devtmpfs: initialized
VFP support v0.3: implementor 41 architecture 3 part 30 variant c rev 3
posixtimers hash table entries: 512 (order: 0, 2048 bytes, linear)
futex hash table entries: 256 (3072 bytes on 1 NUMA nodes, total 3 KiB, linear).
DMA: preallocated 256 KiB pool for atomic coherent allocations
thermal_sys: Registered thermal governor 'step_wise'
/ocp/interconnect@48000000/segment@300000/target-module@e000/lcdc@0: Fixed dependency cycle(s) with /ocp/interconnect@44c00000/segment@200000/target-module@b000/i2c@0/tda0
/ocp/interconnect@44c00000/segment@200000/target-module@b000/i2c@0/tda19988@70: Fixed dependency cycle(s) with /ocp/interconnect@48000000/segment@300000/target-module@e000
clocksource: Switched to clocksource dmtimer
workingset: timestamp_bits=30 (anon: 25) max_order=17 bucket_order=0 (anon: 0)
target-module@4b000000:target-module@140000:pmu@0:fck: device ID is greater than 24
Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
omap_voltage_late_init: Voltage driver support not added
printk: console [ttyS0] disabled
44e09000.serial: ttyS0 MMIO:0x44e09000 (irq = 18, base_baud = 3000000) is a 8250
printk: console [ttyS0] enabled
/ocp/interconnect@44c00000/segment@200000/target-module@10000/scm@0/pinmux@800: Fixed dependency cycle(s) with /ocp/interconnect@44c00000/segment@200000/target-module@100s
pinctrl-single 44e10800.pinmux: 142 pins, size 568
OMAP GPIO hardware version 0.1
omap_i2c 4819c000.i2c: bus 2 rev0.11 at 100 kHz
sdhci-omap 481d8000.mmc: supply pbias not found, using dummy regulator
sdhci-omap 481d8000.mmc: supply vqmmc not found, using dummy regulator
48000000.interconnect:segment@200000:target-module@0:mpu@0:fck: device ID is greater than 24
edma 49000000.dma: TI EDMA DMA engine driver
ti-sysc 44e31000.target-module: Failed to create device link (0x180) with supplier ocp for /ocp/interconnect@44c00000/segment@200000/target-module@31000/timer@0
ti-sysc 48040000.target-module: Failed to create device link (0x180) with supplier ocp for /ocp/interconnect@48000000/segment@0/target-module@40000/timer@0
tps65217-pmic: Failed to locate of_node [id: -1]
tps65217-bl: Failed to locate of_node [id: -1]
tps65217 0-0024: TPS65217 ID 0xe version 1.2
omap_i2c 44e0b000.i2c: bus 0 rev0.11 at 400 kHz
omap_gpio 44e07000.gpio: Could not set line 6 debounce to 200000 microseconds (-22)
sdhci-omap 48060000.mmc: Got CD GPIO
sdhci-omap 48060000.mmc: supply pbias not found, using dummy regulator
sdhci-omap 48060000.mmc: supply vqmmc not found, using dummy regulator
omap_prm 44e00d00.prm: sync_state() pending due to 44d00000.cpu
clk: Disabling unused clocks
PM: genpd: Disabling unused power domains
sdhci-omap 481d8000.mmc: supply pbias not found, using dummy regulator
sdhci-omap 481d8000.mmc: supply vqmmc not found, using dummy regulator
mmc1: SDHCI controller on 481d8000.mmc [481d8000.mmc] using External DMA
mmc0: SDHCI controller on 48060000.mmc [48060000.mmc] using External DMA
Waiting for root device /dev/mmcblk0p2...
mmc0: new high speed SDHC card at address 0001
mmcblk0: mmc0:0001 SD16G 29.1 GiB
 mmcblk0: p1 p2
EXT4-fs (mmcblk0p2): recovery complete
EXT4-fs (mmcblk0p2): mounted filesystem 9a28ee34-eae2-4520-8639-84c16b5212a8 r/w with ordered data mode. Quota mode: disabled.
VFS: Mounted root (ext4 filesystem) on device 179:2.
devtmpfs: mounted
VFS: Pivoted into new rootfs
Freeing unused kernel image (initmem) memory: 1024K
Run /init as init process
mmc1: new high speed MMC card at address 0001
mmcblk1: mmc1:0001 S10004 3.56 GiB
 mmcblk1: p1 p2
mmcblk1boot0: mmc1:0001 S10004 4.00 MiB
mmcblk1boot1: mmc1:0001 S10004 4.00 MiB
mmcblk1rpmb: mmc1:0001 S10004 4.00 MiB, chardev (253:0)

===== BRINGUP SERIAL SHELL =====
Linux version 7.4.0-rc4 (tengfei@debian) (arm-linux-gnueabihf-gcc (Debian 12.2.0-14) 12.2.0, GNU ld (GNU Binutils for Debian) 2.40) #1 Sat Nov 28 03:10:22 EST 2026
cmdline: console=ttyS0,115200n8 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/init
serial : 3816BBBK05DD
================================

~ # cat /root/persist
hello-from-rootfs
~ #
```
可以看到，启动后使用rootfs作为根目录了。并且下电持久化也是正常的。
# fastboot
## 为什么用fastboot
在此之前，所有的系统烧录更新，都需要反复插拔SD卡，直观但是需要人工干预，也不利于自动化的操作。
而fastboot是U-Boot自带的一条USB通道，使得BBB成为一个USB device，而host就可以通过USB通道直接写入mmc分区。最早fastboot是Android的刷写协议，但U-Boot实现的通用的，不依赖Android用户态。
常见的fastboot用法有
- fastboot flash <target> <image> 整分区写，等价于将img 通过`dd`写入分区，不可以操作单文件，同时uboot所在整分区被刷写的话uboot.env也丢了。
- fastboot getvar 查询分区信息
- fastboot reboot 触发重启
因为fastboot工作在U-Boot阶段，所以它是不依赖kernel或者rootfs的。
我们未来希望是通过fastboot + A/B bank组合一起工作，但是本章节先不做AB分区，只验证fastboot的可行性。
## 确认当前fastboot的状态
因为我们编译U-Boot的时候默认就带了fastboot，可以看
``` bash
grep -E '^CONFIG_(CMD_FASTBOOT|FASTBOOT|USB_FUNCTION_FASTBOOT|FASTBOOT_FLASH|FASTBOOT_FLASH_MMC|USB_MUSB_GADGET|USB_GADGET)=' \
  $HOME/build/bringup-uboot/.config
```
所以我们的fastboot应该是直接可用的。另外需要注意，操作flash的时候需要带前缀0:N，其中0表示SD，1是emmc，如果不指明的话默认会刷到EMMC里，这应该是因为另一个配置项CONFIG_FASTBOOT_FLASH_MMC_DEV=1。
- target 侧
需要重启板子，并在u-boot阶段打断
``` bash
unbind ethernet 3
fastboot usb 0
```
因为BBB的miniUSB在U-Boot里同时被RNDIS ethernet gadget占用。直接 `fastboot usb 0` 可能抢不到 UDC，所以要先解绑再启动fastboot。解绑过程中出现类似
```
Clock disable failed for 0x44e0001c idlest 0x10000
Cannot find device 3 of class ethernet
```
的报错都是可以无视的，前者是因为时钟没关掉，后者是因为已经解绑过，不会影响后续我们开fastboot。
- host 侧
``` bash
$ fastboot devices
3816BBBK05DD    fastboot
```
能读到设备说明host 已经识别到板子了，链路是ok的。
``` bash
fastboot getvar partition-size:0:1
fastboot getvar partition-type:0:1
```
预期`0:1`是64M FAT。（getvar partition-size是32位截断的，大于4G的分区会显示0）。
## 制作镜像并刷写
按照我们的现状，如果制作一个p1的镜像，需要包含bootloader（MLO与u-boot.img，千万不能漏了，不然无法启动又要插拔SD卡救命了）、kernel、DTB、boot.scr。
``` bash
rm -f $HOME/build/p1-fastboot.img
truncate -s 64M $HOME/build/p1-fastboot.img
mformat -i $HOME/build/p1-fastboot.img -F -v BOOT ::

mcopy -i $HOME/build/p1-fastboot.img $HOME/build/bringup-uboot/MLO ::/MLO
mcopy -i $HOME/build/p1-fastboot.img $HOME/build/bringup-uboot/u-boot.img ::/u-boot.img
mcopy -i $HOME/build/p1-fastboot.img $HOME/build/bringup-kernel/arch/arm/boot/zImage ::/zImage
mcopy -i $HOME/build/p1-fastboot.img $HOME/build/bringup-kernel/arch/arm/boot/dts/ti/omap/am335x-boneblack.dtb ::/am335x-boneblack.dtb
mcopy -i $HOME/build/p1-fastboot.img $HOME/build/boot-rootfs.scr ::/boot.scr

mdir -i $HOME/build/p1-fastboot.img ::/
sha256sum $HOME/build/p1-fastboot.img
```
之后就可以通过fastboot通道刷入了
``` bash
fastboot flash 0:1 $HOME/build/p1-fastboot.img
fastboot reboot
```
同理，也可以针对P2
``` bash
# img
/usr/sbin/mke2fs -t ext4 -d $HOME/build/bringup-rootfs -F -L ROOTFS \
  $HOME/build/rootfs-fastboot.ext4 1G
# flash
fastboot flash 0:2 $HOME/build/rootfs-fastboot.ext4
fastboot reboot
```

# A/B + Meta分区

# HEALTH + WDG

# 安全回退
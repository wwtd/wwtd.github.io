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
BeagleBone Black也叫BBB，是社区里广泛使用的开源卡片电脑，生态位类似树莓派，又一些差异。BBB的详细介绍可以参见[What is BeagleBone® Black?](https://www.beagleboard.org/boards/beaglebone-black)。包括原理图、手册等也可以从官方网站上获得，全部开源。
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

# 




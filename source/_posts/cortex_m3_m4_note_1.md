---
title: 阅读 《ARM Cortex-M3 与 Cortex-M4 权威指南》 笔记 -- Part1
date: 2026-05-23 15:00:00
tags:
  - Arm Cortex-M
  - 读书记录
  - 《ARM Cortex-M3 与 Cortex-M4 权威指南》

---
# 前言
对于MCU也就是微控制器而言，Arm cortex M系列的MCU几乎是市场里的标杆和模范生了。为了更深入的理解cortex M3/M4及这一类型的MCU，因此选择了《ARM Cortex-M3 与 Cortex-M4 权威指南》第三版，来做深入的学习。

这本书我在不同的渠道收到多次推荐，应该是业界非常有名的指导书了，希望能有满意的收获。

在学习的过程中，可能会借由实验来验证或者加深理解，实验会尽可能通过虚拟环境来做。

## 关于cortex M3、M4
Cortex M3、M4均由ARM公司设计，两者都是32位的微处理器，其中M3发布于2005、2006年，M4发布于2010年。两者的主要差异在于，M4处理器支持浮点运算并拥有更好的DSP性能。
[ARM 文档中心](https://developer.arm.com/documentation)

# 实验环境搭建
得益于前人的智慧，对于cortex M的交叉编译、模拟、调试都有比较成熟的方案了，我的实验平台是一个x86的debian小主机，会主要通过arm-none-eabi-gcc系列交叉编译；通过qemu做模拟；通过gdb-multiarch做调试。
使用工具的具体版本如下：
| 工具 | 版本 | 用途 |
|------|------|------|
| `qemu-system-arm` | 7.2.22 | Cortex-M3/M4 机器模拟 |
| `arm-none-eabi-gcc` | 12.2.1 | ARM 裸机交叉编译器 |
| `gdb-multiarch` | 13.1 | 多架构 GDB 调试器 |
| `libnewlib-arm-none-eabi` | 3.3.0 | 裸机 C 库 |

而对于实验code的基础布局如下：
```
projects/01-env/
├── Makefile        # 构建系统
├── linker.ld       # 链接脚本
├── startup.c       # 向量表 + 启动代码
├── main.c          # 测试程序
└── debug.gdb       # GDB 调试脚本
```
各自细节如：
```Makefile
#Makefile
CFLAGS  = -Wall -Wextra -g -O0 -ffreestanding -nostdlib -mthumb
LDFLAGS = -Wl,-T,linker.ld -nostartfiles -nostdlib -lgcc

SRCS    = startup.c main.c

.PHONY: all clean m3 m4 qemu-m3 qemu-m4 gdb-m3 gdb-m4

all: m3 m4

m3: test-m3.elf
m4: test-m4.elf

test-m3.elf: $(SRCS) linker.ld
        arm-none-eabi-gcc $(CFLAGS) -mcpu=cortex-m3 $(LDFLAGS) -o $@ $(SRCS)

test-m4.elf: $(SRCS) linker.ld
        arm-none-eabi-gcc $(CFLAGS) -mcpu=cortex-m4 -mfloat-abi=soft $(LDFLAGS) -o $@ $(SRCS)

qemu-m3: test-m3.elf
        @echo "=== Cortex-M3 (lm3s6965evb) ==="
        qemu-system-arm -M lm3s6965evb -kernel test-m3.elf -nographic

qemu-m4: test-m4.elf
        @echo "=== Cortex-M4 (mps2-an386) ==="
        qemu-system-arm -M mps2-an386 -kernel test-m4.elf -nographic

qemu-gdb-m3: test-m3.elf
        @echo "=== QEMU waiting for GDB on :1234 (M3) ==="
        qemu-system-arm -M lm3s6965evb -kernel test-m3.elf -S -gdb tcp::1234 -nographic

qemu-gdb-m4: test-m4.elf
        @echo "=== QEMU waiting for GDB on :1234 (M4) ==="
        qemu-system-arm -M mps2-an386 -kernel test-m4.elf -S -gdb tcp::1234 -nographic

gdb:
        gdb-multiarch -q -ex "target remote :1234" test-m3.elf

clean:
        rm -f *.o *.elf *.map
```
```ld
# linker.ld
ENTRY(Reset_Handler)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 256K
    SRAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}

SECTIONS
{
    .vectors : {
        KEEP(*(.vectors))
    } > FLASH

    .text : {
        . = ALIGN(4);
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
        _etext = .;
    } > FLASH

    .data : {
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > SRAM AT > FLASH
    _sidata = LOADADDR(.data);

    .bss : {
        _sbss = .;
        __bss_start = _sbss;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
        __bss_end = _ebss;
    } > SRAM

    . = ALIGN(4);
    _end = .;
}
```
```c
// startup.c
extern unsigned int _sdata, _edata, _sbss, _ebss;
extern unsigned int _sidata;
extern int main(void);

__attribute__((naked)) void Reset_Handler(void) {
    unsigned int *src, *dst;

    src = &_sidata;
    dst = &_sdata;
    while (dst < &_edata)
        *dst++ = *src++;

    dst = &_sbss;
    while (dst < &_ebss)
        *dst++ = 0;

    main();

    while (1);
}

void Default_Handler(void) {
    while (1);
}

void NMI_Handler(void)         __attribute__((weak, alias("Default_Handler")));
void HardFault_Handler(void)   __attribute__((weak, alias("Default_Handler")));
void MemManage_Handler(void)   __attribute__((weak, alias("Default_Handler")));
void BusFault_Handler(void)    __attribute__((weak, alias("Default_Handler")));
void UsageFault_Handler(void)  __attribute__((weak, alias("Default_Handler")));
void SVC_Handler(void)         __attribute__((weak, alias("Default_Handler")));
void DebugMon_Handler(void)    __attribute__((weak, alias("Default_Handler")));
void PendSV_Handler(void)      __attribute__((weak, alias("Default_Handler")));
void SysTick_Handler(void)     __attribute__((weak, alias("Default_Handler")));

__attribute__((used, section(".vectors")))
void *vector_table[16] = {
    [0]  = (void *)0x20010000,
    [1]  = (void *)Reset_Handler,
    [2]  = (void *)NMI_Handler,
    [3]  = (void *)HardFault_Handler,
    [4]  = (void *)MemManage_Handler,
    [5]  = (void *)BusFault_Handler,
    [6]  = (void *)UsageFault_Handler,
    [11] = (void *)SVC_Handler,
    [12] = (void *)DebugMon_Handler,
    [14] = (void *)PendSV_Handler,
    [15] = (void *)SysTick_Handler,
};
```
```c
//main.c
volatile unsigned int counter;

int main(void) {
    counter = 0;
    while (1) {
        counter++;
    }
    return 0;
}
```
```
# debug.gdb
# 启动方式:
#   terminal 1: make qemu-gdb-m3   (或 qemu-gdb-m4)
#   terminal 2: gdb-multiarch -x debug.gdb
#
# 然后即可调试:
#   (gdb) break main        # 设置断点
#   (gdb) continue          # 运行到断点
#   (gdb) stepi             # 单步执行
#   (gdb) info registers    # 查看寄存器
#   (gdb) print counter     # 查看变量
#   (gdb) x/4xw 0x20000000  # 查看内存

file test-m3.elf
target remote :1234
```
## Makefile 目标

| 目标 | 说明 |
|------|------|
| `make m3` | 编译 Cortex-M3 ELF |
| `make m4` | 编译 Cortex-M4 ELF |
| `make qemu-m3` | 直接运行 M3 (无调试) |
| `make qemu-m4` | 直接运行 M4 (无调试) |
| `make qemu-gdb-m3` | M3 + GDB 等待连接 (:1234) |
| `make qemu-gdb-m4` | M4 + GDB 等待连接 (:1234) |
| `make gdb` | 连接 GDB 到 QEMU |
## QEMU 机器选型

- **Cortex-M3**: `lm3s6965evb` (TI Stellaris LM3S6965)
- **Cortex-M4**: `mps2-an386` (ARM MPS2 + AN386 FPGA)

两者均将代码映射到 `0x00000000`，SRAM 映射到 `0x20000000`，便于用同一套链接脚本。

- 如果希望使用其他机器，可以使用如下指令列出支持列表
```bash
qemu-system-arm -M help
```
## 实验环境验证
```bash
# terminal 1: 启动 QEMU (等待 GDB)
make qemu-gdb-m3
# terminal 2: 连接 GDB
make gdb
```

# 实验1：从 Reset 到 main——Cortex-M3 启动全流程跟踪
**目标**：结合反汇编与 GDB，完整跟踪 Cortex-M3 从上电复位到用户 main 函数执行的每一步，观察向量表布局、启动代码对 .bss 的初始化、函数调用时 LR 的变化，以及寄存器在循环中的活动。
**前提**：已完成环境搭建，能正常编译和启动 QEMU+GDB。
## 中断向量表与Reset_Handler
```bash
# 编译M3的elf
make m3
# 查看向量表
arm-none-eabi-objdump -s -j .vectors test-m3.elf
test-m3.elf:     file format elf32-littlearm
Contents of section .vectors:
 0000 00000120 41000000 89000000 89000000  ... A...........
 0010 89000000 89000000 89000000 00000000  ................
 0020 00000000 00000000 00000000 89000000  ................
 0030 89000000 00000000 89000000 89000000  ................
```
因为cortex-M3 是小端序的，所以实际这个表阅读方式是
| 偏移 | 值 (LE) | 对应异常 | 说明 |
|------|---------|----------|------|
| `0x0000` | `0x20010000` | 初始 MSP | 栈顶地址 |
| `0x0004` | `0x00000041` | Reset_Handler | 地址 `0x40`，bit 0 = 1 (Thumb) |
| `0x0008` | `0x00000089` | NMI_Handler | 地址 `0x88` (= Default_Handler) |
| `0x000C` | `0x00000089` | HardFault_Handler | 同上，弱符号 alias |
| `0x002C` | `0x00000089` | SVC_Handler | |
| `0x0030` | `0x00000089` | DebugMon_Handler | |
| `0x0038` | `0x00000089` | PendSV_Handler | |
| `0x003C` | `0x00000089` | SysTick_Handler | |

这里就是和我们startup.c里设置基本是对应的
```c
__attribute__((naked)) void Reset_Handler(void) {
/*
  something
*/
}

void Default_Handler(void) {
    while (1);
}

void NMI_Handler(void)         __attribute__((weak, alias("Default_Handler")));
void HardFault_Handler(void)   __attribute__((weak, alias("Default_Handler")));
void MemManage_Handler(void)   __attribute__((weak, alias("Default_Handler")));
void BusFault_Handler(void)    __attribute__((weak, alias("Default_Handler")));
void UsageFault_Handler(void)  __attribute__((weak, alias("Default_Handler")));
void SVC_Handler(void)         __attribute__((weak, alias("Default_Handler")));
void DebugMon_Handler(void)    __attribute__((weak, alias("Default_Handler")));
void PendSV_Handler(void)      __attribute__((weak, alias("Default_Handler")));
void SysTick_Handler(void)     __attribute__((weak, alias("Default_Handler")));

__attribute__((used, section(".vectors")))
void *vector_table[16] = {
    [0]  = (void *)0x20010000,
    [1]  = (void *)Reset_Handler,
    [2]  = (void *)NMI_Handler,
    [3]  = (void *)HardFault_Handler,
    [4]  = (void *)MemManage_Handler,
    [5]  = (void *)BusFault_Handler,
    [6]  = (void *)UsageFault_Handler,
    [11] = (void *)SVC_Handler,
    [12] = (void *)DebugMon_Handler,
    [14] = (void *)PendSV_Handler,
    [15] = (void *)SysTick_Handler,
};
```
稍微有一点值得提出的是，这里的函数地址bit0都被置为1了，这是因为cortex-M要求Thumb模式，而在取出PC后，硬件是会自动清除bit0的。
关于Reset_Handler，startup.c里我们写的其实是：
```c
extern unsigned int _sdata, _edata, _sbss, _ebss;
extern unsigned int _sidata;
extern int main(void);
__attribute__((naked)) void Reset_Handler(void) {
    unsigned int *src, *dst;

    src = &_sidata;
    dst = &_sdata;
    while (dst < &_edata)
        *dst++ = *src++;

    dst = &_sbss;
    while (dst < &_ebss)
        *dst++ = 0;

    main();

    while (1);
}
```
而我们通过反汇编，看一下实际编译生成的汇编代码其实是：
```bash
arm-none-eabi-objdump -d test-m3.elf | grep -A 40 '<Reset_Handler>'
```
```asm
00000040 <Reset_Handler>:
  40:   4d0c            ldr     r5, [pc, #48]   @ (74 <Reset_Handler+0x34>)
  42:   4c0d            ldr     r4, [pc, #52]   @ (78 <Reset_Handler+0x38>)
  44:   e005            b.n     52 <Reset_Handler+0x12>
  46:   462a            mov     r2, r5
  48:   1d15            adds    r5, r2, #4
  4a:   4623            mov     r3, r4
  4c:   1d1c            adds    r4, r3, #4
  4e:   6812            ldr     r2, [r2, #0]
  50:   601a            str     r2, [r3, #0]
  52:   4b0a            ldr     r3, [pc, #40]   @ (7c <Reset_Handler+0x3c>)
  54:   429c            cmp     r4, r3
  56:   d3f6            bcc.n   46 <Reset_Handler+0x6>
  58:   4c09            ldr     r4, [pc, #36]   @ (80 <Reset_Handler+0x40>)
  5a:   e003            b.n     64 <Reset_Handler+0x24>
  5c:   4623            mov     r3, r4
  5e:   1d1c            adds    r4, r3, #4
  60:   2200            movs    r2, #0
  62:   601a            str     r2, [r3, #0]
  64:   4b07            ldr     r3, [pc, #28]   @ (84 <Reset_Handler+0x44>)
  66:   429c            cmp     r4, r3
  68:   d3f8            bcc.n   5c <Reset_Handler+0x1c>
  6a:   f000 f811       bl      90 <main>
  6e:   bf00            nop
  70:   e7fd            b.n     6e <Reset_Handler+0x2e>
  72:   bf00            nop
  74:   000000ac        .word   0x000000ac
  78:   20000000        .word   0x20000000
  7c:   20000000        .word   0x20000000
  80:   20000000        .word   0x20000000
  84:   20000004        .word   0x20000004

00000088 <Default_Handler>:
  88:   b480            push    {r7}
  8a:   af00            add     r7, sp, #0
  8c:   bf00            nop
  8e:   e7fd            b.n     8c <Default_Handler+0x4>

00000090 <main>:
  90:   b480            push    {r7}
  92:   af00            add     r7, sp, #0
```
代码并不算长，我们尝试解读一下
```asm
00000040 <Reset_Handler>:
  40:   4d0c            ldr     r5, [pc, #48]   @ r5 = _sidata (0xac)
  42:   4c0d            ldr     r4, [pc, #52]   @ r4 = _sdata  (0x20000000)
  44:   e005            b.n     52              @ 跳转到条件检查
  ; .data 复制循环入口:
  46:   462a            mov     r2, r5
  48:   1d15            adds    r5, r2, #4      @ src++
  4a:   4623            mov     r3, r4
  4c:   1d1c            adds    r4, r3, #4      @ dst++
  4e:   6812            ldr     r2, [r2, #0]    @ r2 = *src
  50:   601a            str     r2, [r3, #0]    @ *dst = r2

  52:   4b0a            ldr     r3, [pc, #40]   @ r3 = _edata (0x20000000)
  54:   429c            cmp     r4, r3
  56:   d3f6            bcc.n   46              @ if dst < _edata, 继续复制
  ; .bss 清零循环入口:
  58:   4c09            ldr     r4, [pc, #36]   @ r4 = _sbss (0x20000000)
  5a:   e003            b.n     64              @ 跳转到条件检查

  5c:   4623            mov     r3, r4          @ r3 = dst
  5e:   1d1c            adds    r4, r3, #4      @ dst += 4
  60:   2200            movs    r2, #0          @ r2 = 0
  62:   601a            str     r2, [r3, #0]    @ *dst = 0

  64:   4b07            ldr     r3, [pc, #28]   @ r3 = _ebss (0x20000004)
  66:   429c            cmp     r4, r3
  68:   d3f8            bcc.n   5c              @ if dst < _ebss, 继续清零

  6a:   f000 f811       bl      90              @ 调用 main
  6e:   bf00            nop
  70:   e7fd            b.n     6e              @ main 返回后死循环
  72:   bf00            nop
  74:   000000ac        .word   0x000000ac
  78:   20000000        .word   0x20000000
  7c:   20000000        .word   0x20000000
  80:   20000000        .word   0x20000000
  84:   20000004        .word   0x20000004

00000088 <Default_Handler>:
  88:   b480            push    {r7}
  8a:   af00            add     r7, sp, #0
  8c:   bf00            nop
  8e:   e7fd            b.n     8c <Default_Handler+0x4>

00000090 <main>:
  90:   b480            push    {r7}
  92:   af00            add     r7, sp, #0
```
这里因为用到了链接脚本中的几个变量，这些变量的值也可以通过符号表二次确认：
```bash
arm-none-eabi-objdump -t test-m3.elf | grep -E "counter|_s[bd]|_e[bd]|_sidata"
000000ac g       *ABS*  00000000 _sidata
20000000 g       .bss   00000000 _sbss
20000000 g       .data  00000000 _sdata
20000004 g       .bss   00000000 _ebss
20000000 g     O .bss   00000004 counter
20000000 g       .data  00000000 _edata
```
能看出来，bss段唯一的一个4字节变量就是counter，所以Reset_Handler 也就是把它清零了。
## 通过GDB观察启动过程
两个终端，分别执行：
```bash
make qemu-gdb-m3
```
```bash
gdb-multiarch -q
```
然后在弹出来的gdb交互式窗口分别执行：
```gdb
file test-m3.elf
target remote :1234
info registers
```
```text
gdb-multiarch -q
(gdb) file test-m3.elf
Reading symbols from test-m3.elf...
(gdb) target remote :1234
Remote debugging using :1234
Reset_Handler () at startup.c:8
8           src = &_sidata;
(gdb) info registers
r0             0x0                 0
r1             0x0                 0
r2             0x0                 0
r3             0x0                 0
r4             0x0                 0
r5             0x0                 0
r6             0x0                 0
r7             0x0                 0
r8             0x0                 0
r9             0x0                 0
r10            0x0                 0
r11            0x0                 0
r12            0x0                 0
sp             0x20010000          0x20010000
lr             0xffffffff          -1
pc             0x40                0x40 <Reset_Handler>
xpsr           0x41000000          1090519040
```
这里其实就能看到，PC在0x40表示Reset_Handler。SP在0x20010000，是我们设置的初始栈指针。LR指向0xffffffff，表示在Thread模式使用MSP。XPSR在0x41000000，其bit24为1表示运行在Thumb模式。
接下来，可以用内存dump工具来看向量表在内存的布局。
```gdb
(gdb) x/16xw 0x00000000
0x0 <vector_table>:     0x20010000      0x00000041      0x00000089      0x00000089
0x10 <vector_table+16>: 0x00000089      0x00000089      0x00000089      0x00000000
0x20 <vector_table+32>: 0x00000000      0x00000000      0x00000000      0x00000089
0x30 <vector_table+48>: 0x00000089      0x00000000      0x00000089      0x00000089
```
和objdump的是完全一致的。

- 建立自动显示，让每次stepi后自动刷新关键值
```gdb
display/i $pc
display/4xw 0x20000000
display $lr
display $r4
```
接下来就可以stepi，一路单步执行下去
```gdb
stepi
stepi
stepi
stepi
```
```
(gdb) display/i $pc
1: x/i $pc
=> 0x40 <Reset_Handler>:        ldr     r5, [pc, #48]   @ (0x74 <Reset_Handler+52>)
(gdb) display/4xw 0x20000000
2: x/4xw 0x20000000
0x20000000 <counter>:   0x00000000      0x00000000      0x00000000      0x00000000
(gdb) display $lr
3: $lr = -1
(gdb) display $r4
4: $r4 = 0
(gdb) stepi
9           dst = &_sdata;
1: x/i $pc
=> 0x42 <Reset_Handler+2>:      ldr     r4, [pc, #52]   @ (0x78 <Reset_Handler+56>)
2: x/4xw 0x20000000
0x20000000 <counter>:   0x00000000      0x00000000      0x00000000      0x00000000
3: $lr = -1
4: $r4 = 0
(gdb) stepi
10          while (dst < &_edata)
1: x/i $pc
=> 0x44 <Reset_Handler+4>:      b.n     0x52 <Reset_Handler+18>
2: x/4xw 0x20000000
0x20000000 <counter>:   0x00000000      0x00000000      0x00000000      0x00000000
3: $lr = -1
4: $r4 = 536870912
(gdb) stepi
10          while (dst < &_edata)
1: x/i $pc
=> 0x52 <Reset_Handler+18>:     ldr     r3, [pc, #40]   @ (0x7c <Reset_Handler+60>)
2: x/4xw 0x20000000
0x20000000 <counter>:   0x00000000      0x00000000      0x00000000      0x00000000
3: $lr = -1
4: $r4 = 536870912
(gdb) stepi
0x00000054      10          while (dst < &_edata)
1: x/i $pc
=> 0x54 <Reset_Handler+20>:     cmp     r4, r3
2: x/4xw 0x20000000
0x20000000 <counter>:   0x00000000      0x00000000      0x00000000      0x00000000
3: $lr = -1
4: $r4 = 536870912
```
reset 芯片，然后给程序的关键地址打上断点，重新观察流程
```gdb
(gdb) monitor system_reset
(gdb) info registers
r0             0x0                 0
r1             0x0                 0
r2             0x0                 0
r3             0x0                 0
r4             0x0                 0
r5             0xac                172
r6             0x0                 0
r7             0x0                 0
r8             0x0                 0
r9             0x0                 0
r10            0x0                 0
r11            0x0                 0
r12            0x0                 0
sp             0x20010000          0x20010000
lr             0xffffffff          -1
pc             0x42                0x42 <Reset_Handler+2>
xpsr           0x41000000          1090519040
```
```gdb
(gdb) break *0x58
Breakpoint 1 at 0x58: file startup.c, line 13.
(gdb) break *0x5c
Breakpoint 2 at 0x5c: file startup.c, line 15.
(gdb) break *0x62
Breakpoint 3 at 0x62: file startup.c, line 15.
(gdb) break *0x6a
Breakpoint 4 at 0x6a: file startup.c, line 17.
(gdb) break main
Breakpoint 5 at 0x94: file main.c, line 4.
(gdb) continue
Continuing.

Breakpoint 1, Reset_Handler () at startup.c:13
13          dst = &_sbss;
1: x/i $pc
=> 0x58 <Reset_Handler+24>:     ldr     r4, [pc, #36]   @ (0x80 <Reset_Handler+64>)
2: x/4xw 0x20000000
0x20000000 <counter>:   0x00000000      0x00000000      0x00000000      0x00000000
3: $lr = -1
4: $r4 = 536870912
(gdb) continue
Continuing.

Breakpoint 2, Reset_Handler () at startup.c:15
15              *dst++ = 0;
1: x/i $pc
=> 0x5c <Reset_Handler+28>:     mov     r3, r4
2: x/4xw 0x20000000
0x20000000 <counter>:   0x00000000      0x00000000      0x00000000      0x00000000
3: $lr = -1
4: $r4 = 536870912
(gdb) continue
Continuing.

Breakpoint 3, 0x00000062 in Reset_Handler () at startup.c:15
15              *dst++ = 0;
1: x/i $pc
=> 0x62 <Reset_Handler+34>:     str     r2, [r3, #0]
2: x/4xw 0x20000000
0x20000000 <counter>:   0x00000000      0x00000000      0x00000000      0x00000000
3: $lr = -1
4: $r4 = 536870916
(gdb) continue
Continuing.

Breakpoint 4, Reset_Handler () at startup.c:17
17          main();
1: x/i $pc
=> 0x6a <Reset_Handler+42>:     bl      0x90 <main>
2: x/4xw 0x20000000
0x20000000 <counter>:   0x00000000      0x00000000      0x00000000      0x00000000
3: $lr = -1
4: $r4 = 536870916
(gdb) continue
Continuing.

Breakpoint 5, main () at main.c:4
4           counter = 0;
1: x/i $pc
=> 0x94 <main+4>:       ldr     r3, [pc, #16]   @ (0xa8 <main+24>)
2: x/4xw 0x20000000
0x20000000 <counter>:   0x00000000      0x00000000      0x00000000      0x00000000
3: $lr = 111
4: $r4 = 536870916
```

在这样的流程里，基本上观察到了启动过程里cpu的行为。

# To Be Continued
要学习和记录的内容比较多，先来一篇博文记录最开始的内容，后续会随着阅读的深入对各重点内容加以记录与实验。
感谢阅读~
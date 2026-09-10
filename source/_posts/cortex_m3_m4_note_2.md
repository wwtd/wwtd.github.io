---
title: 从C语言到汇编指令
date: 2026-05-27 21:00:00
tags:
  - Arm Cortex-M
  - 读书记录
  - 《ARM Cortex-M3 与 Cortex-M4 权威指南》

---
# 前言
本文实际是《ARM Cortex-M3 与 Cortex-M4 权威指南》阅读笔记的系列第二篇，主要对应原书第五章（指令集）的学习内容。单纯的列cpu支持哪些指令集实在是不令人感到有趣的内容，因此本章的学习角度将会是从常见的C语言语法出发，观察我们常见的高级语言实际映射到机器的指令集会是什么样的。

## 关于本文的组织方式
前面的**前言**和**环境搭建**是预备章节，一次性搭建好贯穿全文的实验环境。后续各节（01-math、02-bitops ……）彼此平铺、按编号顺序展开，没有复杂的层级关系。每节独立阅读也可以，但建议从前到后走一遍。
文中以原文形式直接贴出了全部关键源码，而不是提供git仓库链接。这样做是故意的——亲手把代码敲进编辑器、亲眼看到编译和反汇编的输出，比单纯git clone然后make获得的体感深得多。花几分钟搭建一个环境，后续每个实验就只需要改一个.c 文件，这笔时间值得投入。

# 测试环境搭建
文件整体布局与上一篇类似，只是将main.c 换成了xx-xxxx.c
```bash
tree
.
├── 01-math.c
├── 02-bitops.c
├── 03-types.c
├── 04-if.c
├── 05-switch.c
├── 06-loop.c
├── 07-break-continue-goto.c
├── 08-logic-short-circuit.c
├── 09b-call-many-args.c
├── 09-call-basics.c
├── 10b-static-local.c
├── 10-stack-frame.c
├── 11-recursion.c
├── 12-function-pointer.c
├── 13-globals.c
├── 14-const.c
├── 15-pointer.c
├── 16-struct.c
├── 17-memcpy-memset.c
├── 18-malloc.c
├── 19-volatile.c
├── 20-atomic.c
├── 21-concurrency.c
├── 22-reentrancy.c
├── 23-float.c
├── 24-cast.c
├── 25-optimization.c
├── 26-tail-call.c
├── 27-dead-code.c
├── 30-pointer-cast.c
├── 31-strict-aliasing.c
├── 32-integer-overflow.c
├── 33-signed-compare.c
├── 34-null-ptr.c
├── 35-stack-overflow.c
├── 36-use-after-return.c
├── debug.gdb
├── linker.ld
├── Makefile
├── _sbrk.c
└── startup.c
```
其中带数字编号的均为设计的实验函数，此处不做展开，后续依次介绍。其余部分为实验环境依赖的内容，分别展开说一下：
```bash
cat debug.gdb
# 使用方式:
#   终端1: make qemu-gdb-09-call-basics
#   终端2: gdb-multiarch -x debug.gdb
#   在 GDB 内: file 09-call-basics.elf
target remote :1234
```
```ld
#linker.ld
ENTRY(Reset_Handler)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 256K
    SRAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}

SECTIONS
{
    .vectors : { KEEP(*(.vectors)) } > FLASH

    .text : {
        *(.text*)
        *(.rodata*)
        _etext = .;
    } > FLASH

    .data : {
        _sdata = .;
        *(.data*)
        _edata = .;
    } > SRAM AT > FLASH
    _sidata = LOADADDR(.data);

    .bss : {
        _sbss = .;
        *(.bss*)
        *(COMMON)
        _ebss = .;
    } > SRAM

    _end = .;
}
```
```makefile
CFLAGS  = -Wall -Wno-unused-but-set-variable -Wno-unused-function -g -O0 -ffreestanding -mthumb -mcpu=cortex-m3

.PHONY: clean qemu-gdb

# make math.elf         → 编译 math.c
# make qemu-gdb-math    → QEMU + GDB 模式启动 math.elf
%.elf: %.c startup.c linker.ld
        arm-none-eabi-gcc $(CFLAGS) -Wl,-T,linker.ld -nostartfiles -nostdlib -o $@ startup.c $< -lgcc -lc

# 需要 malloc 时 (需要 _sbrk):  make libc-malloc.elf
libc-%.elf: %.c startup.c linker.ld _sbrk.c
        arm-none-eabi-gcc $(CFLAGS) -Wl,-T,linker.ld -nostartfiles -specs=nano.specs -o $@ startup.c $< _sbrk.c -lgcc -lc

qemu-gdb-%: %.elf
        qemu-system-arm -M lm3s6965evb -kernel $< -S -gdb tcp::1234 -nographic

clean:
        rm -f *.elf
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
//_sbrk.c
#include <sys/types.h>
#include <errno.h>

extern unsigned int _end;

caddr_t _sbrk(int incr) {
    static unsigned char *heap = NULL;
    unsigned char *prev_heap;

    if (heap == NULL)
        heap = (unsigned char *)&_end;

    prev_heap = heap;
    heap += incr;
    return (caddr_t)prev_heap;
}
```

验证搭建成功
```c
// 01-math.c
/*
 * 观察目标: 加减乘除取余的指令映射
 *
 * 编译: make 01-math.elf
 * 反汇编: arm-none-eabi-objdump -d 01-math.elf
 *
 * 关注点:
 *   1. ADDS/SUBS/MULS 与 C 运算的一一对应
 *   2. 除法在 M3 上调用 __aeabi_idiv (无硬件除法指令)
 *   3. 取余也调用 __aeabi_idivmod (返回商和余数)
 *   4. 复合赋值 += 不会产生额外指令
 */

static int add(int a, int b)      { return a + b; }
static int sub(int a, int b)      { return a - b; }
static int mul(int a, int b)      { return a * b; }
static int divide(int a, int b)   { return a / b; }
static int modulo(int a, int b)   { return a % b; }
static int compound(int a)        { a += 42; return a; }

int main(void) {
    volatile int r;
    r = add(10, 20);
    r = sub(100, 33);
    r = mul(7, 6);
    r = divide(100, 3);
    r = modulo(100, 3);
    r = compound(1);
    return 0;
}
```

```bash
make 01-math.elf  # 观察有elf生成
arm-none-eabi-objdump -d 01-math.elf # 可以看到反汇编指令
make qemu-gdb-01-math # 启动qemu等待gdb
make libc-18-malloc.elf # 需要libc（malloc） 时
```

# 算数运算
```c
// 01-math.c
/*
 * 观察目标: 加减乘除取余的指令映射
 *
 * 编译: make 01-math.elf
 * 反汇编: arm-none-eabi-objdump -d 01-math.elf
 *
 * 关注点:
 *   1. ADDS/SUBS/MULS 与 C 运算的一一对应
 *   2. 除法在 M3 上调用 __aeabi_idiv (无硬件除法指令)
 *   3. 取余也调用 __aeabi_idivmod (返回商和余数)
 *   4. 复合赋值 += 不会产生额外指令
 */

static int add(int a, int b)      { return a + b; }
static int sub(int a, int b)      { return a - b; }
static int mul(int a, int b)      { return a * b; }
static int divide(int a, int b)   { return a / b; }
static int modulo(int a, int b)   { return a % b; }
static int compound(int a)        { a += 42; return a; }

int main(void) {
    volatile int r;
    r = add(10, 20);
    r = sub(100, 33);
    r = mul(7, 6);
    r = divide(100, 3);
    r = modulo(100, 3);
    r = compound(1);
    return 0;
}
```
来看一下生成的汇编指令是怎么样的。
```bash
arm-none-eabi-objdump -d 01-math.elf

01-math.elf:     file format elf32-littlearm


Disassembly of section .text:

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
  6a:   f000 f866       bl      13a <main>
  6e:   bf00            nop
  70:   e7fd            b.n     6e <Reset_Handler+0x2e>
  72:   bf00            nop
  74:   00000190        .word   0x00000190
  78:   20000000        .word   0x20000000
  7c:   20000000        .word   0x20000000
  80:   20000000        .word   0x20000000
  84:   20000000        .word   0x20000000

00000088 <Default_Handler>:
  88:   b480            push    {r7}
  8a:   af00            add     r7, sp, #0
  8c:   bf00            nop
  8e:   e7fd            b.n     8c <Default_Handler+0x4>

00000090 <add>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6039            str     r1, [r7, #0]
  9a:   687a            ldr     r2, [r7, #4]
  9c:   683b            ldr     r3, [r7, #0]
  9e:   4413            add     r3, r2
  a0:   4618            mov     r0, r3
  a2:   370c            adds    r7, #12
  a4:   46bd            mov     sp, r7
  a6:   bc80            pop     {r7}
  a8:   4770            bx      lr

000000aa <sub>:
  aa:   b480            push    {r7}
  ac:   b083            sub     sp, #12
  ae:   af00            add     r7, sp, #0
  b0:   6078            str     r0, [r7, #4]
  b2:   6039            str     r1, [r7, #0]
  b4:   687a            ldr     r2, [r7, #4]
  b6:   683b            ldr     r3, [r7, #0]
  b8:   1ad3            subs    r3, r2, r3
  ba:   4618            mov     r0, r3
  bc:   370c            adds    r7, #12
  be:   46bd            mov     sp, r7
  c0:   bc80            pop     {r7}
  c2:   4770            bx      lr

000000c4 <mul>:
  c4:   b480            push    {r7}
  c6:   b083            sub     sp, #12
  c8:   af00            add     r7, sp, #0
  ca:   6078            str     r0, [r7, #4]
  cc:   6039            str     r1, [r7, #0]
  ce:   687b            ldr     r3, [r7, #4]
  d0:   683a            ldr     r2, [r7, #0]
  d2:   fb02 f303       mul.w   r3, r2, r3
  d6:   4618            mov     r0, r3
  d8:   370c            adds    r7, #12
  da:   46bd            mov     sp, r7
  dc:   bc80            pop     {r7}
  de:   4770            bx      lr

000000e0 <divide>:
  e0:   b480            push    {r7}
  e2:   b083            sub     sp, #12
  e4:   af00            add     r7, sp, #0
  e6:   6078            str     r0, [r7, #4]
  e8:   6039            str     r1, [r7, #0]
  ea:   687a            ldr     r2, [r7, #4]
  ec:   683b            ldr     r3, [r7, #0]
  ee:   fb92 f3f3       sdiv    r3, r2, r3
  f2:   4618            mov     r0, r3
  f4:   370c            adds    r7, #12
  f6:   46bd            mov     sp, r7
  f8:   bc80            pop     {r7}
  fa:   4770            bx      lr

000000fc <modulo>:
  fc:   b480            push    {r7}
  fe:   b083            sub     sp, #12
 100:   af00            add     r7, sp, #0
 102:   6078            str     r0, [r7, #4]
 104:   6039            str     r1, [r7, #0]
 106:   687b            ldr     r3, [r7, #4]
 108:   683a            ldr     r2, [r7, #0]
 10a:   fb93 f2f2       sdiv    r2, r3, r2
 10e:   6839            ldr     r1, [r7, #0]
 110:   fb01 f202       mul.w   r2, r1, r2
 114:   1a9b            subs    r3, r3, r2
 116:   4618            mov     r0, r3
 118:   370c            adds    r7, #12
 11a:   46bd            mov     sp, r7
 11c:   bc80            pop     {r7}
 11e:   4770            bx      lr

00000120 <compound>:
 120:   b480            push    {r7}
 122:   b083            sub     sp, #12
 124:   af00            add     r7, sp, #0
 126:   6078            str     r0, [r7, #4]
 128:   687b            ldr     r3, [r7, #4]
 12a:   332a            adds    r3, #42 @ 0x2a
 12c:   607b            str     r3, [r7, #4]
 12e:   687b            ldr     r3, [r7, #4]
 130:   4618            mov     r0, r3
 132:   370c            adds    r7, #12
 134:   46bd            mov     sp, r7
 136:   bc80            pop     {r7}
 138:   4770            bx      lr

0000013a <main>:
 13a:   b580            push    {r7, lr}
 13c:   b082            sub     sp, #8
 13e:   af00            add     r7, sp, #0
 140:   2114            movs    r1, #20
 142:   200a            movs    r0, #10
 144:   f7ff ffa4       bl      90 <add>
 148:   4603            mov     r3, r0
 14a:   607b            str     r3, [r7, #4]
 14c:   2121            movs    r1, #33 @ 0x21
 14e:   2064            movs    r0, #100        @ 0x64
 150:   f7ff ffab       bl      aa <sub>
 154:   4603            mov     r3, r0
 156:   607b            str     r3, [r7, #4]
 158:   2106            movs    r1, #6
 15a:   2007            movs    r0, #7
 15c:   f7ff ffb2       bl      c4 <mul>
 160:   4603            mov     r3, r0
 162:   607b            str     r3, [r7, #4]
 164:   2103            movs    r1, #3
 166:   2064            movs    r0, #100        @ 0x64
 168:   f7ff ffba       bl      e0 <divide>
 16c:   4603            mov     r3, r0
 16e:   607b            str     r3, [r7, #4]
 170:   2103            movs    r1, #3
 172:   2064            movs    r0, #100        @ 0x64
 174:   f7ff ffc2       bl      fc <modulo>
 178:   4603            mov     r3, r0
 17a:   607b            str     r3, [r7, #4]
 17c:   2001            movs    r0, #1
 17e:   f7ff ffcf       bl      120 <compound>
 182:   4603            mov     r3, r0
 184:   607b            str     r3, [r7, #4]
 186:   2300            movs    r3, #0
 188:   4618            mov     r0, r3
 18a:   3708            adds    r7, #8
 18c:   46bd            mov     sp, r7
 18e:   bd80            pop     {r7, pc}
```
## add
对于add 函数，C语言的函数原型和编译出来的源码放一起对比一下看看:
```c
// 函数的内容就没什么好说的了，两个参数输入，做了加法之后返回一个返回值
static int add(int a, int b)      { return a + b; }
```

``` asm
00000090 <add>:
  ; === 1. 函数序言 (prologue) ===
  90:   b480            push    {r7}            ; 保存旧 R7（帧指针）
  92:   b083            sub     sp, #12         ; 在栈上分配 12 字节局部空间
  94:   af00            add     r7, sp, #0      ; R7 = SP（帧指针指向当前栈底）
  ; === 2.1 接收参数 (R0 / R1) ===
  96:   6078            str     r0, [r7, #4]    ; a → 栈上 [R7+4]
  98:   6039            str     r1, [r7, #0]    ; b → 栈上 [R7+0]
  ; === 2.2 核心运算: a + b ===
  9a:   687a            ldr     r2, [r7, #4]    ; 从栈 reload a
  9c:   683b            ldr     r3, [r7, #0]    ; 从栈 reload b
  9e:   4413            add     r3, r2          ; r3 = a + b  ← C 的 + 在这里
  ; === 3. 返回值 + 函数收尾 (epilogue) ===
  a0:   4618            mov     r0, r3          ; 返回值写入 R0
  a2:   370c            adds    r7, #12         ; 恢复 SP
  a4:   46bd            mov     sp, r7
  a6:   bc80            pop     {r7}            ; 恢复旧 R7
  a8:   4770            bx      lr              ; 返回调用者
```

一般来说，一段汇编函数的阅读都可以分为序言、函数体、收尾 三个部分：
- 序言是函数刚进来的时候保存现场然后分配函数内需要的空间
- 函数体包含了函数的核心逻辑
- 收尾部分则是用来恢复现场、返回调用者的
因为最开始的实验我们使用的是-O0 也就是无优化，所以参数会先被存到栈上再被reload 使用（也就是str、ldr部分）。
而当后续使用较高的优化等级时，这里的参数就会直接在寄存器操作了。而这里的进栈再reload（也称为spill）是为了在调试过程可以方便的修改参数的值。
这里将str 参数的部分单独的分成一个小的逻辑块，就是2.1 接受参数。
总的来看这里的流程：
**函数序言**
因为GCC 的帧指针布局需要使用R7寄存器，所以进来先把R7 入栈。
同样后面会需要两个栈上的临时变量，所以给SP向下偏移获取临时空间，两个u32其实是8个字节，但是这里实际偏移了12个字节，也就是三个uint32的大小。
这样是因为SP需要一直满足 %8 == 0，如果不加padding的话，SP无法满足%8的约束了（%8 的约束可以参考AAPCS）。
然后将SP的值，也就是我们当前可用的栈的边界，存入R7。
最终我们能看到一个类似这样的栈上内存布局，
```
                    高地址
    ┌──────────────────────┐
    │         ...          │
    │   调用者的栈帧       │
    ├──────────────────────┤ ← 入口 SP（%8 == 0）
    │  [保存的 R7]         │ ← 入口SP-4（push 写入）
    ├──────────────────────┤ ← push 之后 SP（%4 == 0, %8 != 0）
    │  [padding: 4 bytes]  │
    │  [局部变量 a]        │  ← 这 12 字节 =
    │  [局部变量 b]        │     sub sp, #12 刚腾出来的
    ├──────────────────────┤ ← sub sp, #12 之后 SP（当前 SP，%8 == 0）
    │         ...          │
    └──────────────────────┘
                    低地址
```

**接收参数**
也是参考AAPCS，如果一个函数有两个入参，那么caller会把这两个参数分别放到R0和R1。
所以，这里用str指令将R0、R1分别存入R7+4，和R7+0的位置，所以a 和 b 的具体位置我们也是能看到的了。

**核心运算**
核心运算说白了就一个add指令，但是由于我们上面提到的spill，编译器在-O0的时候又先把a 和 b 从SP +4、SP+0 ldr到r2、r3寄存器了。
最终调用add r3 r2；将a 和 b相加的结果放入r3。走到这一步，我们已经拿到了c = a + b的值，值就在r3里。

**函数收尾**
这里其实主要做几个事情，首先按照AAPCS函数运算后的返回值传递约定，应该将最后的运算结果放到R0，而现在结果在R3里，所以要把R3 的结果复制到R0里。
另外，栈上分配的临时空间偏移了12个长度，要还回去，所以通过R7加12 算一下偏移12 之前的SP值，然后将结果还回SP。
然后我们在函数进入的是时候把R7 入栈了，要回归原样，所以要pop r7。
经过一通操作，我们已经把整个栈和寄存器都变成了原样，并且已经把返回值放到了R0，接下来只需要退出函数将扩展权交还caller就好，那就是bx lr。

值得一提的是，如果我们人工编写汇编代码的话，这里的逻辑完全可以简化成只有两行:
``` asm
add     r0, r1
bx      lr
```

## sub
sub 和 add 就非常非常一致了，不再详细展开，只点明关键部分：
```c
static int sub(int a, int b)      { return a - b; }
```

``` asm
000000aa <sub>:
  aa:   b480            push    {r7}
  ac:   b083            sub     sp, #12
  ae:   af00            add     r7, sp, #0
  b0:   6078            str     r0, [r7, #4]
  b2:   6039            str     r1, [r7, #0]
  b4:   687a            ldr     r2, [r7, #4]
  b6:   683b            ldr     r3, [r7, #0]
  b8:   1ad3            subs    r3, r2, r3    ; 关键逻辑
  ba:   4618            mov     r0, r3
  bc:   370c            adds    r7, #12
  be:   46bd            mov     sp, r7
  c0:   bc80            pop     {r7}
  c2:   4770            bx      lr
```
只将adds 换成subs 即可。

## mul
```c
static int mul(int a, int b)      { return a * b; }
```
``` asm
000000c4 <mul>:
  c4:   b480            push    {r7}
  c6:   b083            sub     sp, #12
  c8:   af00            add     r7, sp, #0
  ca:   6078            str     r0, [r7, #4]
  cc:   6039            str     r1, [r7, #0]
  ce:   687b            ldr     r3, [r7, #4]
  d0:   683a            ldr     r2, [r7, #0]
  d2:   fb02 f303       mul.w   r3, r2, r3
  d6:   4618            mov     r0, r3
  d8:   370c            adds    r7, #12
  da:   46bd            mov     sp, r7
  dc:   bc80            pop     {r7}
  de:   4770            bx      lr
```
只将adds 换成mul.w 即可。
## divide
``` c
static int divide(int a, int b)   { return a / b; }
```
``` asm
000000e0 <divide>:
  e0:   b480            push    {r7}
  e2:   b083            sub     sp, #12
  e4:   af00            add     r7, sp, #0
  e6:   6078            str     r0, [r7, #4]
  e8:   6039            str     r1, [r7, #0]
  ea:   687a            ldr     r2, [r7, #4]
  ec:   683b            ldr     r3, [r7, #0]
  ee:   fb92 f3f3       sdiv    r3, r2, r3
  f2:   4618            mov     r0, r3
  f4:   370c            adds    r7, #12
  f6:   46bd            mov     sp, r7
  f8:   bc80            pop     {r7}
  fa:   4770            bx      lr
```
只将adds 换成sdiv即可。
## modulo
``` c
static int modulo(int a, int b)   { return a % b; }
```
``` asm
000000fc <modulo>:
  fc:   b480            push    {r7}
  fe:   b083            sub     sp, #12
 100:   af00            add     r7, sp, #0
 102:   6078            str     r0, [r7, #4]
 104:   6039            str     r1, [r7, #0]
 106:   687b            ldr     r3, [r7, #4]
 108:   683a            ldr     r2, [r7, #0]
 10a:   fb93 f2f2       sdiv    r2, r3, r2
 10e:   6839            ldr     r1, [r7, #0]
 110:   fb01 f202       mul.w   r2, r1, r2
 114:   1a9b            subs    r3, r3, r2
 116:   4618            mov     r0, r3
 118:   370c            adds    r7, #12
 11a:   46bd            mov     sp, r7
 11c:   bc80            pop     {r7}
 11e:   4770            bx      lr
```
这里的取余，其实是a % b = a - (a / b) * b，然后综合用了sdiv、mul.w、subs 计算得到的。
## compound
``` c
static int compound(int a)        { a += 42; return a; }
```
``` asm
00000120 <compound>:
 120:   b480            push    {r7}
 122:   b083            sub     sp, #12
 124:   af00            add     r7, sp, #0
 126:   6078            str     r0, [r7, #4]
 128:   687b            ldr     r3, [r7, #4]
 12a:   332a            adds    r3, #42 @ 0x2a
 12c:   607b            str     r3, [r7, #4]
 12e:   687b            ldr     r3, [r7, #4]
 130:   4618            mov     r0, r3
 132:   370c            adds    r7, #12
 134:   46bd            mov     sp, r7
 136:   bc80            pop     {r7}
 138:   4770            bx      lr
```
这里同样偏移 12，原因与 add 相同（AAPCS %8 对齐 + GCC 的帧指针布局），不再赘述。见 add 节分析。
## 拓展：关闭帧指针 (fomit-frame-pointer)
GCC默认使用R7作为帧指针（frame-pointer），为了观察GCC的frame-pointer约定对汇编代码生成的影响，我们可以用-fomit-frame-pointer flag来使GCC跳过对R7的这个使用，这样生成的汇编结果将会有明显的差异。给出编译指令与结果，读者可自行体会。
``` bash
arm-none-eabi-gcc -Wall -Wno-unused-but-set-variable -Wno-unused-function -g -O0 -ffreestanding -mthumb -mcpu=cortex-m3 -Wl,-T,linker.ld -nostartfiles -nostdlib -fomit-frame-pointer -o 01-math.elf startup.c 01-math.c -lgcc
arm-none-eabi-objdump -d 01-math.elf
```
``` asm
;......
000000f4 <compound>:
  f4:   b082            sub     sp, #8
  f6:   9001            str     r0, [sp, #4]
  f8:   9b01            ldr     r3, [sp, #4]
  fa:   332a            adds    r3, #42 @ 0x2a
  fc:   9301            str     r3, [sp, #4]
  fe:   9b01            ldr     r3, [sp, #4]
 100:   4618            mov     r0, r3
 102:   b002            add     sp, #8
 104:   4770            bx      lr
;......
```
# 位运算及自增自减
``` c
/*
 * 观察目标: 位运算及自增自减
 *
 * 编译: make 02-bitops.elf
 * 反汇编: arm-none-eabi-objdump -d 02-bitops.elf
 *
 * 关注点:
 *   1. ANDS / ORRS / EORS / MVNS 直接对应 & | ^ ~
 *   2. LSLS / LSRS / ASRS 对应 << 以及 >> (无符号/有符号)
 *   3. 自增 ++ 在前 (prefix) 与在后 (postfix) 的指令序列差异
 *   4. 复合位运算赋值 &= |= 的实现
 */

static int bit_and(int a, int b)   { return a & b; }
static int bit_or(int a, int b)    { return a | b; }
static int bit_xor(int a, int b)   { return a ^ b; }
static int bit_not(int a)          { return ~a; }

static int shift_left(int a)       { return a << 3; }
static int shift_right_unsigned(unsigned int a) { return a >> 3; }
static int shift_right_signed(int a)           { return a >> 3; }

static int prefix_inc(int a)       { return ++a; }
static int postfix_inc(int a)      { return a++; }
static int prefix_dec(int a)       { return --a; }
static int postfix_dec(int a)      { return a--; }

int main(void) {
    volatile int r;
    r = bit_and(0xFF, 0x0F);
    r = bit_or(0xF0, 0x0F);
    r = bit_xor(0xFF, 0x0F);
    r = bit_not(0xAAAAAAAA);
    r = shift_left(5);
    r = shift_right_unsigned(0xFFFFFFF8u);
    r = shift_right_signed(0xFFFFFFF8);
    r = prefix_inc(10);    /* r = 11, a = 11 */
    r = postfix_inc(10);   /* r = 10, a = 11 */
    return 0;
}
```
## bit_and
``` c
static int bit_and(int a, int b)   { return a & b; }
```
``` asm
00000090 <bit_and>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6039            str     r1, [r7, #0]
  9a:   687a            ldr     r2, [r7, #4]
  9c:   683b            ldr     r3, [r7, #0]
  9e:   4013            ands    r3, r2      ; key logic
  a0:   4618            mov     r0, r3
  a2:   370c            adds    r7, #12
  a4:   46bd            mov     sp, r7
  a6:   bc80            pop     {r7}
  a8:   4770            bx      lr
```
所以这里和add 没有本质区别，仅仅是用了ands
## bit_or
``` c
static int bit_or(int a, int b)    { return a | b; }
```
``` asm
000000aa <bit_or>:
  aa:   b480            push    {r7}
  ac:   b083            sub     sp, #12
  ae:   af00            add     r7, sp, #0
  b0:   6078            str     r0, [r7, #4]
  b2:   6039            str     r1, [r7, #0]
  b4:   687a            ldr     r2, [r7, #4]
  b6:   683b            ldr     r3, [r7, #0]
  b8:   4313            orrs    r3, r2
  ba:   4618            mov     r0, r3
  bc:   370c            adds    r7, #12
  be:   46bd            mov     sp, r7
  c0:   bc80            pop     {r7}
  c2:   4770            bx      lr
```
同样没有本质区别，将ands换成orrs
## bit_xor
``` c
static int bit_xor(int a, int b)   { return a ^ b; }
```
``` asm
000000c4 <bit_xor>:
  c4:   b480            push    {r7}
  c6:   b083            sub     sp, #12
  c8:   af00            add     r7, sp, #0
  ca:   6078            str     r0, [r7, #4]
  cc:   6039            str     r1, [r7, #0]
  ce:   687a            ldr     r2, [r7, #4]
  d0:   683b            ldr     r3, [r7, #0]
  d2:   4053            eors    r3, r2
  d4:   4618            mov     r0, r3
  d6:   370c            adds    r7, #12
  d8:   46bd            mov     sp, r7
  da:   bc80            pop     {r7}
  dc:   4770            bx      lr
```
同样没有本质区别，将ands换成eors。
## bit_not
``` c
static int bit_not(int a)          { return ~a; }
```
``` asm
000000de <bit_not>:
  de:   b480            push    {r7}
  e0:   b083            sub     sp, #12
  e2:   af00            add     r7, sp, #0
  e4:   6078            str     r0, [r7, #4]
  e6:   687b            ldr     r3, [r7, #4]
  e8:   43db            mvns    r3, r3
  ea:   4618            mov     r0, r3
  ec:   370c            adds    r7, #12
  ee:   46bd            mov     sp, r7
  f0:   bc80            pop     {r7}
  f2:   4770            bx      lr
```
同样没有本质区别，将ands换成mvns。
## shift_left
``` c
static int shift_left(int a)       { return a << 3; }
```
``` asm
000000f4 <shift_left>:
  f4:   b480            push    {r7}
  f6:   b083            sub     sp, #12
  f8:   af00            add     r7, sp, #0
  fa:   6078            str     r0, [r7, #4]
  fc:   687b            ldr     r3, [r7, #4]
  fe:   00db            lsls    r3, r3, #3
 100:   4618            mov     r0, r3
 102:   370c            adds    r7, #12
 104:   46bd            mov     sp, r7
 106:   bc80            pop     {r7}
 108:   4770            bx      lr
```
同样没有本质区别，将ands换成lsls。
## shift_right_unsigned
``` c
static int shift_right_unsigned(unsigned int a) { return a >> 3; }
```
``` asm
0000010a <shift_right_unsigned>:
 10a:   b480            push    {r7}
 10c:   b083            sub     sp, #12
 10e:   af00            add     r7, sp, #0
 110:   6078            str     r0, [r7, #4]
 112:   687b            ldr     r3, [r7, #4]
 114:   08db            lsrs    r3, r3, #3
 116:   4618            mov     r0, r3
 118:   370c            adds    r7, #12
 11a:   46bd            mov     sp, r7
 11c:   bc80            pop     {r7}
 11e:   4770            bx      lr
```
同样没有本质区别，将ands换成lsrs。
## shift_right_signed
``` c
static int shift_right_signed(int a)           { return a >> 3; }
```
``` asm
00000120 <shift_right_signed>:
 120:   b480            push    {r7}
 122:   b083            sub     sp, #12
 124:   af00            add     r7, sp, #0
 126:   6078            str     r0, [r7, #4]
 128:   687b            ldr     r3, [r7, #4]
 12a:   10db            asrs    r3, r3, #3
 12c:   4618            mov     r0, r3
 12e:   370c            adds    r7, #12
 130:   46bd            mov     sp, r7
 132:   bc80            pop     {r7}
 134:   4770            bx      lr
```
同样没有本质区别，将ands换成asrs。
## prefix_inc
``` c
static int prefix_inc(int a)       { return ++a; }
```
``` asm
00000136 <prefix_inc>:
 136:   b480            push    {r7}
 138:   b083            sub     sp, #12
 13a:   af00            add     r7, sp, #0
 13c:   6078            str     r0, [r7, #4]
 13e:   687b            ldr     r3, [r7, #4]
 140:   3301            adds    r3, #1
 142:   607b            str     r3, [r7, #4]
 144:   687b            ldr     r3, [r7, #4]
 146:   4618            mov     r0, r3
 148:   370c            adds    r7, #12
 14a:   46bd            mov     sp, r7
 14c:   bc80            pop     {r7}
 14e:   4770            bx      lr
```
和add没啥区别。
## postfix_inc
``` c
static int postfix_inc(int a)      { return a++; }
```
``` asm
00000150 <postfix_inc>:
 150:   b480            push    {r7}
 152:   b083            sub     sp, #12
 154:   af00            add     r7, sp, #0
 156:   6078            str     r0, [r7, #4]
 158:   687b            ldr     r3, [r7, #4]
 15a:   1c5a            adds    r2, r3, #1
 15c:   607a            str     r2, [r7, #4]
 15e:   4618            mov     r0, r3
 160:   370c            adds    r7, #12
 162:   46bd            mov     sp, r7
 164:   bc80            pop     {r7}
 166:   4770            bx      lr
```
这里主要注意，adds 的结果是存在R2的，但是返回值是从R3 mov过去的。
## prefix_dec
与prefix_inc 类似。
## postfix_dec
与postfix_inc 类似。
# 不同长度的数据类型
``` c
/*
 * 观察目标: 不同数据类型的运算差异; 隐式类型转换
 *
 * 编译: make 03-types.elf
 * 反汇编: arm-none-eabi-objdump -d 03-types.elf
 *
 * 关注点:
 *   1. int8 / int16 / int32 的运算——注意 SXTB / SXTH 符号扩展
 *   2. int64 运算拆成两条指令 (低32位 + 高32位)
 *   3. 隐式类型转换: 小类型 → 大类型时插入符号扩展指令
 *   4. 有符号 → 无符号转换: 符号扩展 vs 零扩展
 */

#include <stdint.h>

static int32_t add32(int32_t a, int32_t b)   { return a + b; }
static int16_t add16(int16_t a, int16_t b)   { return a + b; }
static int8_t  add8(int8_t a, int8_t b)      { return a + b; }

static int64_t add64(int64_t a, int64_t b)   { return a + b; }
static int32_t widen(int8_t a, int16_t b)    { return a + b; }

int main(void) {
    volatile int32_t r32;
    volatile int16_t r16;
    volatile int8_t  r8;
    volatile int64_t r64;

    r32 = add32(100, 200);
    r16 = add16(30000, 30000);
    r8  = add8(100, 100);
    r64 = add64(10000000000LL, 20000000000LL);
    r32 = widen((int8_t)10, (int16_t)20);
    return r32 + r64;
}
```
## 不同类型的加法
``` asm
00000090 <add32>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6039            str     r1, [r7, #0]
  9a:   687a            ldr     r2, [r7, #4]
  9c:   683b            ldr     r3, [r7, #0]
  9e:   4413            add     r3, r2
  a0:   4618            mov     r0, r3
  a2:   370c            adds    r7, #12
  a4:   46bd            mov     sp, r7
  a6:   bc80            pop     {r7}
  a8:   4770            bx      lr
```
这里代码的核心其实就是`add     r3, r2` 和 `mov     r0, r3` 。
``` asm
000000aa <add16>:
  aa:   b480            push    {r7}
  ac:   b083            sub     sp, #12
  ae:   af00            add     r7, sp, #0
  b0:   4603            mov     r3, r0
  b2:   460a            mov     r2, r1
  b4:   80fb            strh    r3, [r7, #6]
  b6:   4613            mov     r3, r2
  b8:   80bb            strh    r3, [r7, #4]
  ba:   88fa            ldrh    r2, [r7, #6]
  bc:   88bb            ldrh    r3, [r7, #4]
  be:   4413            add     r3, r2
  c0:   b29b            uxth    r3, r3
  c2:   b21b            sxth    r3, r3
  c4:   4618            mov     r0, r3
  c6:   370c            adds    r7, #12
  c8:   46bd            mov     sp, r7
  ca:   bc80            pop     {r7}
  cc:   4770            bx      lr
```
这里相比较于add32明显的差异在于，用了strh和ldrh，表示操作16位的数据。而uxth 和 sxth分别表示无符号和有符号的展开半字为字。而这里uxth其实是多余的——sxth本身就做了"截断 + 符号扩展"。-O0下GCC会生成冗余指令，开-O1的话其实就会消失了。
``` asm
000000ce <add8>:
  ce:   b480            push    {r7}
  d0:   b083            sub     sp, #12
  d2:   af00            add     r7, sp, #0
  d4:   4603            mov     r3, r0
  d6:   460a            mov     r2, r1
  d8:   71fb            strb    r3, [r7, #7]
  da:   4613            mov     r3, r2
  dc:   71bb            strb    r3, [r7, #6]
  de:   79fa            ldrb    r2, [r7, #7]
  e0:   79bb            ldrb    r3, [r7, #6]
  e2:   4413            add     r3, r2
  e4:   b2db            uxtb    r3, r3
  e6:   b25b            sxtb    r3, r3
  e8:   4618            mov     r0, r3
  ea:   370c            adds    r7, #12
  ec:   46bd            mov     sp, r7
  ee:   bc80            pop     {r7}
  f0:   4770            bx      lr
```
相比于add16，主要就是将strh、ldrh、uxth、sxth换成了strb、ldrb、uxtb、sxtb 用于表达对数据宽度8的处理，其他都一致。
``` asm
000000f2 <add64>:
  f2:   b4b0            push    {r4, r5, r7}
  f4:   b085            sub     sp, #20
  f6:   af00            add     r7, sp, #0
  f8:   e9c7 0102       strd    r0, r1, [r7, #8]
  fc:   e9c7 2300       strd    r2, r3, [r7]
 100:   e9d7 0102       ldrd    r0, r1, [r7, #8]
 104:   e9d7 2300       ldrd    r2, r3, [r7]
 108:   1884            adds    r4, r0, r2
 10a:   eb41 0503       adc.w   r5, r1, r3
 10e:   4622            mov     r2, r4
 110:   462b            mov     r3, r5
 112:   4610            mov     r0, r2
 114:   4619            mov     r1, r3
 116:   3714            adds    r7, #20
 118:   46bd            mov     sp, r7
 11a:   bcb0            pop     {r4, r5, r7}
 11c:   4770            bx      lr
```
这里add64其实也是类似的，主要是将strd、ldrd 来表示对双字数据的操作。然后除了adds，还用了一个adc.w 一起完成双字的加法。
## 隐式类型转换
``` asm
0000011e <widen>:
 11e:   b480            push    {r7}
 120:   b083            sub     sp, #12
 122:   af00            add     r7, sp, #0
 124:   4603            mov     r3, r0
 126:   460a            mov     r2, r1
 128:   71fb            strb    r3, [r7, #7]
 12a:   4613            mov     r3, r2
 12c:   80bb            strh    r3, [r7, #4]
 12e:   f997 2007       ldrsb.w r2, [r7, #7]
 132:   f9b7 3004       ldrsh.w r3, [r7, #4]
 136:   4413            add     r3, r2
 138:   4618            mov     r0, r3
 13a:   370c            adds    r7, #12
 13c:   46bd            mov     sp, r7
 13e:   bc80            pop     {r7}
 140:   4770            bx      lr
```
这里主要看到有差异的是ldrsb与ldrsh，寄存器寻址的同时做符号数的展开，其他的流程基本是一致的。
# if/else
``` c
/*
 * 观察目标: if/else if/else, 条件运算符 ?:
 *
 * 编译: make 04-if.elf
 * 反汇编: arm-none-eabi-objdump -d 04-if.elf
 *
 * 关注点:
 *   1. CMP 比较后接 Bcc (BNE/BEQ/BGT/BLT/BGE/BLE) 构成分支
 *   2. IT (If-Then) 块: 当条件分支体很小时, 编译器用 IT 避免跳转
 *   3. 三元运算符 ?: 在 -O0 下也是分支, 在 -O1 下可能变成 IT
 *   4. 多层嵌套 if 对应的跳转链
 */

static int simple_if(int a) {
    if (a > 0)
        return 1;
    return -1;
}

static int if_else(int a) {
    if (a >= 0)
        return 1;
    else
        return -1;
}

static int if_elif_else(int a) {
    if (a > 0)
        return 10;
    else if (a == 0)
        return 0;
    else
        return -10;
}

static int ternary(int a) {
    return (a > 0) ? 1 : -1;
}

static int nested_if(int a, int b) {
    if (a > 0) {
        if (b > 0)
            return 3;
        return 2;
    }
    return 1;
}

int main(void) {
    volatile int r;
    r = simple_if(5);
    r = if_else(-3);
    r = if_elif_else(0);
    r = ternary(42);
    r = nested_if(1, -1);
    return 0;
}
```
## 简单if
``` asm
00000090 <simple_if>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   687b            ldr     r3, [r7, #4]
  9a:   2b00            cmp     r3, #0
  9c:   dd01            ble.n   a2 <simple_if+0x12>
  9e:   2301            movs    r3, #1
  a0:   e001            b.n     a6 <simple_if+0x16>
  a2:   f04f 33ff       mov.w   r3, #4294967295 @ 0xffffffff
  a6:   4618            mov     r0, r3
  a8:   370c            adds    r7, #12
  aa:   46bd            mov     sp, r7
  ac:   bc80            pop     {r7}
  ae:   4770            bx      lr
```
其实顺序看下来也是比较清晰的，`cmp     r3, #0` 然后有两个路径分叉，要么直接`ble.n   a2 <simple_if+0x12>`，或者就是`movs    r3, #1`之后`b.n     a6 <simple_if+0x16>`，对应C代码是非常清晰的。

## if/else
``` asm
000000b0 <if_else>:
  b0:   b480            push    {r7}
  b2:   b083            sub     sp, #12
  b4:   af00            add     r7, sp, #0
  b6:   6078            str     r0, [r7, #4]
  b8:   687b            ldr     r3, [r7, #4]
  ba:   2b00            cmp     r3, #0
  bc:   db01            blt.n   c2 <if_else+0x12>
  be:   2301            movs    r3, #1
  c0:   e001            b.n     c6 <if_else+0x16>
  c2:   f04f 33ff       mov.w   r3, #4294967295 @ 0xffffffff
  c6:   4618            mov     r0, r3
  c8:   370c            adds    r7, #12
  ca:   46bd            mov     sp, r7
  cc:   bc80            pop     {r7}
  ce:   4770            bx      lr
```
和前面简单if没有本质区别。

## if_elif_else
``` asm
000000d0 <if_elif_else>:
  d0:   b480            push    {r7}
  d2:   b083            sub     sp, #12
  d4:   af00            add     r7, sp, #0
  d6:   6078            str     r0, [r7, #4]
  d8:   687b            ldr     r3, [r7, #4]
  da:   2b00            cmp     r3, #0
  dc:   dd01            ble.n   e2 <if_elif_else+0x12>
  de:   230a            movs    r3, #10
  e0:   e006            b.n     f0 <if_elif_else+0x20>
  e2:   687b            ldr     r3, [r7, #4]
  e4:   2b00            cmp     r3, #0
  e6:   d101            bne.n   ec <if_elif_else+0x1c>
  e8:   2300            movs    r3, #0
  ea:   e001            b.n     f0 <if_elif_else+0x20>
  ec:   f06f 0309       mvn.w   r3, #9
  f0:   4618            mov     r0, r3
  f2:   370c            adds    r7, #12
  f4:   46bd            mov     sp, r7
  f6:   bc80            pop     {r7}
  f8:   4770            bx      lr
```
两个if 对应两个cmp，然后用跳转跳到不同的位置。
## 三元运算符 ?
``` asm
000000fa <ternary>:
  fa:   b480            push    {r7}
  fc:   b083            sub     sp, #12
  fe:   af00            add     r7, sp, #0
 100:   6078            str     r0, [r7, #4]
 102:   687b            ldr     r3, [r7, #4]
 104:   2b00            cmp     r3, #0
 106:   dd01            ble.n   10c <ternary+0x12>
 108:   2301            movs    r3, #1
 10a:   e001            b.n     110 <ternary+0x16>
 10c:   f04f 33ff       mov.w   r3, #4294967295 @ 0xffffffff
 110:   4618            mov     r0, r3
 112:   370c            adds    r7, #12
 114:   46bd            mov     sp, r7
 116:   bc80            pop     {r7}
 118:   4770            bx      lr
```
? 本质上和if else 没有区别。

## 嵌套if
``` asm
0000011a <nested_if>:
 11a:   b480            push    {r7}
 11c:   b083            sub     sp, #12
 11e:   af00            add     r7, sp, #0
 120:   6078            str     r0, [r7, #4]
 122:   6039            str     r1, [r7, #0]
 124:   687b            ldr     r3, [r7, #4]
 126:   2b00            cmp     r3, #0
 128:   dd06            ble.n   138 <nested_if+0x1e>
 12a:   683b            ldr     r3, [r7, #0]
 12c:   2b00            cmp     r3, #0
 12e:   dd01            ble.n   134 <nested_if+0x1a>
 130:   2303            movs    r3, #3
 132:   e002            b.n     13a <nested_if+0x20>
 134:   2302            movs    r3, #2
 136:   e000            b.n     13a <nested_if+0x20>
 138:   2301            movs    r3, #1
 13a:   4618            mov     r0, r3
 13c:   370c            adds    r7, #12
 13e:   46bd            mov     sp, r7
 140:   bc80            pop     {r7}
 142:   4770            bx      lr
```
嵌套的if 逐个看其实和单个的没区别。
# switch/case
``` c
/*
 * 观察目标: switch/case 的两种实现策略
 *
 * 编译: make 05-switch.elf
 * 反汇编: arm-none-eabi-objdump -d 05-switch.elf
 *
 * 关注点:
 *   1. 连续值 case (0,1,2,3) → 跳转表 (TBB/TBH)
 *      在反汇编中可见 .rodata 中的地址表 + TBB 指令
 *   2. 稀疏值 case (0,100,500) → 条件比较链
 *      编译器生成一串 CMP + BEQ
 *   3. default 分支总是最后兜底
 */

static int switch_contiguous(int cmd) {
    switch (cmd) {
        case 0:  return 100;
        case 1:  return 200;
        case 2:  return 300;
        case 3:  return 400;
        default: return -1;
    }
}

static int switch_sparse(int cmd) {
    switch (cmd) {
        case 0:    return 10;
        case 100:  return 20;
        case 500:  return 30;
        case 999:  return 40;
        default:   return -1;
    }
}

/* 无 default 的分支 - 编译器会补充空跳转 */
static int switch_no_default(int cmd) {
    switch (cmd) {
        case 0:  return 10;
        case 1:  return 20;
        case 2:  return 30;
    }
    return -1;
}

int main(void) {
    volatile int r;
    r = switch_contiguous(2);
    r = switch_sparse(100);
    r = switch_no_default(42);
    return 0;
}
```
## 连续case
``` asm
00000090 <switch_contiguous>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   687b            ldr     r3, [r7, #4]
  9a:   2b03            cmp     r3, #3
  9c:   d814            bhi.n   c8 <switch_contiguous+0x38>
  9e:   a201            add     r2, pc, #4      @ (adr r2, a4 <switch_contiguous+0x14>)
  a0:   f852 f023       ldr.w   pc, [r2, r3, lsl #2]
  a4:   000000b5        .word   0x000000b5
  a8:   000000b9        .word   0x000000b9
  ac:   000000bd        .word   0x000000bd
  b0:   000000c3        .word   0x000000c3
  b4:   2364            movs    r3, #100        @ 0x64
  b6:   e009            b.n     cc <switch_contiguous+0x3c>
  b8:   23c8            movs    r3, #200        @ 0xc8
  ba:   e007            b.n     cc <switch_contiguous+0x3c>
  bc:   f44f 7396       mov.w   r3, #300        @ 0x12c
  c0:   e004            b.n     cc <switch_contiguous+0x3c>
  c2:   f44f 73c8       mov.w   r3, #400        @ 0x190
  c6:   e001            b.n     cc <switch_contiguous+0x3c>
  c8:   f04f 33ff       mov.w   r3, #4294967295 @ 0xffffffff
  cc:   4618            mov     r0, r3
  ce:   370c            adds    r7, #12
  d0:   46bd            mov     sp, r7
  d2:   bc80            pop     {r7}
  d4:   4770            bx      lr
```
这里其实核心的语句有三处
``` asm
; 1. 范围检查
9a:   cmp    r3, #3           ; if (cmd > 3)
9c:   bhi.n  c8               ; goto default (返回 -1)

; 2. 计算跳转表基址
9e:   add    r2, pc, #4       ; r2 = 0xa4（跳转表地址）
      ; ↑ 这条就是 adr 的等效写法，注释里标的 @ (adr r2, a4)

; 3. 查表跳转
a0:   ldr.w  pc, [r2, r3, lsl #2]  ; pc =  *(r2 + cmd * 4)
```
可以看出来，生成的汇编语句利用了case的连续性，制作了一个通过r2、r3 跳转的pc的场景，这样的话，可以通过一次O(1)的运算，实现不同case的条件分发。
## 稀疏case
``` asm
000000d6 <switch_sparse>:
  d6:   b480            push    {r7}
  d8:   b083            sub     sp, #12
  da:   af00            add     r7, sp, #0
  dc:   6078            str     r0, [r7, #4]
  de:   687b            ldr     r3, [r7, #4]
  e0:   f240 32e7       movw    r2, #999        @ 0x3e7
  e4:   4293            cmp     r3, r2
  e6:   d018            beq.n   11a <switch_sparse+0x44>
  e8:   687b            ldr     r3, [r7, #4]
  ea:   f5b3 7f7a       cmp.w   r3, #1000       @ 0x3e8
  ee:   da16            bge.n   11e <switch_sparse+0x48>
  f0:   687b            ldr     r3, [r7, #4]
  f2:   f5b3 7ffa       cmp.w   r3, #500        @ 0x1f4
  f6:   d00e            beq.n   116 <switch_sparse+0x40>
  f8:   687b            ldr     r3, [r7, #4]
  fa:   f5b3 7ffa       cmp.w   r3, #500        @ 0x1f4
  fe:   dc0e            bgt.n   11e <switch_sparse+0x48>
 100:   687b            ldr     r3, [r7, #4]
 102:   2b00            cmp     r3, #0
 104:   d003            beq.n   10e <switch_sparse+0x38>
 106:   687b            ldr     r3, [r7, #4]
 108:   2b64            cmp     r3, #100        @ 0x64
 10a:   d002            beq.n   112 <switch_sparse+0x3c>
 10c:   e007            b.n     11e <switch_sparse+0x48>
 10e:   230a            movs    r3, #10
 110:   e007            b.n     122 <switch_sparse+0x4c>
 112:   2314            movs    r3, #20
 114:   e005            b.n     122 <switch_sparse+0x4c>
 116:   231e            movs    r3, #30
 118:   e003            b.n     122 <switch_sparse+0x4c>
 11a:   2328            movs    r3, #40 @ 0x28
 11c:   e001            b.n     122 <switch_sparse+0x4c>
 11e:   f04f 33ff       mov.w   r3, #4294967295 @ 0xffffffff
 122:   4618            mov     r0, r3
 124:   370c            adds    r7, #12
 126:   46bd            mov     sp, r7
 128:   bc80            pop     {r7}
 12a:   4770            bx      lr
```
但是对于稀疏的case，就无法利用上述的简化方法，整个switch case结构就退化为多个cmp+跳转了。
## 无default分支
``` asm
0000012c <switch_no_default>:
 12c:   b480            push    {r7}
 12e:   b083            sub     sp, #12
 130:   af00            add     r7, sp, #0
 132:   6078            str     r0, [r7, #4]
 134:   687b            ldr     r3, [r7, #4]
 136:   2b02            cmp     r3, #2
 138:   d00d            beq.n   156 <switch_no_default+0x2a>
 13a:   687b            ldr     r3, [r7, #4]
 13c:   2b02            cmp     r3, #2
 13e:   dc0c            bgt.n   15a <switch_no_default+0x2e>
 140:   687b            ldr     r3, [r7, #4]
 142:   2b00            cmp     r3, #0
 144:   d003            beq.n   14e <switch_no_default+0x22>
 146:   687b            ldr     r3, [r7, #4]
 148:   2b01            cmp     r3, #1
 14a:   d002            beq.n   152 <switch_no_default+0x26>
 14c:   e005            b.n     15a <switch_no_default+0x2e>
 14e:   230a            movs    r3, #10
 150:   e005            b.n     15e <switch_no_default+0x32>
 152:   2314            movs    r3, #20
 154:   e003            b.n     15e <switch_no_default+0x32>
 156:   231e            movs    r3, #30
 158:   e001            b.n     15e <switch_no_default+0x32>
 15a:   f04f 33ff       mov.w   r3, #4294967295 @ 0xffffffff
 15e:   4618            mov     r0, r3
 160:   370c            adds    r7, #12
 162:   46bd            mov     sp, r7
 164:   bc80            pop     {r7}
 166:   4770            bx      lr
```
在缺失default的情景下，编译器没有选择适用跳转表而是用了cmp，这与编译器内部的判断逻辑有关。
无default的分支——编译器会补充隐式default路径，当所有case都不匹配时跳转到返回-1的位置。
# 循环
``` c
/*
 * 观察目标: for / while / do-while 的循环结构
 *
 * 编译: make 06-loop.elf
 * 反汇编: arm-none-eabi-objdump -d 06-loop.elf
 *
 * 关注点:
 *   1. for 的循环底: CMP + Bcc 跳回循环头
 *   2. while 前置判断 vs do-while 后置判断的区别
 *   3. 循环内数组索引: LDR (基址 + 偏移) → 运算 → STR
 *   4. 无限循环: B . (b.n 自身) 或 B <label>
 */

static int for_sum(int n) {
    int sum = 0;
    for (int i = 0; i < n; i++)
        sum += i;
    return sum;
}

static int for_array_sum(int *arr, int len) {
    int sum = 0;
    for (int i = 0; i < len; i++)
        sum += arr[i];
    return sum;
}

static int while_sum(int n) {
    int sum = 0;
    while (n > 0)
        sum += n--;
    return sum;
}

static int do_while_sum(int n) {
    int sum = 0;
    do {
        sum += n--;
    } while (n > 0);
    return sum;
}

static void infinite_loop(void) {
    while (1);
}

int main(void) {
    volatile int r;
    int arr[] = {1, 2, 3, 4, 5};

    r = for_sum(10);
    r = for_array_sum(arr, 5);
    r = while_sum(10);
    r = do_while_sum(10);

    /* infinite_loop will not return, but we also won't reach it */
    return 0;
}
```
## for 循环
``` asm
00000090 <for_sum>:
  90:   b480            push    {r7}
  92:   b085            sub     sp, #20
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   2300            movs    r3, #0
  9a:   60fb            str     r3, [r7, #12]
  9c:   2300            movs    r3, #0
  9e:   60bb            str     r3, [r7, #8]
  a0:   e006            b.n     b0 <for_sum+0x20>
  a2:   68fa            ldr     r2, [r7, #12]
  a4:   68bb            ldr     r3, [r7, #8]
  a6:   4413            add     r3, r2
  a8:   60fb            str     r3, [r7, #12]
  aa:   68bb            ldr     r3, [r7, #8]
  ac:   3301            adds    r3, #1
  ae:   60bb            str     r3, [r7, #8]
  b0:   68ba            ldr     r2, [r7, #8]
  b2:   687b            ldr     r3, [r7, #4]
  b4:   429a            cmp     r2, r3
  b6:   dbf4            blt.n   a2 <for_sum+0x12>
  b8:   68fb            ldr     r3, [r7, #12]
  ba:   4618            mov     r0, r3
  bc:   3714            adds    r7, #20
  be:   46bd            mov     sp, r7
  c0:   bc80            pop     {r7}
  c2:   4770            bx      lr

000000c4 <for_array_sum>:
  c4:   b480            push    {r7}
  c6:   b085            sub     sp, #20
  c8:   af00            add     r7, sp, #0
  ca:   6078            str     r0, [r7, #4]
  cc:   6039            str     r1, [r7, #0]
  ce:   2300            movs    r3, #0
  d0:   60fb            str     r3, [r7, #12]
  d2:   2300            movs    r3, #0
  d4:   60bb            str     r3, [r7, #8]
  d6:   e00a            b.n     ee <for_array_sum+0x2a>
  d8:   68bb            ldr     r3, [r7, #8]
  da:   009b            lsls    r3, r3, #2
  dc:   687a            ldr     r2, [r7, #4]
  de:   4413            add     r3, r2
  e0:   681b            ldr     r3, [r3, #0]
  e2:   68fa            ldr     r2, [r7, #12]
  e4:   4413            add     r3, r2
  e6:   60fb            str     r3, [r7, #12]
  e8:   68bb            ldr     r3, [r7, #8]
  ea:   3301            adds    r3, #1
  ec:   60bb            str     r3, [r7, #8]
  ee:   68ba            ldr     r2, [r7, #8]
  f0:   683b            ldr     r3, [r7, #0]
  f2:   429a            cmp     r2, r3
  f4:   dbf0            blt.n   d8 <for_array_sum+0x14>
  f6:   68fb            ldr     r3, [r7, #12]
  f8:   4618            mov     r0, r3
  fa:   3714            adds    r7, #20
  fc:   46bd            mov     sp, r7
  fe:   bc80            pop     {r7}
 100:   4770            bx      lr
```
主要就是CMP + 跳转组合的逻辑。

## while 循环
``` asm
00000102 <while_sum>:
 102:   b480            push    {r7}
 104:   b085            sub     sp, #20
 106:   af00            add     r7, sp, #0
 108:   6078            str     r0, [r7, #4]
 10a:   2300            movs    r3, #0
 10c:   60fb            str     r3, [r7, #12]
 10e:   e005            b.n     11c <while_sum+0x1a>
 110:   687b            ldr     r3, [r7, #4]
 112:   1e5a            subs    r2, r3, #1
 114:   607a            str     r2, [r7, #4]
 116:   68fa            ldr     r2, [r7, #12]
 118:   4413            add     r3, r2
 11a:   60fb            str     r3, [r7, #12]
 11c:   687b            ldr     r3, [r7, #4]
 11e:   2b00            cmp     r3, #0
 120:   dcf6            bgt.n   110 <while_sum+0xe>
 122:   68fb            ldr     r3, [r7, #12]
 124:   4618            mov     r0, r3
 126:   3714            adds    r7, #20
 128:   46bd            mov     sp, r7
 12a:   bc80            pop     {r7}
 12c:   4770            bx      lr
```
和for 循环形成的结构是类似的。cmp + 跳转。
## do/while 循环
``` asm
0000012e <do_while_sum>:
 12e:   b480            push    {r7}
 130:   b085            sub     sp, #20
 132:   af00            add     r7, sp, #0
 134:   6078            str     r0, [r7, #4]
 136:   2300            movs    r3, #0
 138:   60fb            str     r3, [r7, #12]
 13a:   687b            ldr     r3, [r7, #4]
 13c:   1e5a            subs    r2, r3, #1
 13e:   607a            str     r2, [r7, #4]
 140:   68fa            ldr     r2, [r7, #12]
 142:   4413            add     r3, r2
 144:   60fb            str     r3, [r7, #12]
 146:   687b            ldr     r3, [r7, #4]
 148:   2b00            cmp     r3, #0
 14a:   dcf6            bgt.n   13a <do_while_sum+0xc>
 14c:   68fb            ldr     r3, [r7, #12]
 14e:   4618            mov     r0, r3
 150:   3714            adds    r7, #20
 152:   46bd            mov     sp, r7
 154:   bc80            pop     {r7}
 156:   4770            bx      lr
```
也是类似的。

## 死循环
``` asm
00000158 <infinite_loop>:
 158:   b480            push    {r7}
 15a:   af00            add     r7, sp, #0
 15c:   bf00            nop
 15e:   e7fd            b.n     15c <infinite_loop+0x4>
```
是一个NOP+一个无条件跳转形成的。

其实总的来看，循环逻辑生成的汇编代码是类似的，也比较易读，主要就是通过CMP+跳转来控制程序流。

# break/continue/goto
``` c
/*
 * 观察目标: break / continue / goto 的跳转实现
 *
 * 编译: make 07-break-continue-goto.elf
 * 反汇编: arm-none-eabi-objdump -d 07-break-continue-goto.elf
 *
 * 关注点:
 *   1. break → 无条件跳转 B 跳出循环体 (跳到循环外)
 *   2. continue → B 跳回循环条件判断处
 *   3. goto → B 直接跳到标签地址 (任意跳转)
 *   4. 嵌套循环中 break 只跳出一层
 */

static int break_on_negative(int *arr, int len) {
    int sum = 0;
    for (int i = 0; i < len; i++) {
        if (arr[i] < 0)
            break;
        sum += arr[i];
    }
    return sum;
}

static int skip_negative(int *arr, int len) {
    int sum = 0;
    for (int i = 0; i < len; i++) {
        if (arr[i] < 0)
            continue;
        sum += arr[i];
    }
    return sum;
}

static int goto_early_exit(int *arr, int len) {
    int sum = 0;
    for (int i = 0; i < len; i++) {
        if (arr[i] < 0)
            goto bail;
        sum += arr[i];
    }
bail:
    return sum;
}

int main(void) {
    int data[] = {1, 2, 3, -1, 5};
    volatile int r;
    r = break_on_negative(data, 5);
    r = skip_negative(data, 5);
    r = goto_early_exit(data, 5);
    return 0;
}
```
## break
``` asm
00000090 <break_on_negative>:
  90:   b480            push    {r7}
  92:   b085            sub     sp, #20
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6039            str     r1, [r7, #0]
  9a:   2300            movs    r3, #0
  9c:   60fb            str     r3, [r7, #12]
  9e:   2300            movs    r3, #0
  a0:   60bb            str     r3, [r7, #8]
  a2:   e011            b.n     c8 <break_on_negative+0x38>
  a4:   68bb            ldr     r3, [r7, #8]
  a6:   009b            lsls    r3, r3, #2
  a8:   687a            ldr     r2, [r7, #4]
  aa:   4413            add     r3, r2
  ac:   681b            ldr     r3, [r3, #0]
  ae:   2b00            cmp     r3, #0
  b0:   db0f            blt.n   d2 <break_on_negative+0x42>
  b2:   68bb            ldr     r3, [r7, #8]
  b4:   009b            lsls    r3, r3, #2
  b6:   687a            ldr     r2, [r7, #4]
  b8:   4413            add     r3, r2
  ba:   681b            ldr     r3, [r3, #0]
  bc:   68fa            ldr     r2, [r7, #12]
  be:   4413            add     r3, r2
  c0:   60fb            str     r3, [r7, #12]
  c2:   68bb            ldr     r3, [r7, #8]
  c4:   3301            adds    r3, #1
  c6:   60bb            str     r3, [r7, #8]
  c8:   68ba            ldr     r2, [r7, #8]
  ca:   683b            ldr     r3, [r7, #0]
  cc:   429a            cmp     r2, r3
  ce:   dbe9            blt.n   a4 <break_on_negative+0x14>
  d0:   e000            b.n     d4 <break_on_negative+0x44>
  d2:   bf00            nop
  d4:   68fb            ldr     r3, [r7, #12]
  d6:   4618            mov     r0, r3
  d8:   3714            adds    r7, #20
  da:   46bd            mov     sp, r7
  dc:   bc80            pop     {r7}
  de:   4770            bx      lr
```
其实还是通过CMP+跳转控制程序流。

## continue
``` asm
000000e0 <skip_negative>:
  e0:   b480            push    {r7}
  e2:   b085            sub     sp, #20
  e4:   af00            add     r7, sp, #0
  e6:   6078            str     r0, [r7, #4]
  e8:   6039            str     r1, [r7, #0]
  ea:   2300            movs    r3, #0
  ec:   60fb            str     r3, [r7, #12]
  ee:   2300            movs    r3, #0
  f0:   60bb            str     r3, [r7, #8]
  f2:   e013            b.n     11c <skip_negative+0x3c>
  f4:   68bb            ldr     r3, [r7, #8]
  f6:   009b            lsls    r3, r3, #2
  f8:   687a            ldr     r2, [r7, #4]
  fa:   4413            add     r3, r2
  fc:   681b            ldr     r3, [r3, #0]
  fe:   2b00            cmp     r3, #0
 100:   db08            blt.n   114 <skip_negative+0x34>
 102:   68bb            ldr     r3, [r7, #8]
 104:   009b            lsls    r3, r3, #2
 106:   687a            ldr     r2, [r7, #4]
 108:   4413            add     r3, r2
 10a:   681b            ldr     r3, [r3, #0]
 10c:   68fa            ldr     r2, [r7, #12]
 10e:   4413            add     r3, r2
 110:   60fb            str     r3, [r7, #12]
 112:   e000            b.n     116 <skip_negative+0x36>
 114:   bf00            nop
 116:   68bb            ldr     r3, [r7, #8]
 118:   3301            adds    r3, #1
 11a:   60bb            str     r3, [r7, #8]
 11c:   68ba            ldr     r2, [r7, #8]
 11e:   683b            ldr     r3, [r7, #0]
 120:   429a            cmp     r2, r3
 122:   dbe7            blt.n   f4 <skip_negative+0x14>
 124:   68fb            ldr     r3, [r7, #12]
 126:   4618            mov     r0, r3
 128:   3714            adds    r7, #20
 12a:   46bd            mov     sp, r7
 12c:   bc80            pop     {r7}
 12e:   4770            bx      lr
```
continue 和 break其实是类似的，至少一个往前面跳一个往后面跳。

## goto
``` asm
00000130 <goto_early_exit>:
 130:   b480            push    {r7}
 132:   b085            sub     sp, #20
 134:   af00            add     r7, sp, #0
 136:   6078            str     r0, [r7, #4]
 138:   6039            str     r1, [r7, #0]
 13a:   2300            movs    r3, #0
 13c:   60fb            str     r3, [r7, #12]
 13e:   2300            movs    r3, #0
 140:   60bb            str     r3, [r7, #8]
 142:   e011            b.n     168 <goto_early_exit+0x38>
 144:   68bb            ldr     r3, [r7, #8]
 146:   009b            lsls    r3, r3, #2
 148:   687a            ldr     r2, [r7, #4]
 14a:   4413            add     r3, r2
 14c:   681b            ldr     r3, [r3, #0]
 14e:   2b00            cmp     r3, #0
 150:   db0f            blt.n   172 <goto_early_exit+0x42>
 152:   68bb            ldr     r3, [r7, #8]
 154:   009b            lsls    r3, r3, #2
 156:   687a            ldr     r2, [r7, #4]
 158:   4413            add     r3, r2
 15a:   681b            ldr     r3, [r3, #0]
 15c:   68fa            ldr     r2, [r7, #12]
 15e:   4413            add     r3, r2
 160:   60fb            str     r3, [r7, #12]
 162:   68bb            ldr     r3, [r7, #8]
 164:   3301            adds    r3, #1
 166:   60bb            str     r3, [r7, #8]
 168:   68ba            ldr     r2, [r7, #8]
 16a:   683b            ldr     r3, [r7, #0]
 16c:   429a            cmp     r2, r3
 16e:   dbe9            blt.n   144 <goto_early_exit+0x14>
 170:   e000            b.n     174 <goto_early_exit+0x44>
 172:   bf00            nop
 174:   68fb            ldr     r3, [r7, #12]
 176:   4618            mov     r0, r3
 178:   3714            adds    r7, #20
 17a:   46bd            mov     sp, r7
 17c:   bc80            pop     {r7}
 17e:   4770            bx      lr
```
goto的语义实际上是无条件跳转，这个C的示例不算好，看不太清楚它的作用，汇编的代码实际类似之前的break例子了。
# 短路求值
``` c
/*
 * 观察目标: && 和 || 的短路求值
 *
 * 编译: make 08-logic-short-circuit.elf
 * 反汇编: arm-none-eabi-objdump -d 08-logic-short-circuit.elf
 *
 * 关注点:
 *   1. a && b: 先求值 a, 若 a==0 则跳过 b 的求值 (CMP + BEQ)
 *   2. a || b: 先求值 a, 若 a!=0 则跳过 b 的求值
 *   3. 两个短路操作都没有对第二个表达式无条件求值
 *   4. CBNZ / CBZ 指令: 比较并跳转 (单条指令完成)
 */

static int side_effect_b = 0;

static int get_a(void) {
    return 0;   /* 返回 0 导致 && 短路 */
}

static int get_b(void) {
    side_effect_b++;
    return 1;
}

static int short_circuit_and(void) {
    if (get_a() && get_b())
        return 1;
    return 0;
}

static int short_circuit_or(void) {
    if (get_a() || get_b())
        return 1;
    return 0;
}

static int chain_and_or(int a, int b, int c) {
    if ((a > 0 && b > 0) || c > 0)
        return 1;
    return 0;
}

int main(void) {
    volatile int r;
    r = short_circuit_and();
    r = short_circuit_or();
    r = chain_and_or(1, 0, 1);
    return 0;
}
```
## 短路与
``` asm
000000bc <short_circuit_and>:
  bc:   b580            push    {r7, lr}
  be:   af00            add     r7, sp, #0
  c0:   f7ff ffe6       bl      90 <get_a>
  c4:   4603            mov     r3, r0
  c6:   2b00            cmp     r3, #0
  c8:   d006            beq.n   d8 <short_circuit_and+0x1c>
  ca:   f7ff ffe8       bl      9e <get_b>
  ce:   4603            mov     r3, r0
  d0:   2b00            cmp     r3, #0
  d2:   d001            beq.n   d8 <short_circuit_and+0x1c>
  d4:   2301            movs    r3, #1
  d6:   e000            b.n     da <short_circuit_and+0x1e>
  d8:   2300            movs    r3, #0
  da:   4618            mov     r0, r3
  dc:   bd80            pop     {r7, pc}
```
先调用get_a，然后将返回值也就是R0和0比较，如果相等，直接跳到0返回值，反之才需要调用get_b，这样和我们理解的C语法是一致的。

## 短路或
```asm
000000de <short_circuit_or>:
  de:   b580            push    {r7, lr}
  e0:   af00            add     r7, sp, #0
  e2:   f7ff ffd5       bl      90 <get_a>
  e6:   4603            mov     r3, r0
  e8:   2b00            cmp     r3, #0
  ea:   d104            bne.n   f6 <short_circuit_or+0x18>
  ec:   f7ff ffd7       bl      9e <get_b>
  f0:   4603            mov     r3, r0
  f2:   2b00            cmp     r3, #0
  f4:   d001            beq.n   fa <short_circuit_or+0x1c>
  f6:   2301            movs    r3, #1
  f8:   e000            b.n     fc <short_circuit_or+0x1e>
  fa:   2300            movs    r3, #0
  fc:   4618            mov     r0, r3
  fe:   bd80            pop     {r7, pc} 
```
先调用get_a，然后将返回值也就是R0和0比较，如果不相等，直接跳到1返回值。另一分支才需要调用get_b。
## 组合条件
``` asm
00000100 <chain_and_or>:
 100:   b480            push    {r7}
 102:   b085            sub     sp, #20
 104:   af00            add     r7, sp, #0
 106:   60f8            str     r0, [r7, #12]
 108:   60b9            str     r1, [r7, #8]
 10a:   607a            str     r2, [r7, #4]
 10c:   68fb            ldr     r3, [r7, #12]
 10e:   2b00            cmp     r3, #0
 110:   dd02            ble.n   118 <chain_and_or+0x18>
 112:   68bb            ldr     r3, [r7, #8]
 114:   2b00            cmp     r3, #0
 116:   dc02            bgt.n   11e <chain_and_or+0x1e>
 118:   687b            ldr     r3, [r7, #4]
 11a:   2b00            cmp     r3, #0
 11c:   dd01            ble.n   122 <chain_and_or+0x22>
 11e:   2301            movs    r3, #1
 120:   e000            b.n     124 <chain_and_or+0x24>
 122:   2300            movs    r3, #0
 124:   4618            mov     r0, r3
 126:   3714            adds    r7, #20
 128:   46bd            mov     sp, r7
 12a:   bc80            pop     {r7}
 12c:   4770            bx      lr
```
`if ((a > 0 && b > 0) || c > 0)` 对应到汇编代码里，使用CMP+跳转控制整个程序流。
# 函数调用
## 函数调用基础
``` c
/*
 * 观察目标: 函数调用与返回, LR 寄存器
 *
 * 编译: make 09-call-basics.elf
 * 反汇编: arm-none-eabi-objdump -d 09-call-basics.elf
 *
 * 关注点:
 *   1. BL <target>: 跳转并将返回地址写入 LR
 *   2. PUSH {LR} / POP {PC}: 保存和恢复返回地址
 *   3. LR 在调用链中的变化: main → callee → another
 *   4. 叶子函数 (不调其他函数) 不需要 PUSH LR
 */

static int leaf_add(int a, int b) {
    return a + b;
}

static int non_leaf_double(int x) {
    return leaf_add(x, x);
}

static int non_leaf_triple(int x) {
    int a = leaf_add(x, x);
    int b = leaf_add(x, a);
    return b;
}

static void empty(void) {
    /* 无返回值的空函数 - 观察它的 prologue/epilogue */
}

int main(void) {
    volatile int r;
    r = leaf_add(1, 2);
    r = non_leaf_double(5);
    r = non_leaf_triple(3);
    empty();
    return 0;
}
```
### 叶子函数
``` asm
00000090 <leaf_add>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6039            str     r1, [r7, #0]
  9a:   687a            ldr     r2, [r7, #4]
  9c:   683b            ldr     r3, [r7, #0]
  9e:   4413            add     r3, r2
  a0:   4618            mov     r0, r3
  a2:   370c            adds    r7, #12
  a4:   46bd            mov     sp, r7
  a6:   bc80            pop     {r7}
  a8:   4770            bx      lr
```
叶子函数也就是不调用其它函数的函数，类似于整个调用树的叶子。那这里叶子函数最明显的特征就是lr不需要入栈，因为全程都不会修改lr。
### 非叶子函数
``` asm
000000aa <non_leaf_double>:
  aa:   b580            push    {r7, lr}
  ac:   b082            sub     sp, #8
  ae:   af00            add     r7, sp, #0
  b0:   6078            str     r0, [r7, #4]
  b2:   6879            ldr     r1, [r7, #4]
  b4:   6878            ldr     r0, [r7, #4]
  b6:   f7ff ffeb       bl      90 <leaf_add>
  ba:   4603            mov     r3, r0
  bc:   4618            mov     r0, r3
  be:   3708            adds    r7, #8
  c0:   46bd            mov     sp, r7
  c2:   bd80            pop     {r7, pc}

000000c4 <non_leaf_triple>:
  c4:   b580            push    {r7, lr}
  c6:   b084            sub     sp, #16
  c8:   af00            add     r7, sp, #0
  ca:   6078            str     r0, [r7, #4]
  cc:   6879            ldr     r1, [r7, #4]
  ce:   6878            ldr     r0, [r7, #4]
  d0:   f7ff ffde       bl      90 <leaf_add>
  d4:   60f8            str     r0, [r7, #12]
  d6:   68f9            ldr     r1, [r7, #12]
  d8:   6878            ldr     r0, [r7, #4]
  da:   f7ff ffd9       bl      90 <leaf_add>
  de:   60b8            str     r0, [r7, #8]
  e0:   68bb            ldr     r3, [r7, #8]
  e2:   4618            mov     r0, r3
  e4:   3710            adds    r7, #16
  e6:   46bd            mov     sp, r7
  e8:   bd80            pop     {r7, pc}
```
非叶子函数就明显看到，因为要产生新的调用，所以需要提前将lr入栈。而在业务逻辑跑完之后，只要用一个反向的pop将入栈的lr内容推入pc，就丝滑的完成将控制权还给caller了。

### 空函数
``` asm
000000ea <empty>:
  ea:   b480            push    {r7}
  ec:   af00            add     r7, sp, #0
  ee:   bf00            nop
  f0:   46bd            mov     sp, r7
  f2:   bc80            pop     {r7}
  f4:   4770            bx      lr
```
空函数本身没有业务，但是因为编译器的生成逻辑，这里还是生成了一些套路的话的代码，也挺有意思的，可以一读。

## 多参数调用
``` c
/*
 * 观察目标: 参数个数对传参方式的影响
 *
 * 编译: make 09b-call-many-args.elf
 * 反汇编: arm-none-eabi-objdump -d 09b-call-many-args.elf
 *
 * 关注点:
 *   1. 1~4 个参数: R0-R3 传递, 无栈操作
 *   2. 5+ 个参数: 前 4 个在 R0-R3, 第 5 个起压栈 (PUSH/STR)
 *   3. 大结构体作为返回值: 调用者分配空间, R0 传递隐藏指针
 */

typedef struct { int x, y, z, w; } big_t;

static int args_4(int a, int b, int c, int d) {
    return a + b + c + d;
}

static int args_8(int a, int b, int c, int d,
                  int e, int f, int g, int h) {
    return a + b + c + d + e + f + g + h;
}

static big_t make_big(int a, int b, int c, int d) {
    big_t s = {a, b, c, d};
    return s;
}

int main(void) {
    volatile int r;
    big_t s;

    r = args_4(1, 2, 3, 4);
    r = args_8(1, 2, 3, 4, 5, 6, 7, 8);
    s = make_big(10, 20, 30, 40);
    return r;
}
```
### 4个以内参数
``` asm
00000090 <args_4>:
  90:   b480            push    {r7}
  92:   b085            sub     sp, #20
  94:   af00            add     r7, sp, #0
  96:   60f8            str     r0, [r7, #12]
  98:   60b9            str     r1, [r7, #8]
  9a:   607a            str     r2, [r7, #4]
  9c:   603b            str     r3, [r7, #0]
  9e:   68fa            ldr     r2, [r7, #12]
  a0:   68bb            ldr     r3, [r7, #8]
  a2:   441a            add     r2, r3
  a4:   687b            ldr     r3, [r7, #4]
  a6:   441a            add     r2, r3
  a8:   683b            ldr     r3, [r7, #0]
  aa:   4413            add     r3, r2
  ac:   4618            mov     r0, r3
  ae:   3714            adds    r7, #20
  b0:   46bd            mov     sp, r7
  b2:   bc80            pop     {r7}
  b4:   4770            bx      lr
```
按照AAPCS的约定，少于4个的参数传递是利用R0~R3的。从上面的汇编也能看出来。

### 超过4个参数
``` asm
000000b6 <args_8>:
  b6:   b480            push    {r7}
  b8:   b085            sub     sp, #20
  ba:   af00            add     r7, sp, #0
  bc:   60f8            str     r0, [r7, #12]
  be:   60b9            str     r1, [r7, #8]
  c0:   607a            str     r2, [r7, #4]
  c2:   603b            str     r3, [r7, #0]
  c4:   68fa            ldr     r2, [r7, #12]
  c6:   68bb            ldr     r3, [r7, #8]
  c8:   441a            add     r2, r3
  ca:   687b            ldr     r3, [r7, #4]
  cc:   441a            add     r2, r3
  ce:   683b            ldr     r3, [r7, #0]
  d0:   441a            add     r2, r3
  d2:   69bb            ldr     r3, [r7, #24]
  d4:   441a            add     r2, r3
  d6:   69fb            ldr     r3, [r7, #28]
  d8:   441a            add     r2, r3
  da:   6a3b            ldr     r3, [r7, #32]
  dc:   441a            add     r2, r3
  de:   6a7b            ldr     r3, [r7, #36]   @ 0x24
  e0:   4413            add     r3, r2
  e2:   4618            mov     r0, r3
  e4:   3714            adds    r7, #20
  e6:   46bd            mov     sp, r7
  e8:   bc80            pop     {r7}
  ea:   4770            bx      lr
```
按照AAPCS的约定，超过4个的参数传递前4个是利用R0~R3的，而其余的则是由caller提前放置在栈内的。从上面的汇编也能看出来对其的使用方式。

### 结构体返回值
``` asm
000000ec <make_big>:
  ec:   b490            push    {r4, r7}
  ee:   b088            sub     sp, #32
  f0:   af00            add     r7, sp, #0
  f2:   60f8            str     r0, [r7, #12]
  f4:   60b9            str     r1, [r7, #8]
  f6:   607a            str     r2, [r7, #4]
  f8:   603b            str     r3, [r7, #0]
  fa:   68bb            ldr     r3, [r7, #8]
  fc:   613b            str     r3, [r7, #16]
  fe:   687b            ldr     r3, [r7, #4]
 100:   617b            str     r3, [r7, #20]
 102:   683b            ldr     r3, [r7, #0]
 104:   61bb            str     r3, [r7, #24]
 106:   6abb            ldr     r3, [r7, #40]   @ 0x28
 108:   61fb            str     r3, [r7, #28]
 10a:   68fb            ldr     r3, [r7, #12]
 10c:   461c            mov     r4, r3
 10e:   f107 0310       add.w   r3, r7, #16
 112:   cb0f            ldmia   r3, {r0, r1, r2, r3}
 114:   e884 000f       stmia.w r4, {r0, r1, r2, r3}
 118:   68f8            ldr     r0, [r7, #12]
 11a:   3720            adds    r7, #32
 11c:   46bd            mov     sp, r7
 11e:   bc90            pop     {r4, r7}
 120:   4770            bx      lr
00000122 <main>:
 122:   b580            push    {r7, lr}
 124:   b08a            sub     sp, #40 @ 0x28
 126:   af04            add     r7, sp, #16
 128:   2304            movs    r3, #4
 12a:   2203            movs    r2, #3
 12c:   2102            movs    r1, #2
 12e:   2001            movs    r0, #1
 130:   f7ff ffae       bl      90 <args_4>
 134:   4603            mov     r3, r0
 136:   617b            str     r3, [r7, #20]
 138:   2308            movs    r3, #8
 13a:   9303            str     r3, [sp, #12]
 13c:   2307            movs    r3, #7
 13e:   9302            str     r3, [sp, #8]
 140:   2306            movs    r3, #6
 142:   9301            str     r3, [sp, #4]
 144:   2305            movs    r3, #5
 146:   9300            str     r3, [sp, #0]
 148:   2304            movs    r3, #4
 14a:   2203            movs    r2, #3
 14c:   2102            movs    r1, #2
 14e:   2001            movs    r0, #1
 150:   f7ff ffb1       bl      b6 <args_8>
 154:   4603            mov     r3, r0
 156:   617b            str     r3, [r7, #20]
 158:   1d38            adds    r0, r7, #4
 15a:   2328            movs    r3, #40 @ 0x28
 15c:   9300            str     r3, [sp, #0]
 15e:   231e            movs    r3, #30
 160:   2214            movs    r2, #20
 162:   210a            movs    r1, #10
 164:   f7ff ffc2       bl      ec <make_big>
 168:   697b            ldr     r3, [r7, #20]
 16a:   4618            mov     r0, r3
 16c:   3718            adds    r7, #24
 16e:   46bd            mov     sp, r7
 170:   bd80            pop     {r7, pc} 
```
这里其实要同时看caller和callee的行为。首先对于main函数，它有这样几个关键操作
``` asm
00000122 <main>:
 122:   b580            push    {r7, lr}
 124:   b08a            sub     sp, #40 @ 0x28
 126:   af04            add     r7, sp, #16
 ;;;;;;;;;;
 158:   1d38            adds    r0, r7, #4
 15a:   2328            movs    r3, #40 @ 0x28
 15c:   9300            str     r3, [sp, #0]
 15e:   231e            movs    r3, #30
 160:   2214            movs    r2, #20
 162:   210a            movs    r1, #10
 164:   f7ff ffc2       bl      ec <make_big>
 ;;;;;;;;;;
```
这里其实表达的是，main函数进来的时候移动SP在栈上分配了40个字节的大小，但是R7却设置成SP+16，这样的话堆栈就被分为[SP，SP+16]和[SP+16，SP+40]两个部分。
```
                    高地址
    ┌──────────────────────────┐
    │   caller 的栈帧           │
    ├──────────────────────────┤ ← 入口 SP（%8 == 0）
    │  [saved LR]              │ ← 入口SP-4
    ├──────────────────────────┤
    │  [saved R7]              │ ← 入口SP-8（push 后 SP）
    ├──────────────────────────┤
    │  [volatile r]            │ ← 入口SP-12 = R7+20
    ├──────────────────────────┤
    │  [s.w: 未初始化]         │ ← 入口SP-16 = R7+16
    │  [s.z: 未初始化]         │ ← 入口SP-20 = R7+12
    │  [s.y: 未初始化]         │ ← 入口SP-24 = R7+8
    │  [s.x: 未初始化]         │ ← 入口SP-28 = R7+4
    ├──────────────────────────┤
    │  [未使用/padding]         │ ← 入口SP-32 = R7+0
    ├──────────────────────────┤ ← R7 = SP+16 = 入口SP-32
    │  [栈传参保留区]           │
    │  arg8@SP+12, arg7@SP+8   │ ← 入口SP-36 ~ 入口SP-40
    │  arg6@SP+4,  arg5@SP+0   │ ← 入口SP-44 ~ 入口SP-48
    ├──────────────────────────┤ ← SP = 入口SP-48（%8 == 0）
    │         ...              │
                    低地址
```
结合图可以比较好的看出来，main函数是怎么做堆栈的划分的，SP到SP+16的这16个空间被用来做参数传递了，也就是R0~R3包含不了的参数都丢这里了。然后中间有两块分别用来做临时变量r和s的存储。同时在函数调用之前，将s的地址放到R0里。
而到make_big里，R0携带的地址又通过如下几个关键语句完成了使命。
``` asm
000000ec <make_big>:
  ec:   b490            push    {r4, r7}
  ee:   b088            sub     sp, #32
  f0:   af00            add     r7, sp, #0
  f2:   60f8            str     r0, [r7, #12]
  ;;;;
  10a:   68fb            ldr     r3, [r7, #12]
  10c:   461c            mov     r4, r3
  ;;;;
  114:   e884 000f       stmia.w r4, {r0, r1, r2, r3}
```
# 局部变量的存储
## 局部变量
``` c
/*
 * 观察目标: 局部变量在栈上的分配与回收
 *
 * 编译: make 10-stack-frame.elf
 * 反汇编: arm-none-eabi-objdump -d 10-stack-frame.elf
 * GDB:  make qemu-gdb-10-stack-frame
 *   另一个终端: gdb-multiarch -q -ex "target remote :1234" 10-stack-frame.elf
 *   在 GDB 中: break main; continue; stepi; info registers sp
 *
 * 关注点:
 *   1. SUB SP, SP, #N 分配栈空间 (多个局部变量)
 *   2. ADD SP, SP, #N 回收空间
 *   3. SP 在函数 prologue/epilogue 中的变化
 *   4. 大局部变量 vs 小局部变量的分配方式差异
 *   5. 局部数组完全在栈上
 */

static int many_locals(void) {
    int a = 1, b = 2, c = 3, d = 4;
    int e = 5, f = 6, g = 7, h = 8;
    return a + b + c + d + e + f + g + h;
}

static int local_array(void) {
    int arr[8];
    for (int i = 0; i < 8; i++)
        arr[i] = i * i;
    int sum = 0;
    for (int i = 0; i < 8; i++)
        sum += arr[i];
    return sum;
}

static int deeply_nested(void) {
    int x = 1;
    {
        int y = 2;
        {
            int z = 3;
            x = x + y + z;
        }
    }
    return x;
}

int main(void) {
    volatile int r;
    r = many_locals();
    r = local_array();
    r = deeply_nested();
    return 0;
}
```
### 普通栈变量
``` asm
00000090 <many_locals>:
  90:   b480            push    {r7}
  92:   b089            sub     sp, #36 @ 0x24
  94:   af00            add     r7, sp, #0
  96:   2301            movs    r3, #1
  98:   61fb            str     r3, [r7, #28]
  9a:   2302            movs    r3, #2
  9c:   61bb            str     r3, [r7, #24]
  9e:   2303            movs    r3, #3
  a0:   617b            str     r3, [r7, #20]
  a2:   2304            movs    r3, #4
  a4:   613b            str     r3, [r7, #16]
  a6:   2305            movs    r3, #5
  a8:   60fb            str     r3, [r7, #12]
  aa:   2306            movs    r3, #6
  ac:   60bb            str     r3, [r7, #8]
  ae:   2307            movs    r3, #7
  b0:   607b            str     r3, [r7, #4]
  b2:   2308            movs    r3, #8
  b4:   603b            str     r3, [r7, #0]
  b6:   69fa            ldr     r2, [r7, #28]
  b8:   69bb            ldr     r3, [r7, #24]
  ba:   441a            add     r2, r3
  bc:   697b            ldr     r3, [r7, #20]
  be:   441a            add     r2, r3
  c0:   693b            ldr     r3, [r7, #16]
  c2:   441a            add     r2, r3
  c4:   68fb            ldr     r3, [r7, #12]
  c6:   441a            add     r2, r3
  c8:   68bb            ldr     r3, [r7, #8]
  ca:   441a            add     r2, r3
  cc:   687b            ldr     r3, [r7, #4]
  ce:   441a            add     r2, r3
  d0:   683b            ldr     r3, [r7, #0]
  d2:   4413            add     r3, r2
  d4:   4618            mov     r0, r3
  d6:   3724            adds    r7, #36 @ 0x24
  d8:   46bd            mov     sp, r7
  da:   bc80            pop     {r7}
  dc:   4770            bx      lr
```
可以看出来，这里是通过栈上分配了能放8个数据的空间，`sub     sp, #36 @ 0x24` 然后在函数执行结束后释放掉这些空间`adds    r7, #36 @ 0x24`，对应C语法栈上临时变量的性质，确实是函数结束后自动释放的。
### 数组变量
``` asm
000000de <local_array>:
  de:   b480            push    {r7}
  e0:   b08d            sub     sp, #52 @ 0x34
  e2:   af00            add     r7, sp, #0
  e4:   2300            movs    r3, #0
  e6:   62fb            str     r3, [r7, #44]   @ 0x2c
  e8:   e00b            b.n     102 <local_array+0x24>
  ea:   6afb            ldr     r3, [r7, #44]   @ 0x2c
  ec:   fb03 f203       mul.w   r2, r3, r3
  f0:   6afb            ldr     r3, [r7, #44]   @ 0x2c
  f2:   009b            lsls    r3, r3, #2
  f4:   3330            adds    r3, #48 @ 0x30
  f6:   443b            add     r3, r7
  f8:   f843 2c2c       str.w   r2, [r3, #-44]
  fc:   6afb            ldr     r3, [r7, #44]   @ 0x2c
  fe:   3301            adds    r3, #1
 100:   62fb            str     r3, [r7, #44]   @ 0x2c
 102:   6afb            ldr     r3, [r7, #44]   @ 0x2c
 104:   2b07            cmp     r3, #7
 106:   ddf0            ble.n   ea <local_array+0xc>
 108:   2300            movs    r3, #0
 10a:   62bb            str     r3, [r7, #40]   @ 0x28
 10c:   2300            movs    r3, #0
 10e:   627b            str     r3, [r7, #36]   @ 0x24
 110:   e00b            b.n     12a <local_array+0x4c>
 112:   6a7b            ldr     r3, [r7, #36]   @ 0x24
 114:   009b            lsls    r3, r3, #2
 116:   3330            adds    r3, #48 @ 0x30
 118:   443b            add     r3, r7
 11a:   f853 3c2c       ldr.w   r3, [r3, #-44]
 11e:   6aba            ldr     r2, [r7, #40]   @ 0x28
 120:   4413            add     r3, r2
 122:   62bb            str     r3, [r7, #40]   @ 0x28
 124:   6a7b            ldr     r3, [r7, #36]   @ 0x24
 126:   3301            adds    r3, #1
 128:   627b            str     r3, [r7, #36]   @ 0x24
 12a:   6a7b            ldr     r3, [r7, #36]   @ 0x24
 12c:   2b07            cmp     r3, #7
 12e:   ddf0            ble.n   112 <local_array+0x34>
 130:   6abb            ldr     r3, [r7, #40]   @ 0x28
 132:   4618            mov     r0, r3
 134:   3734            adds    r7, #52 @ 0x34
 136:   46bd            mov     sp, r7
 138:   bc80            pop     {r7}
 13a:   4770            bx      lr
```
```
                    高地址
    ┌──────────────────────┐
    │   caller 的栈帧       │
    ├──────────────────────┤ ← 入口 SP
    │  [saved R7]          │ ← 入口SP-4
    ├──────────────────────┤
    │  [i (第一层循环)]     │ ← R7+44
    │  [sum]               │ ← R7+40
    │  [i (第二层循环)]     │ ← R7+36
    │  [arr[7]]            │ ← R7+32
    │  [arr[6]]            │ ← R7+28
    │  [arr[5]]            │ ← R7+24
    │  [arr[4]]            │ ← R7+20
    │  [arr[3]]            │ ← R7+16
    │  [arr[2]]            │ ← R7+12
    │  [arr[1]]            │ ← R7+8
    │  [arr[0]]            │ ← R7+4
    │  [对齐/padding]      │ ← R7+0
    ├──────────────────────┤ ← SP = R7
    │         ...          │
                    低地址
```
整体的数据布局是类似这样的，然后稍微要注意一点的有，这里算offset 是通过`&arr[index] = &arr[0] + 4(sizeof(int)) * index` 做的，所以会用lsls做移位表达乘法；两个for循环的两个i在C语言里是一回事，但是在GCC -O0把它们分配成两个不同的内存单元了。

### 多层变量
``` asm
0000013c <deeply_nested>:
 13c:   b480            push    {r7}
 13e:   b085            sub     sp, #20
 140:   af00            add     r7, sp, #0
 142:   2301            movs    r3, #1
 144:   60fb            str     r3, [r7, #12]
 146:   2302            movs    r3, #2
 148:   60bb            str     r3, [r7, #8]
 14a:   2303            movs    r3, #3
 14c:   607b            str     r3, [r7, #4]
 14e:   68fa            ldr     r2, [r7, #12]
 150:   68bb            ldr     r3, [r7, #8]
 152:   4413            add     r3, r2
 154:   687a            ldr     r2, [r7, #4]
 156:   4413            add     r3, r2
 158:   60fb            str     r3, [r7, #12]
 15a:   68fb            ldr     r3, [r7, #12]
 15c:   4618            mov     r0, r3
 15e:   3714            adds    r7, #20
 160:   46bd            mov     sp, r7
 162:   bc80            pop     {r7}
 164:   4770            bx      lr
```
其实和没有花括号的没啥区别，至于花括号代表的生命周期的事和这里的栈上数据分配无关。

## 静态变量
``` c
/*
 * 观察目标: 函数内 static 局部变量的存储位置
 *
 * 编译: make 10b-static-local.elf
 * 反汇编: arm-none-eabi-objdump -d 10b-static-local.elf
 * GDB:  make qemu-gdb-10b-static-local
 *
 * 关注点:
 *   1. static 变量不在栈上——在 .data 或 .bss 段 (用 objdump -t 确认)
 *   2. 普通局部变量在栈上, 每次调用重新分配 (SP 偏移)
 *   3. static 变量跨函数调用保持值, 本质就是全局变量
 */

static int counter(void) {
    static int count = 0;
    int local = 0;
    count++;
    local++;
    return count + local;
}

static int accumulate(int x) {
    static int sum = 0;
    sum += x;
    return sum;
}

int main(void) {
    volatile int r;
    r = counter();
    r = counter();
    r = counter();
    r = accumulate(5);
    r = accumulate(10);
    return 0;
}
```
``` asm
00000090 <counter>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   2300            movs    r3, #0
  98:   607b            str     r3, [r7, #4]
  9a:   4b08            ldr     r3, [pc, #32]   @ (bc <counter+0x2c>)
  9c:   681b            ldr     r3, [r3, #0]
  9e:   3301            adds    r3, #1
  a0:   4a06            ldr     r2, [pc, #24]   @ (bc <counter+0x2c>)
  a2:   6013            str     r3, [r2, #0]
  a4:   687b            ldr     r3, [r7, #4]
  a6:   3301            adds    r3, #1
  a8:   607b            str     r3, [r7, #4]
  aa:   4b04            ldr     r3, [pc, #16]   @ (bc <counter+0x2c>)
  ac:   681a            ldr     r2, [r3, #0]
  ae:   687b            ldr     r3, [r7, #4]
  b0:   4413            add     r3, r2
  b2:   4618            mov     r0, r3
  b4:   370c            adds    r7, #12
  b6:   46bd            mov     sp, r7
  b8:   bc80            pop     {r7}
  ba:   4770            bx      lr
  bc:   20000000        .word   0x20000000

000000c0 <accumulate>:
  c0:   b480            push    {r7}
  c2:   b083            sub     sp, #12
  c4:   af00            add     r7, sp, #0
  c6:   6078            str     r0, [r7, #4]
  c8:   4b06            ldr     r3, [pc, #24]   @ (e4 <accumulate+0x24>)
  ca:   681a            ldr     r2, [r3, #0]
  cc:   687b            ldr     r3, [r7, #4]
  ce:   4413            add     r3, r2
  d0:   4a04            ldr     r2, [pc, #16]   @ (e4 <accumulate+0x24>)
  d2:   6013            str     r3, [r2, #0]
  d4:   4b03            ldr     r3, [pc, #12]   @ (e4 <accumulate+0x24>)
  d6:   681b            ldr     r3, [r3, #0]
  d8:   4618            mov     r0, r3
  da:   370c            adds    r7, #12
  dc:   46bd            mov     sp, r7
  de:   bc80            pop     {r7}
  e0:   4770            bx      lr
  e2:   bf00            nop
  e4:   20000004        .word   0x20000004
```
static变量在汇编层就是全局变量。不同于普通局部变量在栈上通过SP/R7偏移访问，们被分配在 .bss/.data 段，通过固定地址访问。
``` bash
$ arm-none-eabi-objdump -t 10b-static-local.elf | grep -E "count|sum"
00000090 l     F .text  00000030 counter
20000000 l       .bss   00000004 count.1
20000004 l       .bss   00000004 sum.0
```
可以看到bss段上分配的数据空间。

# 递归
``` c
/*
 * 观察目标: 递归调用中栈帧的叠加; 尾调用优化
 *
 * 编译: make 11-recursion.elf
 * 反汇编: arm-none-eabi-objdump -d 11-recursion.elf
 * GDB:  make qemu-gdb-11-recursion
 *
 * 关注点:
 *   1. 每次递归调用 PUSH {LR} + SUB SP 分配新栈帧
 *   2. SP 随递归深度递减
 *   3. 从 GDB 看 backtrace: 每层递归的返回地址
 *   4. 尾调用优化: -O2 下 tail_factorial_tco 的 BL → B + 无 push {LR}
 *      对比 tail_factorial (常量参数被消除) 和 tail_factorial_tco (保留)
 */

static int factorial(int n) {
    if (n <= 1)
        return 1;
    return n * factorial(n - 1);
}

static int fibonacci(int n) {
    if (n <= 1)
        return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

/* 尾递归 - 编译器可能优化为循环 */
static int tail_factorial(int n, int acc) {
    if (n <= 1)
        return acc;
    return tail_factorial(n - 1, acc * n);
}

static int gcd(int a, int b) {
    if (b == 0)
        return a;
    return gcd(b, a % b);
}

/* 尾递归演示: noinline 阻止内联, 参数来自 volatile 阻止常量折叠 */
static int __attribute__((noinline)) tail_factorial_tco(int n, int acc) {
    if (n <= 1)
        return acc;
    return tail_factorial_tco(n - 1, acc * n);
}

int main(void) {
    volatile int r;
    volatile int n = 5;
    volatile int init = 1;
    r = factorial(5);
    r = fibonacci(6);
    r = tail_factorial(5, 1);
    r = gcd(12, 8);
    r = tail_factorial_tco(n, init);
    return 0;
}
```
## 典型递归
``` asm
00000090 <factorial>:
  90:   b580            push    {r7, lr}
  92:   b082            sub     sp, #8
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   687b            ldr     r3, [r7, #4]
  9a:   2b01            cmp     r3, #1
  9c:   dc01            bgt.n   a2 <factorial+0x12>
  9e:   2301            movs    r3, #1
  a0:   e008            b.n     b4 <factorial+0x24>
  a2:   687b            ldr     r3, [r7, #4]
  a4:   3b01            subs    r3, #1
  a6:   4618            mov     r0, r3
  a8:   f7ff fff2       bl      90 <factorial>
  ac:   4602            mov     r2, r0
  ae:   687b            ldr     r3, [r7, #4]
  b0:   fb02 f303       mul.w   r3, r2, r3
  b4:   4618            mov     r0, r3
  b6:   3708            adds    r7, #8
  b8:   46bd            mov     sp, r7
  ba:   bd80            pop     {r7, pc}

000000bc <fibonacci>:
  bc:   b590            push    {r4, r7, lr}
  be:   b083            sub     sp, #12
  c0:   af00            add     r7, sp, #0
  c2:   6078            str     r0, [r7, #4]
  c4:   687b            ldr     r3, [r7, #4]
  c6:   2b01            cmp     r3, #1
  c8:   dc01            bgt.n   ce <fibonacci+0x12>
  ca:   687b            ldr     r3, [r7, #4]
  cc:   e00c            b.n     e8 <fibonacci+0x2c>
  ce:   687b            ldr     r3, [r7, #4]
  d0:   3b01            subs    r3, #1
  d2:   4618            mov     r0, r3
  d4:   f7ff fff2       bl      bc <fibonacci>
  d8:   4604            mov     r4, r0
  da:   687b            ldr     r3, [r7, #4]
  dc:   3b02            subs    r3, #2
  de:   4618            mov     r0, r3
  e0:   f7ff ffec       bl      bc <fibonacci>
  e4:   4603            mov     r3, r0
  e6:   4423            add     r3, r4
  e8:   4618            mov     r0, r3
  ea:   370c            adds    r7, #12
  ec:   46bd            mov     sp, r7
  ee:   bd90            pop     {r4, r7, pc}
```
其实还是比较直观的，进来读参数，比较递归的截止条件，然后跳转return或者bl调用。
堆栈增长类似：
```
main 的栈帧:
                    高地址
    ┌───────────────────────────────┐
    │  main 的其余栈空间              │
    ├───────────────────────────────┤ ← main 调用 factorial(3) 时的 SP

factorial(3) 的栈帧:
    ├───────────────────────────────┤
    │  [saved LR: return to main]   │ ← R7+12
    │  [saved R7: main 的 R7]       │ ← R7+8
    │  [n = 3]                      │ ← R7+4
    │  [padding]                    │ ← R7+0
    ├───────────────────────────────┤ ← factorial(3) 的 SP

factorial(2) 的栈帧:
    ├───────────────────────────────┤
    │  [saved LR: return to fact 3] │ ← R7+12
    │  [saved R7: fact3 的 R7]     │ ← R7+8
    │  [n = 2]                      │ ← R7+4
    │  [padding]                    │ ← R7+0
    ├───────────────────────────────┤ ← factorial(2) 的 SP

factorial(1) 的栈帧 (最深):
    ├───────────────────────────────┤
    │  [saved LR: return to fact 2] │ ← R7+12
    │  [saved R7: fact2 的 R7]     │ ← R7+8
    │  [n = 1]                      │ ← R7+4
    │  [padding]                    │ ← R7+0
    ├───────────────────────────────┤ ← factorial(1) 的 SP ← 当前 SP
    │                              │
                    低地址
```
可以看到，随着递归的次数增加，对栈的占用是线性增长的。那如果n非常大，这就会出现朋友们喜闻乐见的爆栈了。
而fibonacci的堆栈增长也有类似的趋势，但是会更多。
## 尾递归
``` asm
000000f0 <tail_factorial>:
  f0:   b580            push    {r7, lr}
  f2:   b082            sub     sp, #8
  f4:   af00            add     r7, sp, #0
  f6:   6078            str     r0, [r7, #4]
  f8:   6039            str     r1, [r7, #0]
  fa:   687b            ldr     r3, [r7, #4]
  fc:   2b01            cmp     r3, #1
  fe:   dc01            bgt.n   104 <tail_factorial+0x14>
 100:   683b            ldr     r3, [r7, #0]
 102:   e009            b.n     118 <tail_factorial+0x28>
 104:   687b            ldr     r3, [r7, #4]
 106:   1e58            subs    r0, r3, #1
 108:   683b            ldr     r3, [r7, #0]
 10a:   687a            ldr     r2, [r7, #4]
 10c:   fb02 f303       mul.w   r3, r2, r3
 110:   4619            mov     r1, r3
 112:   f7ff ffed       bl      f0 <tail_factorial>
 116:   4603            mov     r3, r0
 118:   4618            mov     r0, r3
 11a:   3708            adds    r7, #8
 11c:   46bd            mov     sp, r7
 11e:   bd80            pop     {r7, pc}
```
用makefile默认的O0编译选项来编译，可以看到编译的结果和之前的普通递归没区别。
而使用O2编译选项，可以看到tail_factorial_tco的优化效果（因为直接将O2参数传递给编译器这里可能会报一个startup.c的错，这里偷懒直接看汇编了）
``` bash
arm-none-eabi-gcc -O2 -ffreestanding -mthumb -mcpu=cortex-m3 -S 11-recursion.c -o /tmp/r2.s
grep -A 20 "tail_factorial_tco:" /tmp/r2.s
```
``` asm
tail_factorial_tco:
        @ args = 0, pretend = 0, frame = 0
        @ frame_needed = 0, uses_anonymous_args = 0
        @ link register save eliminated.
        mov     r3, r0
        cmp     r3, #1
        mov     r0, r1
        ble     .L5
.L2:
        mov     r2, r3
        subs    r3, r3, #1
        cmp     r3, #1
        mul     r0, r2, r0
        bne     .L2
.L5:
        bx      lr
        .size   tail_factorial_tco, .-tail_factorial_tco
        .align  1
        .p2align 2,,3
        .syntax unified
        .thumb
```
这里可以看到，最明显的一个特征就是，这里没有用额外的栈，不论N多大，这里所使用的栈的空间是常数的，那就是一个比较美妙的性质了。
一般能够满足尾递归优化的条件就是满足尾调用的形式，就是递归函数f，在最后return的也是一个f的调用，而f的所有中间状态都被作为参数传递进f了。
gcd 也是尾优化的一个典型例子了，与上面类似，不再赘述。
# 函数指针
``` c
/*
 * 观察目标: 函数指针与间接调用
 *
 * 编译: make 12-function-pointer.elf
 * 反汇编: arm-none-eabi-objdump -d 12-function-pointer.elf
 *
 * 关注点:
 *   1. 函数指针调用: 先 LDR 加载地址, 再 BLX (寄存器间接跳转)
 *   2. 直接调用是 BL <label>, 函数指针是 BLX <reg>
 *   3. 回调模式: 将函数指针作为参数传递
 */

typedef int (*op_fn)(int, int);

static int add(int a, int b) { return a + b; }
static int mul(int a, int b) { return a * b; }

static int apply(op_fn op, int a, int b) {
    return op(a, b);
}

int main(void) {
    volatile int r;
    op_fn fn;

    fn = add;
    r = fn(3, 4);

    fn = mul;
    r = fn(3, 4);

    r = apply(add, 10, 20);
    r = apply(mul, 10, 20);
    return 0;
}
```
``` asm
00000090 <add>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6039            str     r1, [r7, #0]
  9a:   687a            ldr     r2, [r7, #4]
  9c:   683b            ldr     r3, [r7, #0]
  9e:   4413            add     r3, r2
  a0:   4618            mov     r0, r3
  a2:   370c            adds    r7, #12
  a4:   46bd            mov     sp, r7
  a6:   bc80            pop     {r7}
  a8:   4770            bx      lr

000000aa <mul>:
  aa:   b480            push    {r7}
  ac:   b083            sub     sp, #12
  ae:   af00            add     r7, sp, #0
  b0:   6078            str     r0, [r7, #4]
  b2:   6039            str     r1, [r7, #0]
  b4:   687b            ldr     r3, [r7, #4]
  b6:   683a            ldr     r2, [r7, #0]
  b8:   fb02 f303       mul.w   r3, r2, r3
  bc:   4618            mov     r0, r3
  be:   370c            adds    r7, #12
  c0:   46bd            mov     sp, r7
  c2:   bc80            pop     {r7}
  c4:   4770            bx      lr

000000c6 <apply>:
  c6:   b580            push    {r7, lr}
  c8:   b084            sub     sp, #16
  ca:   af00            add     r7, sp, #0
  cc:   60f8            str     r0, [r7, #12]
  ce:   60b9            str     r1, [r7, #8]
  d0:   607a            str     r2, [r7, #4]
  d2:   68fb            ldr     r3, [r7, #12]
  d4:   6879            ldr     r1, [r7, #4]
  d6:   68b8            ldr     r0, [r7, #8]
  d8:   4798            blx     r3
  da:   4603            mov     r3, r0
  dc:   4618            mov     r0, r3
  de:   3710            adds    r7, #16
  e0:   46bd            mov     sp, r7
  e2:   bd80            pop     {r7, pc}

000000e4 <main>:
  e4:   b580            push    {r7, lr}
  e6:   b082            sub     sp, #8
  e8:   af00            add     r7, sp, #0
  ea:   4b11            ldr     r3, [pc, #68]   @ (130 <main+0x4c>)
  ec:   607b            str     r3, [r7, #4]
  ee:   687b            ldr     r3, [r7, #4]
  f0:   2104            movs    r1, #4
  f2:   2003            movs    r0, #3
  f4:   4798            blx     r3
  f6:   4603            mov     r3, r0
  f8:   603b            str     r3, [r7, #0]
  fa:   4b0e            ldr     r3, [pc, #56]   @ (134 <main+0x50>)
  fc:   607b            str     r3, [r7, #4]
  fe:   687b            ldr     r3, [r7, #4]
 100:   2104            movs    r1, #4
 102:   2003            movs    r0, #3
 104:   4798            blx     r3
 106:   4603            mov     r3, r0
 108:   603b            str     r3, [r7, #0]
 10a:   2214            movs    r2, #20
 10c:   210a            movs    r1, #10
 10e:   4808            ldr     r0, [pc, #32]   @ (130 <main+0x4c>)
 110:   f7ff ffd9       bl      c6 <apply>
 114:   4603            mov     r3, r0
 116:   603b            str     r3, [r7, #0]
 118:   2214            movs    r2, #20
 11a:   210a            movs    r1, #10
 11c:   4805            ldr     r0, [pc, #20]   @ (134 <main+0x50>)
 11e:   f7ff ffd2       bl      c6 <apply>
 122:   4603            mov     r3, r0
 124:   603b            str     r3, [r7, #0]
 126:   2300            movs    r3, #0
 128:   4618            mov     r0, r3
 12a:   3708            adds    r7, #8
 12c:   46bd            mov     sp, r7
 12e:   bd80            pop     {r7, pc}
 130:   00000091        .word   0x00000091
 134:   000000ab        .word   0x000000ab
```
这里核心的点主要在，`blx     r3` 与`.word   0x00000091` `.word   0x000000ab`。将需要跳转的函数地址提取出来，并且以参数传递进`apply` 然后通过`blx     r3`完成关键一跳。
# 全局变量的存储
``` c
/*
 * 观察目标: 全局变量的存储位置 (段)
 *
 * 编译: make 13-globals.elf
 * 观察:
 *   arm-none-eabi-objdump -t 13-globals.elf | grep -E "init|uninit|zero|const"
 *   arm-none-eabi-objdump -d 13-globals.elf
 *
 * 关注点:
 *   1. 初始化全局变量 → .data 段 (FLASH 中存初始值, 启动时复制到 SRAM)
 *   2. 未初始化 / 零初始化 → .bss 段 (不占 FLASH, 启动时清零)
 *   3. const 全局 → .rodata 段 (只读, 在 FLASH 中)
 *   4. 分段直接对应 Reset_Handler 中的复制/清零循环
 */

int init_val   = 0x12345678;
int zero_val   = 0;
int uninit_val;
const int const_val = 0xAA;

int main(void) {
    volatile int r;
    r = init_val;
    r = zero_val;
    r = uninit_val;
    r = const_val;
    return 0;
}
```
``` bash
arm-none-eabi-objdump -t 13-globals.elf | grep -E "init|uninit|zero|const"
20000000 g     O .data  00000004 init_val
000000c4 g     O .text  00000004 const_val
20000004 g     O .bss   00000004 zero_val
20000008 g     O .bss   00000004 uninit_val
```
可以看出来，未初始化的静态变量都在bss里，而初始化的就在data里，const变量就在text只读段里。
# const 变量存储
``` c
/*
 * 观察目标: 常量与字符串字面量的存储
 *
 * 编译: make 14-const.elf
 * 反汇编: arm-none-eabi-objdump -d 14-const.elf
 * 观察: arm-none-eabi-objdump -s -j .rodata 14-const.elf
 *
 * 关注点:
 *   1. 字符串字面量存储在 .rodata 段 (FLASH 中)
 *   2. 局部 const 变量跟普通局部变量一样在栈上 (编译器不优化时)
 *   3. ADR 指令加载 .rodata 中字面量的地址 (literal pool)
 *   4. 字符串指针 vs 字符数组在汇编上的差异
 */

const char msg[] = "hello";

static int use_string(void) {
    const char *s = "world";
    return s[0] + msg[0];
}

static int local_const(void) {
    const int x = 42;
    return x;
}

int main(void) {
    volatile int r;
    r = use_string();
    r = local_const();
    return 0;
}
```
``` asm
00000090 <use_string>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   4b06            ldr     r3, [pc, #24]   @ (b0 <use_string+0x20>)
  98:   607b            str     r3, [r7, #4]
  9a:   687b            ldr     r3, [r7, #4]
  9c:   781b            ldrb    r3, [r3, #0]
  9e:   461a            mov     r2, r3
  a0:   2368            movs    r3, #104        @ 0x68
  a2:   4413            add     r3, r2
  a4:   4618            mov     r0, r3
  a6:   370c            adds    r7, #12
  a8:   46bd            mov     sp, r7
  aa:   bc80            pop     {r7}
  ac:   4770            bx      lr
  ae:   bf00            nop
  b0:   000000f4        .word   0x000000f4

000000b4 <local_const>:
  b4:   b480            push    {r7}
  b6:   b083            sub     sp, #12
  b8:   af00            add     r7, sp, #0
  ba:   232a            movs    r3, #42 @ 0x2a
  bc:   607b            str     r3, [r7, #4]
  be:   687b            ldr     r3, [r7, #4]
  c0:   4618            mov     r0, r3
  c2:   370c            adds    r7, #12
  c4:   46bd            mov     sp, r7
  c6:   bc80            pop     {r7}
  c8:   4770            bx      lr

000000ca <main>:
  ca:   b580            push    {r7, lr}
  cc:   b082            sub     sp, #8
  ce:   af00            add     r7, sp, #0
  d0:   f7ff ffde       bl      90 <use_string>
  d4:   4603            mov     r3, r0
  d6:   607b            str     r3, [r7, #4]
  d8:   f7ff ffec       bl      b4 <local_const>
  dc:   4603            mov     r3, r0
  de:   607b            str     r3, [r7, #4]
  e0:   2300            movs    r3, #0
  e2:   4618            mov     r0, r3
  e4:   3708            adds    r7, #8
  e6:   46bd            mov     sp, r7
  e8:   bd80            pop     {r7, pc}
  ea:   bf00            nop

000000ec <msg>:
  ec:   6568 6c6c 006f 0000 6f77 6c72 0064          hello...world.
```
可以看出来，msg在.rodata（FLASH），而x不存在于任何数据段在-O0下它像普通局部变量一样走栈，但因为值小，编译器直接嵌到指令里了（movs r3, #42），连栈都没用。
字面量地址加载："world" 的地址 0xf4是通过literal pool（ldr r3, [pc, #24]）拿到的，不是直接嵌入指令——因为地址值大，16 位指令编码放不下。
# 指针
``` c
/*
 * 观察目标: 指针操作 vs 数组下标
 *
 * 编译: make 15-pointer.elf
 * 反汇编: arm-none-eabi-objdump -d 15-pointer.elf
 *
 * 关注点:
 *   1. arr[i] 和 *(arr + i) 生成完全相同的指令: LDR R0, [base, i, LSL #2]
 *   2. 指针 ++ 实际加 sizeof(*p) 字节: ADDS ptr, #4 (int*)
 *   3. 数组名传参退化为指针: 函数内无法知道数组长度
 *   4. 多级指针: **ptr → LDR 再 LDR
 */

static int array_index(int *arr, int i) {
    return arr[i];
}

static int pointer_offset(int *arr, int i) {
    return *(arr + i);
}

static int pointer_inc(int *p) {
    int a = *p;
    p++;
    int b = *p;
    return a + b;
}

static int pointer_to_pointer(int **pp, int i) {
    int *p = pp[i];
    return p[0] + p[1];
}

int main(void) {
    int data[] = {10, 20, 30, 40};
    int *ptr = data;
    volatile int r;
    r = array_index(data, 2);
    r = pointer_offset(data, 2);
    r = pointer_inc(ptr);
    r = pointer_to_pointer(&ptr, 0);
    return 0;
}
```
## 指针与数组
``` asm
00000090 <array_index>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6039            str     r1, [r7, #0]
  9a:   683b            ldr     r3, [r7, #0]
  9c:   009b            lsls    r3, r3, #2
  9e:   687a            ldr     r2, [r7, #4]
  a0:   4413            add     r3, r2
  a2:   681b            ldr     r3, [r3, #0]
  a4:   4618            mov     r0, r3
  a6:   370c            adds    r7, #12
  a8:   46bd            mov     sp, r7
  aa:   bc80            pop     {r7}
  ac:   4770            bx      lr

000000ae <pointer_offset>:
  ae:   b480            push    {r7}
  b0:   b083            sub     sp, #12
  b2:   af00            add     r7, sp, #0
  b4:   6078            str     r0, [r7, #4]
  b6:   6039            str     r1, [r7, #0]
  b8:   683b            ldr     r3, [r7, #0]
  ba:   009b            lsls    r3, r3, #2
  bc:   687a            ldr     r2, [r7, #4]
  be:   4413            add     r3, r2
  c0:   681b            ldr     r3, [r3, #0]
  c2:   4618            mov     r0, r3
  c4:   370c            adds    r7, #12
  c6:   46bd            mov     sp, r7
  c8:   bc80            pop     {r7}
  ca:   4770            bx      lr
```
可以看出来`arr[i]` 与 `*(arr + i)` 编译出的汇编代码是一模一样的，这当然也跟我们理解的C语言语法是一致的。
## 指针与解引用
``` asm
000000cc <pointer_inc>:
  cc:   b480            push    {r7}
  ce:   b085            sub     sp, #20
  d0:   af00            add     r7, sp, #0
  d2:   6078            str     r0, [r7, #4]
  d4:   687b            ldr     r3, [r7, #4]
  d6:   681b            ldr     r3, [r3, #0]
  d8:   60fb            str     r3, [r7, #12]
  da:   687b            ldr     r3, [r7, #4]
  dc:   3304            adds    r3, #4
  de:   607b            str     r3, [r7, #4]
  e0:   687b            ldr     r3, [r7, #4]
  e2:   681b            ldr     r3, [r3, #0]
  e4:   60bb            str     r3, [r7, #8]
  e6:   68fa            ldr     r2, [r7, #12]
  e8:   68bb            ldr     r3, [r7, #8]
  ea:   4413            add     r3, r2
  ec:   4618            mov     r0, r3
  ee:   3714            adds    r7, #20
  f0:   46bd            mov     sp, r7
  f2:   bc80            pop     {r7}
  f4:   4770            bx      lr
```
这里的有一个ptr 的++，但是实际映射过去是`adds    r3, #4`，因为这里的指针类似是int *，所以++ 移动的size 是4。

## 多级指针
``` asm
000000f6 <pointer_to_pointer>:
  f6:   b480            push    {r7}
  f8:   b085            sub     sp, #20
  fa:   af00            add     r7, sp, #0
  fc:   6078            str     r0, [r7, #4]
  fe:   6039            str     r1, [r7, #0]
 100:   683b            ldr     r3, [r7, #0]
 102:   009b            lsls    r3, r3, #2
 104:   687a            ldr     r2, [r7, #4]
 106:   4413            add     r3, r2
 108:   681b            ldr     r3, [r3, #0]
 10a:   60fb            str     r3, [r7, #12]
 10c:   68fb            ldr     r3, [r7, #12]
 10e:   681a            ldr     r2, [r3, #0]
 110:   68fb            ldr     r3, [r7, #12]
 112:   3304            adds    r3, #4
 114:   681b            ldr     r3, [r3, #0]
 116:   4413            add     r3, r2
 118:   4618            mov     r0, r3
 11a:   3714            adds    r7, #20
 11c:   46bd            mov     sp, r7
 11e:   bc80            pop     {r7}
 120:   4770            bx      lr
```
** 也就是ldr后再ldr，多一层指针就多一次ldr。
# 结构体
``` c
/*
 * 观察目标: 结构体内存布局、对齐与成员访问
 *
 * 编译: make 16-struct.elf
 * 反汇编: arm-none-eabi-objdump -d 16-struct.elf
 *
 * 关注点:
 *   1. 成员访问: STR/LDR with offset (如 STR R0, [R3, #4] 访问第二个成员)
 *   2. 对齐填充: 结构体成员间有 padding 字节
 *   3. 各成员的偏移量可以在反汇编的 offset 中直接读出
 *   4. 结构体赋值通常拆成逐成员 STR
 */

typedef struct {
    char  c;      /* offset 0, size 1 */
    int   i;      /* offset 4 (3 bytes padding), size 4 */
    short s;      /* offset 8, size 2 */
} packed_t;       /* total: 10 + 2 padding = 12 */

typedef struct {
    int   i;      /* offset 0 */
    char  c;      /* offset 4 */
    short s;      /* offset 6 (no padding needed) */
} ordered_t;      /* total: 8 */

static int read_members(packed_t *p) {
    return p->c + p->i + p->s;
}

static ordered_t make_ordered(int i, char c, short s) {
    ordered_t o = {i, c, s};
    return o;
}

int main(void) {
    packed_t p = {'A', 12345, 678};
    ordered_t o;
    volatile int r;

    r = read_members(&p);
    o = make_ordered(1, 'B', 2);
    return r;
}
```
有两个struct，在gdb里使用`ptype /o`，可以看不同struct的offset，可以分别的offset：
```
(gdb) ptype /o packed_t
type = struct {
/*      0      |       1 */    char c;
/* XXX  3-byte hole      */
/*      4      |       4 */    int i;
/*      8      |       2 */    short s;
/* XXX  2-byte padding   */

                               /* total size (bytes):   12 */
                             }
(gdb) ptype /o ordered_t
type = struct {
/*      0      |       4 */    int i;
/*      4      |       1 */    char c;
/* XXX  1-byte hole      */
/*      6      |       2 */    short s;

                               /* total size (bytes):    8 */
                             }
```
这里就能看到，相同的三个元素，在不同的排列顺序下，产生了不同的offset排列，并且sizeof(struct) 也有差异。
## struct 解析
``` asm
00000090 <read_members>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   687b            ldr     r3, [r7, #4]
  9a:   781b            ldrb    r3, [r3, #0]
  9c:   461a            mov     r2, r3
  9e:   687b            ldr     r3, [r7, #4]
  a0:   685b            ldr     r3, [r3, #4]
  a2:   4413            add     r3, r2
  a4:   687a            ldr     r2, [r7, #4]
  a6:   f9b2 2008       ldrsh.w r2, [r2, #8]
  aa:   4413            add     r3, r2
  ac:   4618            mov     r0, r3
  ae:   370c            adds    r7, #12
  b0:   46bd            mov     sp, r7
  b2:   bc80            pop     {r7}
  b4:   4770            bx      lr
```
对比上面解析出来的offset，可以看到`p->c + p->i + p->s`，对struct中每个字段的提取其实就是通过不同的offset 读取的，类似
``` asm
9a:   781b            ldrb    r3, [r3, #0]
a0:   685b            ldr     r3, [r3, #4]
a6:   f9b2 2008       ldrsh.w r2, [r2, #8]
```
## struct对齐的影响
因为struct涉及一个字节对齐的说法，在编译器优化的时候除了考虑最小化内存空间的占用，还要考虑比如说内存的访问效率。比如说对于有的机器，如果数据是4字节对齐的话那数据读取的效率会有很大优势。
所以这里我们就会发现，两个结构体，实际上有效数据长度是一样的，但有可能会编译出不同排布和size的结构体。然后这也指导我们，对于一些性能敏感的struct可以经过一些精细的编排获得数据尺寸和读写性能的平衡。
录make_ordered 汇编代码如下：
``` asm
000000b6 <make_ordered>:
  b6:   b480            push    {r7}
  b8:   b087            sub     sp, #28
  ba:   af00            add     r7, sp, #0
  bc:   60f8            str     r0, [r7, #12]
  be:   60b9            str     r1, [r7, #8]
  c0:   4611            mov     r1, r2
  c2:   461a            mov     r2, r3
  c4:   460b            mov     r3, r1
  c6:   71fb            strb    r3, [r7, #7]
  c8:   4613            mov     r3, r2
  ca:   80bb            strh    r3, [r7, #4]
  cc:   68bb            ldr     r3, [r7, #8]
  ce:   613b            str     r3, [r7, #16]
  d0:   79fb            ldrb    r3, [r7, #7]
  d2:   753b            strb    r3, [r7, #20]
  d4:   88bb            ldrh    r3, [r7, #4]
  d6:   82fb            strh    r3, [r7, #22]
  d8:   68fb            ldr     r3, [r7, #12]
  da:   461a            mov     r2, r3
  dc:   f107 0310       add.w   r3, r7, #16
  e0:   e893 0003       ldmia.w r3, {r0, r1}
  e4:   e882 0003       stmia.w r2, {r0, r1}
  e8:   68f8            ldr     r0, [r7, #12]
  ea:   371c            adds    r7, #28
  ec:   46bd            mov     sp, r7
  ee:   bc80            pop     {r7}
  f0:   4770            bx      lr
```
# memcpy / memset
``` c
/*

 * 观察目标: memcpy / memset 的指令序列 (小尺寸内联 vs 大尺寸库调用)
 *
 * 编译: make 17-memcpy-memset.elf
 * 反汇编: arm-none-eabi-objdump -d 17-memcpy-memset.elf
 *
 * 关注点:
 *   1. 小长度 memcpy (8 字节) → 内联 LDMIA/STMIA
 *   2. 大长度 memcpy (512 字节) → 调用 __aeabi_memcpy 库函数
 *   3. 小长度 memset (16 字节) → 展开为 4 条 STR
 *   4. 大长度 memset (512 字节) → 调用 __aeabi_memset
 *   5. 手写循环 vs 库函数调用的指令密度差异
 */

static int memcpy_small(void) {
    int src[2] = {1, 2};
    int dst[2];
    __builtin_memcpy(dst, src, sizeof(src));
    return dst[0] + dst[1];
}

static int memcpy_large(void) {
    int src[128];
    int dst[128];
    for (int i = 0; i < 128; i++)
        src[i] = i;
    __builtin_memcpy(dst, src, sizeof(src));
    return dst[127];
}

static int memset_small(void) {
    int buf[4];
    __builtin_memset(buf, 0, sizeof(buf));
    return buf[0];
}

static int memset_large(void) {
    int buf[128];
    __builtin_memset(buf, 0, sizeof(buf));
    return buf[0];
}

int main(void) {
    volatile int r;
    r = memcpy_small();
    r = memcpy_large();
    r = memset_small();
    r = memset_large();
    return 0;
```
``` asm
00000090 <memcpy_small>:
  90:   b480            push    {r7}
  92:   b085            sub     sp, #20
  94:   af00            add     r7, sp, #0
  96:   4a0b            ldr     r2, [pc, #44]   @ (c4 <memcpy_small+0x34>)
  98:   f107 0308       add.w   r3, r7, #8
  9c:   e892 0003       ldmia.w r2, {r0, r1}
  a0:   e883 0003       stmia.w r3, {r0, r1}
  a4:   463b            mov     r3, r7
  a6:   f107 0208       add.w   r2, r7, #8
  aa:   e892 0003       ldmia.w r2, {r0, r1}
  ae:   e883 0003       stmia.w r3, {r0, r1}
  b2:   683a            ldr     r2, [r7, #0]
  b4:   687b            ldr     r3, [r7, #4]
  b6:   4413            add     r3, r2
  b8:   4618            mov     r0, r3
  ba:   3714            adds    r7, #20
  bc:   46bd            mov     sp, r7
  be:   bc80            pop     {r7}
  c0:   4770            bx      lr
  c2:   bf00            nop
  c4:   0000033c        .word   0x0000033c

000000c8 <memcpy_large>:
  c8:   b580            push    {r7, lr}
  ca:   f5ad 6d81       sub.w   sp, sp, #1032   @ 0x408
  ce:   af00            add     r7, sp, #0
  d0:   2300            movs    r3, #0
  d2:   f8c7 3404       str.w   r3, [r7, #1028] @ 0x404
  d6:   e00e            b.n     f6 <memcpy_large+0x2e>
  d8:   f507 6381       add.w   r3, r7, #1032   @ 0x408
  dc:   f5a3 7301       sub.w   r3, r3, #516    @ 0x204
  e0:   f8d7 2404       ldr.w   r2, [r7, #1028] @ 0x404
  e4:   f8d7 1404       ldr.w   r1, [r7, #1028] @ 0x404
  e8:   f843 1022       str.w   r1, [r3, r2, lsl #2]
  ec:   f8d7 3404       ldr.w   r3, [r7, #1028] @ 0x404
  f0:   3301            adds    r3, #1
  f2:   f8c7 3404       str.w   r3, [r7, #1028] @ 0x404
  f6:   f8d7 3404       ldr.w   r3, [r7, #1028] @ 0x404
  fa:   2b7f            cmp     r3, #127        @ 0x7f
  fc:   ddec            ble.n   d8 <memcpy_large+0x10>
  fe:   f507 6381       add.w   r3, r7, rgba(3, 3, 3, 0.13)   @ 0x408
 102:   f2a3 4204       subw    r2, r3, #1028   @ 0x404
 106:   f507 6381       add.w   r3, r7, #1032   @ 0x408
 10a:   f5a3 7301       sub.w   r3, r3, #516    @ 0x204
 10e:   4610            mov     r0, r2
 110:   4619            mov     r1, r3
 112:   f44f 7300       mov.w   r3, #512        @ 0x200
 116:   461a            mov     r2, r3
 118:   f000 f84a       bl      1b0 <memcpy>
 11c:   f507 6381       add.w   r3, r7, #1032   @ 0x408
 120:   f2a3 4304       subw    r3, r3, #1028   @ 0x404
 124:   f8d3 31fc       ldr.w   r3, [r3, #508]  @ 0x1fc
 128:   4618            mov     r0, r3
 12a:   f507 6781       add.w   r7, r7, #1032   @ 0x408
 12e:   46bd            mov     sp, r7
 130:   bd80            pop     {r7, pc}

00000132 <memset_small>:
 132:   b480            push    {r7}
 134:   b085            sub     sp, #20
 136:   af00            add     r7, sp, #0
 138:   463b            mov     r3, r7
 13a:   461a            mov     r2, r3
 13c:   2300            movs    r3, #0
 13e:   6013            str     r3, [r2, #0]
 140:   6053            str     r3, [r2, #4]
 142:   6093            str     r3, [r2, #8]
 144:   60d3            str     r3, [r2, #12]
 146:   683b            ldr     r3, [r7, #0]
 148:   4618            mov     r0, r3
 14a:   3714            adds    r7, #20
 14c:   46bd            mov     sp, r7
 14e:   bc80            pop     {r7}
 150:   4770            bx      lr

00000152 <memset_large>:
 152:   b580            push    {r7, lr}
 154:   f5ad 7d00       sub.w   sp, sp, #512    @ 0x200
 158:   af00            add     r7, sp, #0
 15a:   463b            mov     r3, r7
 15c:   4618            mov     r0, r3
 15e:   f44f 7300       mov.w   r3, #512        @ 0x200
 162:   461a            mov     r2, r3
 164:   2100            movs    r1, #0
 166:   f000 f899       bl      29c <memset>
 16a:   f507 7300       add.w   r3, r7, #512    @ 0x200
 16e:   f5a3 7300       sub.w   r3, r3, #512    @ 0x200
 172:   681b            ldr     r3, [r3, #0]
 174:   4618            mov     r0, r3
 176:   f507 7700       add.w   r7, r7, #512    @ 0x200
 17a:   46bd            mov     sp, r7
 17c:   bd80            pop     {r7, pc}
```
这里看到的一个比较好玩的地方是，__builtin_memset 和__builtin_memcpy是编译器内建的操作，对于小尺寸（一般小于64），编译器会直接展开成LDM STR等，而大尺寸的操作才会真的调用memset、memcpy。算是编译器送的免费午餐了。
# malloc / free
``` c
/*
 * 观察目标: malloc/free 的调用序列与堆的位置
 *
 * 编译: make libc-18-malloc.elf
 * 反汇编: arm-none-eabi-objdump -d libc-18-malloc.elf
 *
 * 关注点:
 *   1. malloc 对应 BL __malloc_r (newlib 内部)
 *   2. free  对应 BL _free_r
 *   3. malloc 内部调用 _sbrk 扩展堆 (见 _sbrk.c)
 *   4. 返回的地址在 .bss 之后的堆区域
 *   5. free 后的内存管理 (free list 操作)
 */

#include <stdlib.h>

int main(void) {
    volatile int *p;
    volatile int *q;

    p = malloc(4);
    if (p)
        *p = 42;

    q = malloc(100);
    if (q)
        q[0] = 1;

    free((void *)p);
    free((void *)q);

    return 0;
}
```
``` asm
00000090 <main>:
  90:   b580            push    {r7, lr}
  92:   b082            sub     sp, #8
  94:   af00            add     r7, sp, #0
  96:   2004            movs    r0, #4
  98:   f000 f83c       bl      114 <malloc>
  9c:   4603            mov     r3, r0
  9e:   607b            str     r3, [r7, #4]
  a0:   687b            ldr     r3, [r7, #4]
  a2:   2b00            cmp     r3, #0
  a4:   d002            beq.n   ac <main+0x1c>
  a6:   687b            ldr     r3, [r7, #4]
  a8:   222a            movs    r2, #42 @ 0x2a
  aa:   601a            str     r2, [r3, #0]
  ac:   2064            movs    r0, #100        @ 0x64
  ae:   f000 f831       bl      114 <malloc>
  b2:   4603            mov     r3, r0
  b4:   603b            str     r3, [r7, #0]
  b6:   683b            ldr     r3, [r7, #0]
  b8:   2b00            cmp     r3, #0
  ba:   d002            beq.n   c2 <main+0x32>
  bc:   683b            ldr     r3, [r7, #0]
  be:   2201            movs    r2, #1
  c0:   601a            str     r2, [r3, #0]
  c2:   6878            ldr     r0, [r7, #4]
  c4:   f000 f82e       bl      124 <free>
  c8:   6838            ldr     r0, [r7, #0]
  ca:   f000 f82b       bl      124 <free>
  ce:   2300            movs    r3, #0
  d0:   4618            mov     r0, r3
  d2:   3708            adds    r7, #8
  d4:   46bd            mov     sp, r7
  d6:   bd80            pop     {r7, pc}

000000d8 <_sbrk>:
  d8:   b480            push    {r7}
  da:   b085            sub     sp, #20
  dc:   af00            add     r7, sp, #0
  de:   6078            str     r0, [r7, #4]
  e0:   4b0a            ldr     r3, [pc, #40]   @ (10c <_sbrk+0x34>)
  e2:   681b            ldr     r3, [r3, #0]
  e4:   2b00            cmp     r3, #0
  e6:   d102            bne.n   ee <_sbrk+0x16>
  e8:   4b08            ldr     r3, [pc, #32]   @ (10c <_sbrk+0x34>)
  ea:   4a09            ldr     r2, [pc, #36]   @ (110 <_sbrk+0x38>)
  ec:   601a            str     r2, [r3, #0]
  ee:   4b07            ldr     r3, [pc, #28]   @ (10c <_sbrk+0x34>)
  f0:   681b            ldr     r3, [r3, #0]
  f2:   60fb            str     r3, [r7, #12]
  f4:   4b05            ldr     r3, [pc, #20]   @ (10c <_sbrk+0x34>)
  f6:   681a            ldr     r2, [r3, #0]
  f8:   687b            ldr     r3, [r7, #4]
  fa:   4413            add     r3, r2
  fc:   4a03            ldr     r2, [pc, #12]   @ (10c <_sbrk+0x34>)
  fe:   6013            str     r3, [r2, #0]
 100:   68fb            ldr     r3, [r7, #12]
 102:   4618            mov     r0, r3
 104:   3714            adds    r7, #20
 106:   46bd            mov     sp, r7
 108:   bc80            pop     {r7}
 10a:   4770            bx      lr
 10c:   20000064        .word   0x20000064
 110:   20000074        .word   0x20000074

00000114 <malloc>:
 114:   4b02            ldr     r3, [pc, #8]    @ (120 <malloc+0xc>)
 116:   4601            mov     r1, r0
 118:   6818            ldr     r0, [r3, #0]
 11a:   f000 b869       b.w     1f0 <_malloc_r>
 11e:   bf00            nop
 120:   20000000        .word   0x20000000

00000124 <free>:
 124:   4b02            ldr     r3, [pc, #8]    @ (130 <free+0xc>)
 126:   4601            mov     r1, r0
 128:   6818            ldr     r0, [r3, #0]
 12a:   f000 b803       b.w     134 <_free_r>
 12e:   bf00            nop
 130:   20000000        .word   0x20000000

00000134 <_free_r>:
 134:   2900            cmp     r1, #0
 136:   d050            beq.n   1da <_free_r+0xa6>
 138:   b538            push    {r3, r4, r5, lr}
 13a:   f851 3c04       ldr.w   r3, [r1, #-4]
 13e:   1f0c            subs    r4, r1, #4
 140:   2b00            cmp     r3, #0
 142:   bfb8            it      lt
 144:   18e4            addlt   r4, r4, r3
 146:   4605            mov     r5, r0
 148:   f000 f8be       bl      2c8 <__malloc_lock>
 14c:   4a27            ldr     r2, [pc, #156]  @ (1ec <_free_r+0xb8>)
 14e:   6813            ldr     r3, [r2, #0]
 150:   b12b            cbz     r3, 15e <_free_r+0x2a>
 152:   42a3            cmp     r3, r4
 154:   d90c            bls.n   170 <_free_r+0x3c>
 156:   6821            ldr     r1, [r4, #0]
 158:   1860            adds    r0, r4, r1
 15a:   4283            cmp     r3, r0
 15c:   d02c            beq.n   1b8 <_free_r+0x84>
 15e:   4628            mov     r0, r5
 160:   6063            str     r3, [r4, #4]
 162:   6014            str     r4, [r2, #0]
 164:   e8bd 4038       ldmia.w sp!, {r3, r4, r5, lr}
 168:   f000 b8b0       b.w     2cc <__malloc_unlock>
 16c:   42a3            cmp     r3, r4
 16e:   d80f            bhi.n   190 <_free_r+0x5c>
 170:   461a            mov     r2, r3
 172:   685b            ldr     r3, [r3, #4]
 174:   2b00            cmp     r3, #0
 176:   d1f9            bne.n   16c <_free_r+0x38>
 178:   6811            ldr     r1, [r2, #0]
 17a:   1850            adds    r0, r2, r1
 17c:   4284            cmp     r4, r0
 17e:   d017            beq.n   1b0 <_free_r+0x7c>
 180:   d32c            bcc.n   1dc <_free_r+0xa8>
 182:   6063            str     r3, [r4, #4]
 184:   6054            str     r4, [r2, #4]
 186:   4628            mov     r0, r5
 188:   e8bd 4038       ldmia.w sp!, {r3, r4, r5, lr}
 18c:   f000 b89e       b.w     2cc <__malloc_unlock>
 190:   6811            ldr     r1, [r2, #0]
 192:   1850            adds    r0, r2, r1
 194:   42a0            cmp     r0, r4
 196:   d014            beq.n   1c2 <_free_r+0x8e>
 198:   d820            bhi.n   1dc <_free_r+0xa8>
 19a:   6821            ldr     r1, [r4, #0]
 19c:   1860            adds    r0, r4, r1
 19e:   4283            cmp     r3, r0
 1a0:   d1ef            bne.n   182 <_free_r+0x4e>
 1a2:   6818            ldr     r0, [r3, #0]
 1a4:   685b            ldr     r3, [r3, #4]
 1a6:   4408            add     r0, r1
 1a8:   e9c4 0300       strd    r0, r3, [r4]
 1ac:   6054            str     r4, [r2, #4]
 1ae:   e7ea            b.n     186 <_free_r+0x52>
 1b0:   6823            ldr     r3, [r4, #0]
 1b2:   440b            add     r3, r1
 1b4:   6013            str     r3, [r2, #0]
 1b6:   e7e6            b.n     186 <_free_r+0x52>
 1b8:   6818            ldr     r0, [r3, #0]
 1ba:   685b            ldr     r3, [r3, #4]
 1bc:   4408            add     r0, r1
 1be:   6020            str     r0, [r4, #0]
 1c0:   e7cd            b.n     15e <_free_r+0x2a>
 1c2:   6820            ldr     r0, [r4, #0]
 1c4:   4401            add     r1, r0
 1c6:   1850            adds    r0, r2, r1
 1c8:   4283            cmp     r3, r0
 1ca:   6011            str     r1, [r2, #0]
 1cc:   d1db            bne.n   186 <_free_r+0x52>
 1ce:   e9d3 0400       ldrd    r0, r4, [r3]
 1d2:   4401            add     r1, r0
 1d4:   e9c2 1400       strd    r1, r4, [r2]
 1d8:   e7d5            b.n     186 <_free_r+0x52>
 1da:   4770            bx      lr
 1dc:   230c            movs    r3, #12
 1de:   4628            mov     r0, r5
 1e0:   602b            str     r3, [r5, #0]
 1e2:   e8bd 4038       ldmia.w sp!, {r3, r4, r5, lr}
 1e6:   f000 b871       b.w     2cc <__malloc_unlock>
 1ea:   bf00            nop
 1ec:   20000068        .word   0x20000068

000001f0 <_malloc_r>:
 1f0:   b5f8            push    {r3, r4, r5, r6, r7, lr}
 1f2:   1ccd            adds    r5, r1, #3
 1f4:   f025 0503       bic.w   r5, r5, #3
 1f8:   3508            adds    r5, #8
 1fa:   2d0c            cmp     r5, #12
 1fc:   bf38            it      cc
 1fe:   250c            movcc   r5, #12
 200:   2d00            cmp     r5, #0
 202:   4606            mov     r6, r0
 204:   db15            blt.n   232 <_malloc_r+0x42>
 206:   42a9            cmp     r1, r5
 208:   d813            bhi.n   232 <_malloc_r+0x42>
 20a:   4f25            ldr     r7, [pc, #148]  @ (2a0 <_malloc_r+0xb0>)
 20c:   f000 f85c       bl      2c8 <__malloc_lock>
 210:   683a            ldr     r2, [r7, #0]
 212:   b192            cbz     r2, 23a <_malloc_r+0x4a>
 214:   4614            mov     r4, r2
 216:   e003            b.n     220 <_malloc_r+0x30>
 218:   6863            ldr     r3, [r4, #4]
 21a:   4622            mov     r2, r4
 21c:   b16b            cbz     r3, 23a <_malloc_r+0x4a>
 21e:   461c            mov     r4, r3
 220:   6823            ldr     r3, [r4, #0]
 222:   1b5b            subs    r3, r3, r5
 224:   d4f8            bmi.n   218 <_malloc_r+0x28>
 226:   2b0b            cmp     r3, #11
 228:   d929            bls.n   27e <_malloc_r+0x8e>
 22a:   6023            str     r3, [r4, #0]
 22c:   441c            add     r4, r3
 22e:   6025            str     r5, [r4, #0]
 230:   e018            b.n     264 <_malloc_r+0x74>
 232:   230c            movs    r3, #12
 234:   6033            str     r3, [r6, #0]
 236:   2000            movs    r0, #0
 238:   bdf8            pop     {r3, r4, r5, r6, r7, pc}
 23a:   6879            ldr     r1, [r7, #4]
 23c:   b359            cbz     r1, 296 <_malloc_r+0xa6>
 23e:   4629            mov     r1, r5
 240:   4630            mov     r0, r6
 242:   f000 f82f       bl      2a4 <_sbrk_r>
 246:   1c43            adds    r3, r0, #1
 248:   4601            mov     r1, r0
 24a:   d01e            beq.n   28a <_malloc_r+0x9a>
 24c:   1cc4            adds    r4, r0, #3
 24e:   f024 0403       bic.w   r4, r4, #3
 252:   42a0            cmp     r0, r4
 254:   d005            beq.n   262 <_malloc_r+0x72>
 256:   4630            mov     r0, r6
 258:   1a61            subs    r1, r4, r1
 25a:   f000 f823       bl      2a4 <_sbrk_r>
 25e:   3001            adds    r0, #1
 260:   d013            beq.n   28a <_malloc_r+0x9a>
 262:   6025            str     r5, [r4, #0]
 264:   4630            mov     r0, r6
 266:   f000 f831       bl      2cc <__malloc_unlock>
 26a:   f104 000b       add.w   r0, r4, #11
 26e:   1d23            adds    r3, r4, #4
 270:   f020 0007       bic.w   r0, r0, #7
 274:   1ac2            subs    r2, r0, r3
 276:   bf1c            itt     ne
 278:   1a1b            subne   r3, r3, r0
 27a:   50a3            strne   r3, [r4, r2]
 27c:   bdf8            pop     {r3, r4, r5, r6, r7, pc}
 27e:   6863            ldr     r3, [r4, #4]
 280:   4294            cmp     r4, r2
 282:   bf0c            ite     eq
 284:   603b            streq   r3, [r7, #0]
 286:   6053            strne   r3, [r2, #4]
 288:   e7ec            b.n     264 <_malloc_r+0x74>
 28a:   230c            movs    r3, #12
 28c:   4630            mov     r0, r6
 28e:   6033            str     r3, [r6, #0]
 290:   f000 f81c       bl      2cc <__malloc_unlock>
 294:   e7cf            b.n     236 <_malloc_r+0x46>
 296:   4630            mov     r0, r6
 298:   f000 f804       bl      2a4 <_sbrk_r>
 29c:   6078            str     r0, [r7, #4]
 29e:   e7ce            b.n     23e <_malloc_r+0x4e>
 2a0:   20000068        .word   0x20000068

000002a4 <_sbrk_r>:
 2a4:   2200            movs    r2, #0
 2a6:   b538            push    {r3, r4, r5, lr}
 2a8:   4d06            ldr     r5, [pc, #24]   @ (2c4 <_sbrk_r+0x20>)
 2aa:   4604            mov     r4, r0
 2ac:   4608            mov     r0, r1
 2ae:   602a            str     r2, [r5, #0]
 2b0:   f7ff ff12       bl      d8 <_sbrk>
 2b4:   1c43            adds    r3, r0, #1
 2b6:   d000            beq.n   2ba <_sbrk_r+0x16>
 2b8:   bd38            pop     {r3, r4, r5, pc}
 2ba:   682b            ldr     r3, [r5, #0]
 2bc:   2b00            cmp     r3, #0
 2be:   d0fb            beq.n   2b8 <_sbrk_r+0x14>
 2c0:   6023            str     r3, [r4, #0]
 2c2:   bd38            pop     {r3, r4, r5, pc}
 2c4:   20000070        .word   0x20000070

000002c8 <__malloc_lock>:
 2c8:   4770            bx      lr
 2ca:   bf00            nop

000002cc <__malloc_unlock>:
 2cc:   4770            bx      lr
 2ce:   bf00            nop

000002d0 <cleanup_glue>:
 2d0:   e92d 41f0       stmdb   sp!, {r4, r5, r6, r7, r8, lr}
 2d4:   680e            ldr     r6, [r1, #0]
 2d6:   460c            mov     r4, r1
 2d8:   4605            mov     r5, r0
 2da:   b1be            cbz     r6, 30c <cleanup_glue+0x3c>
 2dc:   6837            ldr     r7, [r6, #0]
 2de:   b18f            cbz     r7, 304 <cleanup_glue+0x34>
 2e0:   f8d7 8000       ldr.w   r8, [r7]
 2e4:   f1b8 0f00       cmp.w   r8, #0
 2e8:   d008            beq.n   2fc <cleanup_glue+0x2c>
 2ea:   f8d8 1000       ldr.w   r1, [r8]
 2ee:   b109            cbz     r1, 2f4 <cleanup_glue+0x24>
 2f0:   f7ff ffee       bl      2d0 <cleanup_glue>
 2f4:   4641            mov     r1, r8
 2f6:   4628            mov     r0, r5
 2f8:   f7ff ff1c       bl      134 <_free_r>
 2fc:   4639            mov     r1, r7
 2fe:   4628            mov     r0, r5
 300:   f7ff ff18       bl      134 <_free_r>
 304:   4631            mov     r1, r6
 306:   4628            mov     r0, r5
 308:   f7ff ff14       bl      134 <_free_r>
 30c:   4621            mov     r1, r4
 30e:   4628            mov     r0, r5
 310:   e8bd 41f0       ldmia.w sp!, {r4, r5, r6, r7, r8, lr}
 314:   f7ff bf0e       b.w     134 <_free_r>

00000318 <_reclaim_reent>:
 318:   4b31            ldr     r3, [pc, #196]  @ (3e0 <_reclaim_reent+0xc8>)
 31a:   681b            ldr     r3, [r3, #0]
 31c:   4283            cmp     r3, r0
 31e:   d059            beq.n   3d4 <_reclaim_reent+0xbc>
 320:   6a42            ldr     r2, [r0, #36]   @ 0x24
 322:   b570            push    {r4, r5, r6, lr}
 324:   4605            mov     r5, r0
 326:   2a00            cmp     r2, #0
 328:   d04f            beq.n   3ca <_reclaim_reent+0xb2>
 32a:   68d1            ldr     r1, [r2, #12]
 32c:   b191            cbz     r1, 354 <_reclaim_reent+0x3c>
 32e:   2600            movs    r6, #0
 330:   598c            ldr     r4, [r1, r6]
 332:   b144            cbz     r4, 346 <_reclaim_reent+0x2e>
 334:   4621            mov     r1, r4
 336:   6824            ldr     r4, [r4, #0]
 338:   4628            mov     r0, r5
 33a:   f7ff fefb       bl      134 <_free_r>
 33e:   2c00            cmp     r4, #0
 340:   d1f8            bne.n   334 <_reclaim_reent+0x1c>
 342:   6a6b            ldr     r3, [r5, #36]   @ 0x24
 344:   68d9            ldr     r1, [r3, #12]
 346:   3604            adds    r6, #4
 348:   2e80            cmp     r6, #128        @ 0x80
 34a:   d1f1            bne.n   330 <_reclaim_reent+0x18>
 34c:   4628            mov     r0, r5
 34e:   f7ff fef1       bl      134 <_free_r>
 352:   6a6a            ldr     r2, [r5, #36]   @ 0x24
 354:   6811            ldr     r1, [r2, #0]
 356:   2900            cmp     r1, #0
 358:   d03d            beq.n   3d6 <_reclaim_reent+0xbe>
 35a:   4628            mov     r0, r5
 35c:   f7ff feea       bl      134 <_free_r>
 360:   6969            ldr     r1, [r5, #20]
 362:   b111            cbz     r1, 36a <_reclaim_reent+0x52>
 364:   4628            mov     r0, r5
 366:   f7ff fee5       bl      134 <_free_r>
 36a:   6a6a            ldr     r2, [r5, #36]   @ 0x24
 36c:   b11a            cbz     r2, 376 <_reclaim_reent+0x5e>
 36e:   4611            mov     r1, r2
 370:   4628            mov     r0, r5
 372:   f7ff fedf       bl      134 <_free_r>
 376:   6ba9            ldr     r1, [r5, #56]   @ 0x38
 378:   b111            cbz     r1, 380 <_reclaim_reent+0x68>
 37a:   4628            mov     r0, r5
 37c:   f7ff feda       bl      134 <_free_r>
 380:   6be9            ldr     r1, [r5, #60]   @ 0x3c
 382:   b111            cbz     r1, 38a <_reclaim_reent+0x72>
 384:   4628            mov     r0, r5
 386:   f7ff fed5       bl      134 <_free_r>
 38a:   6c29            ldr     r1, [r5, #64]   @ 0x40
 38c:   b111            cbz     r1, 394 <_reclaim_reent+0x7c>
 38e:   4628            mov     r0, r5
 390:   f7ff fed0       bl      134 <_free_r>
 394:   6de9            ldr     r1, [r5, #92]   @ 0x5c
 396:   b111            cbz     r1, 39e <_reclaim_reent+0x86>
 398:   4628            mov     r0, r5
 39a:   f7ff fecb       bl      134 <_free_r>
 39e:   6da9            ldr     r1, [r5, #88]   @ 0x58
 3a0:   b111            cbz     r1, 3a8 <_reclaim_reent+0x90>
 3a2:   4628            mov     r0, r5
 3a4:   f7ff fec6       bl      134 <_free_r>
 3a8:   6b69            ldr     r1, [r5, #52]   @ 0x34
 3aa:   b111            cbz     r1, 3b2 <_reclaim_reent+0x9a>
 3ac:   4628            mov     r0, r5
 3ae:   f7ff fec1       bl      134 <_free_r>
 3b2:   69ab            ldr     r3, [r5, #24]
 3b4:   b16b            cbz     r3, 3d2 <_reclaim_reent+0xba>
 3b6:   4628            mov     r0, r5
 3b8:   6aab            ldr     r3, [r5, #40]   @ 0x28
 3ba:   4798            blx     r3
 3bc:   6ca9            ldr     r1, [r5, #72]   @ 0x48
 3be:   b141            cbz     r1, 3d2 <_reclaim_reent+0xba>
 3c0:   4628            mov     r0, r5
 3c2:   e8bd 4070       ldmia.w sp!, {r4, r5, r6, lr}
 3c6:   f7ff bf83       b.w     2d0 <cleanup_glue>
 3ca:   6941            ldr     r1, [r0, #20]
 3cc:   2900            cmp     r1, #0
 3ce:   d1c9            bne.n   364 <_reclaim_reent+0x4c>
 3d0:   e7d1            b.n     376 <_reclaim_reent+0x5e>
 3d2:   bd70            pop     {r4, r5, r6, pc}
 3d4:   4770            bx      lr
 3d6:   6969            ldr     r1, [r5, #20]
 3d8:   2900            cmp     r1, #0
 3da:   d1c3            bne.n   364 <_reclaim_reent+0x4c>
 3dc:   e7c7            b.n     36e <_reclaim_reent+0x56>
 3de:   bf00            nop
 3e0:   20000000        .word   0x20000000

000003e4 <_global_impure_ptr>:
 3e4:   20000004                                ... 
```

```
main
 │
 ├─► malloc (0x114)
 │    │
 │    └─► _malloc_r (0x1f0)
 │         ├── __malloc_lock (0x2c8)    ← 空函数 (单线程, 无竞争)
 │         ├── _sbrk_r (0x2a4)
 │         │    └── _sbrk (0xd8)       ← 我们的 _sbrk.c (移动堆顶指针)
 │         └── __malloc_unlock (0x2cc)  ← 空函数
 │
 ├─► free (0x124)
 │    │
 │    └─► _free_r (0x134)
 │         ├── __malloc_lock
 │         ├── [free list 遍历合并]       ← 找相邻空闲块合并
 │         └── __malloc_unlock
 │
 └── [return]
```
这里看到，malloc会调用_malloc_r，_malloc_r本身是一个可重入的实现，主要就是要加个锁防止重入了。而_malloc_r没有直接调用_sbrk，中间还隔了一层_sbrk_r。而通过_sbrk_r才真实的移动堆指针完成数据空间分配。
# volatile
``` c
/*
 * 观察目标: volatile 阻止编译器优化
 *
 * 编译 (对比):
 *   make 19-volatile.elf                      → -O0, 两版本长得一样
 *   make CFLAGS="-O1" 19-volatile.elf         → -O1 下差异显著
 *
 * 这个实验的核心是 busy_loop 对比:
 *   无 volatile → 循环变量在寄存器里, 无内存操作
 *   有 volatile → 每次读写必须经过内存 (LDR/STR)
 *
 * 注意: 用 CFLAGS="-O1" 时需要用 -mthumb -mcpu=cortex-m3
 *   正确: make CFLAGS="-O1 -mthumb -mcpu=cortex-m3 -ffreestanding" 19-volatile.elf
 *   否则会编出 ARM 指令 (M3 不能用)
 */

/* -O1 下: n 次递减用寄存器完成, 不碰内存 */
static int __attribute__((noinline)) delay_no_volatile(int n) {
    int i;
    for (i = 0; i < n; i++)
        ;
    return i;
}

/* -O1 下: volatile 强制每次迭代 LDR/STR, 无法优化到寄存器 */
static int __attribute__((noinline)) delay_volatile(int n) {
    volatile int i;
    for (i = 0; i < n; i++)
        ;
    return i;
}

int main(void) {
    volatile int r;

    r = delay_no_volatile(100);
    r = delay_volatile(100);
    return 0;
}
```
## 无优化状态
``` asm
00000090 <delay_no_volatile>:
  90:   b480            push    {r7}
  92:   b085            sub     sp, #20
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   2300            movs    r3, #0
  9a:   60fb            str     r3, [r7, #12]
  9c:   e002            b.n     a4 <delay_no_volatile+0x14>
  9e:   68fb            ldr     r3, [r7, #12]
  a0:   3301            adds    r3, #1
  a2:   60fb            str     r3, [r7, #12]
  a4:   68fa            ldr     r2, [r7, #12]
  a6:   687b            ldr     r3, [r7, #4]
  a8:   429a            cmp     r2, r3
  aa:   dbf8            blt.n   9e <delay_no_volatile+0xe>
  ac:   68fb            ldr     r3, [r7, #12]
  ae:   4618            mov     r0, r3
  b0:   3714            adds    r7, #20
  b2:   46bd            mov     sp, r7
  b4:   bc80            pop     {r7}
  b6:   4770            bx      lr

000000b8 <delay_volatile>:
  b8:   b480            push    {r7}
  ba:   b085            sub     sp, #20
  bc:   af00            add     r7, sp, #0
  be:   6078            str     r0, [r7, #4]
  c0:   2300            movs    r3, #0
  c2:   60fb            str     r3, [r7, #12]
  c4:   e002            b.n     cc <delay_volatile+0x14>
  c6:   68fb            ldr     r3, [r7, #12]
  c8:   3301            adds    r3, #1
  ca:   60fb            str     r3, [r7, #12]
  cc:   68fb            ldr     r3, [r7, #12]
  ce:   687a            ldr     r2, [r7, #4]
  d0:   429a            cmp     r2, r3
  d2:   dcf8            bgt.n   c6 <delay_volatile+0xe>
  d4:   68fb            ldr     r3, [r7, #12]
  d6:   4618            mov     r0, r3
  d8:   3714            adds    r7, #20
  da:   46bd            mov     sp, r7
  dc:   bc80            pop     {r7}
  de:   4770            bx      lr
```
在O0状态，也就是不优化的时候，加和不加volatile生成的汇编代码其实是一致的。
## 编译器优化后
``` asm
000000a4 <delay_no_volatile>:
  a4:   2800            cmp     r0, #0
  a6:   dd04            ble.n   b2 <delay_no_volatile+0xe>
  a8:   2300            movs    r3, #0
  aa:   3301            adds    r3, #1
  ac:   4298            cmp     r0, r3
  ae:   d1fc            bne.n   aa <delay_no_volatile+0x6>
  b0:   4770            bx      lr
  b2:   2000            movs    r0, #0
  b4:   4770            bx      lr

000000b6 <delay_volatile>:
  b6:   b082            sub     sp, #8
  b8:   2300            movs    r3, #0
  ba:   9301            str     r3, [sp, #4]
  bc:   9b01            ldr     r3, [sp, #4]
  be:   4298            cmp     r0, r3
  c0:   dd05            ble.n   ce <delay_volatile+0x18>
  c2:   9b01            ldr     r3, [sp, #4]
  c4:   3301            adds    r3, #1
  c6:   9301            str     r3, [sp, #4]
  c8:   9b01            ldr     r3, [sp, #4]
  ca:   4283            cmp     r3, r0
  cc:   dbf9            blt.n   c2 <delay_volatile+0xc>
  ce:   9801            ldr     r0, [sp, #4]
  d0:   b002            add     sp, #8
  d2:   4770            bx      lr
```
而开了O1优化之后，对于没有volatile修饰的变量，编译器对变量的访问就会做简化，它会直接从寄存器那数值而不是ldr → str → ldr。
# LDREX/STREX 原子操作
``` c
 * 反汇编: arm-none-eabi-objdump -d 20-atomic.elf
 *
 * 关注点:
 *   1. LDREX R0, [R1]: 加载 + 标记独占访问
 *   2. STREX R0, R2, [R1]: 条件存储, R0 = 0 成功 / 1 失败
 *   3. 自旋锁: LDREX → CMP → ITE → STREX / MOV
 *   4. CLREX: 清除独占标记
 *   5. 对比普通 STR 和 STREX 的差异
 */

static int atomic_inc(volatile int *p) {
    int new_val, failed;
    do {
        __asm__ __volatile__(
            "ldrex %0, [%2]\n\t"
            "adds  %0, %0, #1\n\t"
            "strex %1, %0, [%2]\n\t"
            : "=&r"(new_val), "=&r"(failed)
            : "r"(p)
            : "memory", "cc"
        );
    } while (failed);
    return new_val;
}

static int normal_inc(volatile int *p) {
    return ++(*p);
}

static int spin_lock(volatile int *lock) {
    int result;
    do {
        __asm__ __volatile__(
            "ldrex %0, [%1]\n\t"
            : "=&r"(result)
            : "r"(lock)
            : "memory"
        );
    } while (result != 0);
    __asm__ __volatile__(
        "strex %0, %1, [%2]\n\t"
        : "=&r"(result)
        : "r"(1), "r"(lock)
        : "memory"
    );
    return result;
}

static void spin_unlock(volatile int *lock) {
    *lock = 0;
}

int main(void) {
    volatile int counter = 0;
    volatile int lock = 0;

    atomic_inc(&counter);
    normal_inc(&counter);
    spin_lock(&lock);
    spin_unlock(&lock);
    return 0;
}
```
##  normal_inc VS atomic_inc
``` asm
00000090 <atomic_inc>:
  90:   b480            push    {r7}
  92:   b085            sub     sp, #20
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6879            ldr     r1, [r7, #4]
  9a:   e851 2f00       ldrex   r2, [r1]
  9e:   3201            adds    r2, #1
  a0:   e841 2300       strex   r3, r2, [r1]
  a4:   60fa            str     r2, [r7, #12]
  a6:   60bb            str     r3, [r7, #8]
  a8:   68bb            ldr     r3, [r7, #8]
  aa:   2b00            cmp     r3, #0
  ac:   d1f4            bne.n   98 <atomic_inc+0x8>
  ae:   68fb            ldr     r3, [r7, #12]
  b0:   4618            mov     r0, r3
  b2:   3714            adds    r7, #20
  b4:   46bd            mov     sp, r7
  b6:   bc80            pop     {r7}
  b8:   4770            bx      lr

000000ba <normal_inc>:
  ba:   b480            push    {r7}
  bc:   b083            sub     sp, #12
  be:   af00            add     r7, sp, #0
  c0:   6078            str     r0, [r7, #4]
  c2:   687b            ldr     r3, [r7, #4]
  c4:   681b            ldr     r3, [r3, #0]
  c6:   3301            adds    r3, #1
  c8:   687a            ldr     r2, [r7, #4]
  ca:   6013            str     r3, [r2, #0]
  cc:   4618            mov     r0, r3
  ce:   370c            adds    r7, #12
  d0:   46bd            mov     sp, r7
  d2:   bc80            pop     {r7}
  d4:   4770            bx      lr
```
只看核心逻辑的话，normal_inc本质是
``` asm
  cc:   681b            ldr     r3, [r3, #0]
  ce:   3301            adds    r3, #1
  d2:   6013            str     r3, [r2, #0]
```
读数据->递增->写回。
而atomic_inc 的差异就会是
``` asm
  9a:   ldrex   r2, [r1]          ; 独占加载
  9e:   adds    r2, #1
  a0:   strex   r3, r2, [r1]      ; 独占写入
  a8:   cmp     r3, #0
  ac:   bne.n   98                 ; 失败重试
```
流程也是读数据->递增->写回，但是写回的操作，由str换成了strex。而strex会一个排他的写入指令，这样如果在写入过程中出现了中断被修改的话，strex会抛出错误码，这样通过对错误码的比较加入retry loop，可以确保写入的原子性。但是代价就是多了一个循环控制，如果在竞争激烈的时候这个循环是可能多次触发的。

## 独占监视器
LDREX和STREX是配对出现的，它们依赖CPU内部的独占监视器（Exclusive Monitor）来工作：
```
LDREX Rt, [Rn]     ← 加载 Rt = *Rn, 同时标记 Rn 地址为"独占访问"
STREX Rd, Rt, [Rn] ← 尝试写 *Rn = Rt
                     ├── 独占监视器判定: 自 LDREX 以来有人写过这个地址吗？
                     │   ├── 没有 → 写入成功, Rd = 0
                     │   └── 有 → 写入失败, Rd = 1, *Rn 不变
                     └── 结果在 Rd 里
```
在单核Cortex-M上"有人写过"的唯一可能就是中断。中断处理程序里要是碰了同一个变量，STREX就会返回1，然后外层的while (failed) 循环重试，直到没有中断冲突。
注意：LDREX和STREX必须成对使用，中间间隔越小越好。如果在LDREX之后、STREX之前发生了异常或上下文切换，独占监视器可能会被清除，导致STREX失败——这恰恰是它保证原子性的方式。

## spin_lock & spin_unlock
``` asm
000000de <spin_lock>:
  de:   b480            push    {r7}
  e0:   b085            sub     sp, #20
  e2:   af00            add     r7, sp, #0
  e4:   6078            str     r0, [r7, #4]
  e6:   687a            ldr     r2, [r7, #4]
  e8:   e852 3f00       ldrex   r3, [r2]
  ec:   60fb            str     r3, [r7, #12]
  ee:   68fb            ldr     r3, [r7, #12]
  f0:   2b00            cmp     r3, #0
  f2:   d1f8            bne.n   e6 <spin_lock+0x8>
  f4:   2101            movs    r1, #1
  f6:   687a            ldr     r2, [r7, #4]
  f8:   e842 1300       strex   r3, r1, [r2]
  fc:   60fb            str     r3, [r7, #12]
  fe:   68fb            ldr     r3, [r7, #12]
 100:   4618            mov     r0, r3
 102:   3714            adds    r7, #20
 104:   46bd            mov     sp, r7
 106:   bc80            pop     {r7}
 108:   4770            bx      lr

0000010a <spin_unlock>:
 10a:   b480            push    {r7}
 10c:   b083            sub     sp, #12
 10e:   af00            add     r7, sp, #0
 110:   6078            str     r0, [r7, #4]
 112:   687b            ldr     r3, [r7, #4]
 114:   2200            movs    r2, #0
 116:   601a            str     r2, [r3, #0]
 118:   bf00            nop
 11a:   370c            adds    r7, #12
 11c:   46bd            mov     sp, r7
 11e:   bc80            pop     {r7}
 120:   4770            bx      lr
```
完整走一遍spin_lock的逻辑：
```
1. LDREX r3, [lock]    读 lock, 设置独占标记
   CMP  r3, #0          是 0 吗?
   BNE  1              不是 0 → 锁被别人占着, 回头再读

2. MOVS r1, #1          r1 = 1 (要写入的值)
   STREX r3, r1, [lock]  尝试写入: *lock = 1
                         返回 r3 = 0 (成功) 或 1 (失败)

3. 返回 r3               caller 检查返回值
```
而 spin_unlock 就简单得多——只是str r2, [r3, #0]，一条普通STR把锁清零。不需要 LDREX/STREX，因为"写 0"这个操作不会被其他核误解（其他核正在 LDREX 等待，你这里str写0会被它们的独占监视器检测到，触发STREX失败然后重试）。
完整的加锁解锁周期：
```
        LDREX → lock == 0? → STREX(1) → 成功 → [临界区] → STR(0)
           ↑                      ↓
           └──── 等待 ──── BNE ← 失败
```
值得注意的是spin_lock的返回值——严格来说，spin_lock在STREX成功后就立即返回了0（r3 = 0），但它没有检查返回值！这是一个小瑕疵——如果 STREX 在写入锁值之后又被其它事情打断，锁实际上没有被获取，但它返回了0。在严格的生产代码里，spin_lock的LDREX→CMP→STREX应该也包在一个循环里，确保获取锁后再检查一次。但在这个裸机单中断的简化场景下，它已经够用了。
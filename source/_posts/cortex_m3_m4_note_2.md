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

# SysTick 中断与并发

到这里为止的实验都还只有一条控制流。但真实 MCU 程序里最重要的东西是中断——它会在任意两条指令之间插进来一段别人的代码，而这段代码和你正在跑的函数共享同一片内存。这一节用 SysTick 做一次“中断改全局变量”的演示，它也是后面异常/中断章节的预热。

``` c
/*
 * 观察目标: 中断共享变量与 volatile 的必要性
 *
 * 编译: make 21-concurrency.elf
 * GDB:  make qemu-gdb-21-concurrency
 *   终端2: gdb-multiarch -q -ex "target remote :1234" 21-concurrency.elf
 *
 * 关注点:
 *   1. SysTick 中断每 N 个 CPU 周期递增全局变量 tick
 *   2. GDB 可观察 tick 在中断中被修改、main 循环中读取
 *   3. main 循环中 volatile 强制每次迭代重新 LDR
 *   4. 中断修改 main 使用的变量 → 典型的并发问题土壤
 *   5. QEMU 下 SysTick 频率有限, 纯运行时退出可能较慢;
 *      用 GDB 设断点观察即可, 也可用 -icount 加速
 *
 * 这是后续异常/中断章节的预热。
 */

#include <stdint.h>

volatile uint32_t systick_count;

void SysTick_Handler(void) {
    systick_count++;
}

static void systick_init(void) {
    /* SysTick: processor clock, 使能 + 中断 */
    *((volatile uint32_t *)0xE000E014) = 1000 - 1;  /* STK_LOAD */
    *((volatile uint32_t *)0xE000E018) = 0;          /* STK_VAL */
    *((volatile uint32_t *)0xE000E010) = 7;          /* STK_CTRL: enable + tickint + clksrc */
}

int main(void) {
    systick_init();

    while (1) {
        if (systick_count > 1000)
            break;
    }

    return 0;
}
```

## 中断处理程序

``` asm
00000090 <SysTick_Handler>:
  90:   b480            push    {r7}
  92:   af00            add     r7, sp, #0
  94:   4b04            ldr     r3, [pc, #16]   @ (a8 <SysTick_Handler+0x18>)
  96:   681b            ldr     r3, [r3, #0]
  98:   3301            adds    r3, #1
  9a:   4a03            ldr     r2, [pc, #12]   @ (a8 <SysTick_Handler+0x18>)
  9c:   6013            str     r3, [r2, #0]
  9e:   bf00            nop
  a0:   46bd            mov     sp, r7
  a2:   bc80            pop     {r7}
  a4:   4770            bx      lr
  a6:   bf00            nop
  a8:   20000000        .word   0x20000000

000000ac <systick_init>:
  ac:   b480            push    {r7}
  ae:   af00            add     r7, sp, #0
  b0:   4b06            ldr     r3, [pc, #24]   @ (cc <systick_init+0x20>)
  b2:   f240 32e7       movw    r2, #999        @ 0x3e7
  b6:   601a            str     r2, [r3, #0]
  b8:   4b05            ldr     r3, [pc, #20]   @ (d0 <systick_init+0x24>)
  ba:   2200            movs    r2, #0
  bc:   601a            str     r2, [r3, #0]
  be:   4b05            ldr     r3, [pc, #20]   @ (d4 <systick_init+0x28>)
  c0:   2207            movs    r2, #7
  c2:   601a            str     r2, [r3, #0]
  c4:   bf00            nop
  c6:   46bd            mov     sp, r7
  c8:   bc80            pop     {r7}
  ca:   4770            bx      lr
  cc:   e000e014        .word   0xe000e014
  d0:   e000e018        .word   0xe000e018
  d4:   e000e010        .word   0xe000e010
```

SysTick_Handler 干的事很朴素：`ldr r3, [pc, #16]` 从字面量池取出 systick_count 的地址（0x20000000，在 .bss 里），`ldr` 读出来，`adds r3, #1`，再 `str` 写回去。这就是 `systick_count++` 最直白的翻译。

有两点值得留意。一是整个处理程序里没有 `push {lr}`——因为它不调用任何函数，是个“叶子”，全程不会踩到 lr，所以返回时直接 `bx lr` 就回到被中断的地方。二是它头顶照样挂着 `push {r7}` / `add r7, sp, #0` 这套帧指针序言：这是 GCC 在 -O0 下一视同仁的产物，并不因为它是中断就特殊对待。

systick_init 则是往 SysTick 的三个寄存器写值：`movw r2, #999` 写进 0xE000E014（STK_LOAD，重装载值 1000-1，即每 1000 个时钟打一次中断），清 0xE000E018（STK_VAL），最后把 7 写进 0xE000E010（STK_CTRL：使能 + 开中断 + 处理器时钟）。这三个都是外设寄存器地址，在汇编里就是三个 .word 常量。

## 主循环轮询

``` asm
000000d8 <main>:
  d8:   b580            push    {r7, lr}
  da:   af00            add     r7, sp, #0
  dc:   f7ff ffe6       bl      ac <systick_init>
  e0:   4b04            ldr     r3, [pc, #16]   @ (f4 <main+0x1c>)
  e2:   681b            ldr     r3, [r3, #0]
  e4:   f5b3 7f7a       cmp.w   r3, #1000       @ 0x3e8
  e8:   d800            bhi.n   ec <main+0x14>
  ea:   e7f9            b.n     e0 <main+0x8>
  ec:   bf00            nop
  ee:   2300            movs    r3, #0
  f0:   4618            mov     r0, r3
  f2:   bd80            pop     {r7, pc}
  f4:   20000000        .word   0x20000000
```

main 里的 `while (1) { if (systick_count > 1000) break; }` 编译出来是：先把 systick_count 读进 r3，`cmp.w r3, #1000`，再 `bhi`（高于则跳走）。两个细节：

- **每圈都重新 LDR**：因为 systick_count 是 volatile，编译器不能把它缓存在寄存器里，循环每转一圈都会真的去内存读一次。如果它不是 volatile，优化一开，这个循环就会被编成“只读一次然后死循环”——这正是上一节 volatile 的直接后果。
- **`bhi` 是无符号比较**：systick_count 是 uint32_t，`> 1000` 走的是无符号条件码（bhi 一族），而不是有符号的 bgt。

## 动态观察

光看汇编还不够——这个实验的意义在于“中断真的插进来了”。在 GDB 里把断点设在 SysTick_Handler 上，先放行 4 次：

``` bash
(gdb) break SysTick_Handler
(gdb) ignore 1 4
(gdb) continue
Breakpoint 1, SysTick_Handler () at 21-concurrency.c:24
24        systick_count++;
$1 = 4
(gdb) bt
#0  SysTick_Handler () at 21-concurrency.c:24
#1  <signal handler called>
#2  0x000000e2 in main () at 21-concurrency.c:38
(gdb) info registers pc lr
pc             0x94                0x94 <SysTick_Handler+4>
lr             0xfffffff9          -7
```

停在第 5 次进入中断的时刻，此时 systick_count 已经是 4。更值得看的是 backtrace 里那一层 `<signal handler called>`——处理器没有“调用者压入的返回地址”这回事，GDB 只能诚实地告诉你“下面这段不是普通函数调用”。再看 lr：`0xfffffff9`。

0xFFFFFFF9 是 EXC_RETURN。中断的返回不靠压栈的地址，而靠 lr 里这个魔法值：它告诉 CPU“返回到线程模式、用 MSP、栈帧是基本帧”。这也是为什么中断处理程序里绝不能随手改 lr。

一路跑到底，main 的循环会在 systick_count 第一次超过 1000 时退出：

``` bash
Breakpoint 2, main () at 21-concurrency.c:39
39                break;
$2 = 1001
(gdb) x/1xw 0x20000000
0x20000000 <systick_count>:    0x000003e9
```

1001 = 0x3e9，和直接读内存的结果一致——中断确实在 main 背后偷偷把这块内存加了一千次。

# 可重入与不可重入

“可重入”这个词听起来玄，其实判据只有一条：**函数运行期间，它的状态放在哪里？**放在全局/static（.data/.bss）里就不可重入，因为下一次进入会覆盖上一次的状态；全部放在参数和栈上就可重入。落到汇编层面，就是“访问固定地址”和“访问 SP 相对地址”的区别。

``` c
/*
 * 观察目标: 不可重入函数的成因
 *
 * 编译: make 22-reentrancy.elf
 * 反汇编: arm-none-eabi-objdump -d 22-reentrancy.elf
 *
 * 关注点:
 *   1. 函数依赖全局/静态变量 → 第一次调用未完成时第二次调用破坏状态
 *   2. 可重入版本只使用栈 (参数 + 局部变量), 天然安全
 *   3. 反汇编中: 不可重入函数访问 .data/.bss (LDR from global addr)
 *                可重入函数只操作 SP 相关地址 (LDR from SP offset)
 */

static int seed = 1;

/* 不可重入: 依赖全局变量 seed */
static int rand_int(void) {
    seed = seed * 1103515245 + 12345;
    return (seed >> 16) & 0x7FFF;
}

/* 可重入: 依赖调用者传入的状态 */
static int rand_int_r(int *state) {
    *state = *state * 1103515245 + 12345;
    return (*state >> 16) & 0x7FFF;
}

/* 不可重入: 内部 static 缓冲区 */
static char *itoa_bad(int n) {
    static char buf[12];
    int i = 0;
    if (n < 0) { n = -n; }
    do { buf[i++] = '0' + (n % 10); } while ((n /= 10) > 0);
    buf[i] = '\0';
    return buf;
}

int main(void) {
    volatile int r1, r2;
    volatile char *s;
    int state = 1234;

    r1 = rand_int();
    r1 = rand_int();

    r2 = rand_int_r(&state);
    r2 = rand_int_r(&state);

    s = itoa_bad(42);
    return r1 + r2;
}
```

## 依赖全局状态的版本

``` asm
00000090 <rand_int>:
  90:   b480            push    {r7}
  92:   af00            add     r7, sp, #0
  94:   4b09            ldr     r3, [pc, #36]   @ (bc <rand_int+0x2c>)
  96:   681b            ldr     r3, [r3, #0]
  98:   4a09            ldr     r2, [pc, #36]   @ (c0 <rand_int+0x30>)
  9a:   fb02 f303       mul.w   r3, r2, r3
  9e:   f503 5340       add.w   r3, r3, #12288  @ 0x3000
  a2:   3339            adds    r3, #57 @ 0x39
  a4:   4a05            ldr     r2, [pc, #20]   @ (bc <rand_int+0x2c>)
  a6:   6013            str     r3, [r2, #0]
  a8:   4b04            ldr     r3, [pc, #16]   @ (bc <rand_int+0x2c>)
  aa:   681b            ldr     r3, [r3, #0]
  ac:   141b            asrs    r3, r3, #16
  ae:   f3c3 030e       ubfx    r3, r3, #0, #15
  b2:   4618            mov     r0, r3
  b4:   46bd            mov     sp, r7
  b6:   bc80            pop     {r7}
  b8:   4770            bx      lr
  ba:   bf00            nop
  bc:   20000000        .word   0x20000000
  c0:   41c64e6d        .word   0x41c64e6d
```

rand_int 是一个标准的 LCG。它把状态 seed 存在文件级 static 变量里，汇编上表现为：`ldr r3, [r3, #0]`（r3 来自字面量池里的 0x20000000，即 seed 的地址），`mul.w r3, r2, r3`（乘以 1103515245 = 0x41c64e6d），`add.w ... #0x3000` 加 `adds #57`（合起来 +12345），`str` 写回，最后重新 `ldr` 读出来做移位、取低 15 位。

关键在于那个 0x20000000——它是 .data 段里一个**固定地址**。不管谁、什么时候调用 rand_int，用的都是同一格内存。所以这个函数天生不可重入：如果第一次调用算到一半被打断，第二次进来会把 seed 改掉，第一次的后续计算就跟着错乱。

## 把状态交给调用者

``` asm
000000c4 <rand_int_r>:
  c4:   b480            push    {r7}
  c6:   b083            sub     sp, #12
  c8:   af00            add     r7, sp, #0
  ca:   6078            str     r0, [r7, #4]
  cc:   687b            ldr     r3, [r7, #4]
  ce:   681b            ldr     r3, [r3, #0]
  d0:   4a08            ldr     r2, [pc, #32]   @ (f4 <rand_int_r+0x30>)
  d2:   fb02 f303       mul.w   r3, r2, r3
  d6:   f503 5340       add.w   r3, r3, #12288  @ 0x3000
  da:   3339            adds    r3, #57 @ 0x39
  dc:   687a            ldr     r2, [r7, #4]
  de:   6013            str     r3, [r2, #0]
  e0:   687b            ldr     r3, [r7, #4]
  e2:   681b            ldr     r3, [r3, #0]
  e4:   141b            asrs    r3, r3, #16
  e6:   f3c3 030e       ubfx    r3, r3, #0, #15
  ea:   4618            mov     r0, r3
  ec:   370c            adds    r7, #12
  ee:   46bd            mov     sp, r7
  f0:   bc80            pop     {r7}
  f2:   4770            bx      lr
  f4:   41c64e6d        .word   0x41c64e6d
```

rand_int_r 做的事一模一样，唯一的区别是状态从哪里来：它接收一个 `int *state`，全程只跟这个指针打交道。汇编里除了取参数、算乘法，所有访问都是 `[r7, #4]` 这种 SP 相对偏移——**没有任何一个固定的全局地址**。

这就是可重入的版本：状态跟着调用走，每次调用各用各的，中断里再调它也不会互相干扰。

## 内部 static 缓冲区

``` asm
000000f8 <itoa_bad>:
  f8:   b480            push    {r7}
  fa:   b085            sub     sp, #20
  fc:   af00            add     r7, sp, #0
  fe:   6078            str     r0, [r7, #4]
 100:   2300            movs    r3, #0
 102:   60fb            str     r3, [r7, #12]
 104:   687b            ldr     r3, [r7, #4]
 106:   2b00            cmp     r3, #0
 108:   da02            bge.n   110 <itoa_bad+0x18>
 10a:   687b            ldr     r3, [r7, #4]
 10c:   425b            negs    r3, r3
 10e:   607b            str     r3, [r7, #4]
 110:   687a            ldr     r2, [r7, #4]
 112:   4b14            ldr     r3, [pc, #80]   @ (164 <itoa_bad+0x6c>)
 114:   fb83 1302       smull   r1, r3, r3, r2
 118:   1099            asrs    r1, r3, #2
 11a:   17d3            asrs    r3, r2, #31
 11c:   1ac9            subs    r1, r1, r3
 11e:   460b            mov     r3, r1
 120:   009b            lsls    r3, r3, #2
 122:   440b            add     r3, r1
 124:   005b            lsls    r3, r3, #1
 126:   1ad1            subs    r1, r2, r3
 128:   b2ca            uxtb    r2, r1
 12a:   68fb            ldr     r3, [r7, #12]
 12c:   1c59            adds    r1, r3, #1
 12e:   60f9            str     r1, [r7, #12]
 130:   3230            adds    r2, #48 @ 0x30
 132:   b2d1            uxtb    r1, r2
 134:   4a0c            ldr     r2, [pc, #48]   @ (168 <itoa_bad+0x70>)
 136:   54d1            strb    r1, [r2, r3]
 138:   687b            ldr     r3, [r7, #4]
 13a:   4a0a            ldr     r2, [pc, #40]   @ (164 <itoa_bad+0x6c>)
 13c:   fb82 1203       smull   r1, r2, r2, r3
 140:   1092            asrs    r2, r2, #2
 142:   17db            asrs    r3, r3, #31
 144:   1ad3            subs    r3, r2, r3
 146:   607b            str     r3, [r7, #4]
 148:   687b            ldr     r3, [r7, #4]
 14a:   2b00            cmp     r3, #0
 14c:   dce0            bgt.n   110 <itoa_bad+0x18>
 14e:   4a06            ldr     r2, [pc, #24]   @ (168 <itoa_bad+0x70>)
 150:   68fb            ldr     r3, [r7, #12]
 152:   4413            add     r3, r2
 154:   2200            movs    r2, #0
 156:   701a            strb    r2, [r3, #0]
 158:   4b03            ldr     r3, [pc, #12]   @ (168 <itoa_bad+0x70>)
 15a:   4618            mov     r0, r3
 15c:   3714            adds    r7, #20
 15e:   46bd            mov     sp, r7
 160:   bc80            pop     {r7}
 162:   4770            bx      lr
 164:   66666667        .word   0x66666667
 168:   20000004        .word   0x20000004
```

itoa_bad 更隐蔽一点：它内部有个 `static char buf[12]`，最后 `return buf`。汇编里最后那句 `ldr r3, [pc, #12]` 取出来的 0x20000004 就是 buf 的固定地址，函数返回的就是它。

这个函数的问题不在于重入时算错，而在于**返回的是一块所有人共享的内存**。两个调用者先后调用它，拿到的是同一个地址，第二个人的结果会把第一个人的覆盖掉。这类“返回内部 static 缓冲区”的接口，在并发或嵌套调用下几乎必然出问题。
# 浮点：M3 软浮点 vs M4 硬 FPU

这是全系列第一次把 M3 和 M4 摆在一起对比。M4 比 M3 多出来的最主要的东西就是 FPU（浮点单元），这一节就来看：同一段浮点 C 代码，两边编译出来差多少。

``` c
/*
 * 观察目标: M3 软浮点 vs M4 硬件 FPU
 *
 * M3 编译: make 23-float.elf
 * M4 编译: make CFLAGS="-mcpu=cortex-m4 -mfloat-abi=hard -mfpu=fpv4-sp-d16" 23-float.elf
 *
 * 反汇编对比:
 *   arm-none-eabi-objdump -d 23-float.elf          (M3, 软浮点)
 *   arm-none-eabi-objdump -d 23-float.elf | grep -E "vldr|vstr|vadd|vmul"  (M4, 硬浮点)
 *
 * 关注点:
 *   1. M3: 浮点运算调用 __aeabi_fadd / __aeabi_fmul 等库函数
 *   2. M4: VADD / VSUB / VMUL / VLDR / VSTR 等硬件指令
 *   3. M4 硬浮点的 prologue 需要 VPUSH 保存浮点寄存器
 */

static float fadd(float a, float b)   { return a + b; }
static float fsub(float a, float b)   { return a - b; }
static float fmul(float a, float b)   { return a * b; }
static float fdiv(float a, float b)   { return a / b; }

static float fma(float a, float b, float c) {
    return a * b + c;
}

int main(void) {
    volatile float r;
    r = fadd(1.5f, 2.5f);
    r = fsub(10.0f, 3.0f);
    r = fmul(2.0f, 3.0f);
    r = fdiv(7.0f, 2.0f);
    r = fma(2.0f, 3.0f, 1.0f);
    return 0;
}
```

两版都编出来：

``` bash
make 23-float.elf
make CFLAGS="-mcpu=cortex-m4 -mfloat-abi=hard -mfpu=fpv4-sp-d16" 23-float.elf
```

M4 必须同时给出 `-mfloat-abi=hard`（用硬件浮点调用约定）和 `-mfpu=fpv4-sp-d16`（M4 上这块单精度 FPU），缺一不可。

## M3：浮点运算全靠库函数

``` asm
00000090 <fadd>:
  90:   b580            push    {r7, lr}
  92:   b082            sub     sp, #8
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6039            str     r1, [r7, #0]
  9a:   6839            ldr     r1, [r7, #0]
  9c:   6878            ldr     r0, [r7, #4]
  9e:   f000 f931       bl      304 <__addsf3>
  a2:   4603            mov     r3, r0
  a4:   4618            mov     r0, r3
  a6:   3708            adds    r7, #8
  a8:   46bd            mov     sp, r7
  aa:   bd80            pop     {r7, pc}

000000ac <fsub>:
  ac:   b580            push    {r7, lr}
  ae:   b082            sub     sp, #8
  b0:   af00            add     r7, sp, #0
  b2:   6078            str     r0, [r7, #4]
  b4:   6039            str     r1, [r7, #0]
  b6:   6839            ldr     r1, [r7, #0]
  b8:   6878            ldr     r0, [r7, #4]
  ba:   f000 f921       bl      300 <__aeabi_fsub>
  be:   4603            mov     r3, r0
  c0:   4618            mov     r0, r3
  c2:   3708            adds    r7, #8
  c4:   46bd            mov     sp, r7
  c6:   bd80            pop     {r7, pc}

000000c8 <fmul>:
  c8:   b580            push    {r7, lr}
  ca:   b082            sub     sp, #8
  cc:   af00            add     r7, sp, #0
  ce:   6078            str     r0, [r7, #4]
  d0:   6039            str     r1, [r7, #0]
  d2:   6839            ldr     r1, [r7, #0]
  d4:   6878            ldr     r0, [r7, #4]
  d6:   f000 fa1d       bl      514 <__aeabi_fmul>
  da:   4603            mov     r3, r0
  dc:   4618            mov     r0, r3
  de:   3708            adds    r7, #8
  e0:   46bd            mov     sp, r7
  e2:   bd80            pop     {r7, pc}

000000e4 <fdiv>:
  e4:   b580            push    {r7, lr}
  e6:   b082            sub     sp, #8
  e8:   af00            add     r7, sp, #0
  ea:   6078            str     r0, [r7, #4]
  ec:   6039            str     r1, [r7, #0]
  ee:   6839            ldr     r1, [r7, #0]
  f0:   6878            ldr     r0, [r7, #4]
  f2:   f000 fac3       bl      67c <__aeabi_fdiv>
  f6:   4603            mov     r3, r0
  f8:   4618            mov     r0, r3
  fa:   3708            adds    r7, #8
  fc:   46bd            mov     sp, r7
  fe:   bd80            pop     {r7, pc}

00000100 <fma>:
 100:   b580            push    {r7, lr}
 102:   b084            sub     sp, #16
 104:   af00            add     r7, sp, #0
 106:   60f8            str     r0, [r7, #12]
 108:   60b9            str     r1, [r7, #8]
 10a:   607a            str     r2, [r7, #4]
 10c:   68b9            ldr     r1, [r7, #8]
 10e:   68f8            ldr     r0, [r7, #12]
 110:   f000 fa00       bl      514 <__aeabi_fmul>
 114:   4603            mov     r3, r0
 116:   6879            ldr     r1, [r7, #4]
 118:   4618            mov     r0, r3
 11a:   f000 f8f3       bl      304 <__addsf3>
 11e:   4603            mov     r3, r0
 120:   4618            mov     r0, r3
 122:   3710            adds    r7, #16
 124:   46bd            mov     sp, r7
 126:   bd80            pop     {r7, pc}
```

五个函数各只剩一副空壳：把两个 float 参数从 r0/r1 存到栈上，再原样 `ldr` 回 r0/r1，然后 `bl` 一个软件浮点例程。真正的加减乘除是那些例程干的——名字各不相同（fadd 走 `__addsf3`，sub/mul/div 分别走 `__aeabi_fsub`/`__aeabi_fmul`/`__aeabi_fdiv`），但都属于编译器提供的软件浮点运行时。M3 没有 FPU，任何一次浮点运算都得这么绕一圈。

fma 尤其明显：`a*b+c` 先在 `__aeabi_fmul` 里算乘法，返回值在 r0，再喂给 `__addsf3` 算加法——两次函数调用。

另外注意 soft-float 下浮点也走整数寄存器：参数在 r0/r1，返回值在 r0，float 的位模式被当成普通 32 位整数搬运。

## M3：浮点参数走 r0/r1

``` asm
00000128 <main>:
 128:   b580            push    {r7, lr}
 12a:   b082            sub     sp, #8
 12c:   af00            add     r7, sp, #0
 12e:   4914            ldr     r1, [pc, #80]   @ (180 <main+0x58>)
 130:   f04f 507f       mov.w   r0, #1069547520 @ 0x3fc00000
 134:   f7ff ffac       bl      90 <fadd>
 138:   4603            mov     r3, r0
 13a:   607b            str     r3, [r7, #4]
 13c:   4911            ldr     r1, [pc, #68]   @ (184 <main+0x5c>)
 13e:   4812            ldr     r0, [pc, #72]   @ (188 <main+0x60>)
 140:   f7ff ffb4       bl      ac <fsub>
 144:   4603            mov     r3, r0
 146:   607b            str     r3, [r7, #4]
 148:   490e            ldr     r1, [pc, #56]   @ (184 <main+0x5c>)
 14a:   f04f 4080       mov.w   r0, #1073741824 @ 0x40000000
 14e:   f7ff ffbb       bl      c8 <fmul>
 152:   4603            mov     r3, r0
 154:   607b            str     r3, [r7, #4]
 156:   f04f 4180       mov.w   r1, #1073741824 @ 0x40000000
 15a:   480c            ldr     r0, [pc, #48]   @ (18c <main+0x64>)
 15c:   f7ff ffc2       bl      e4 <fdiv>
 160:   4603            mov     r3, r0
 162:   607b            str     r3, [r7, #4]
 164:   f04f 527e       mov.w   r2, #1065353216 @ 0x3f800000
 168:   4906            ldr     r1, [pc, #24]   @ (184 <main+0x5c>)
 16a:   f04f 4080       mov.w   r0, #1073741824 @ 0x40000000
 16e:   f7ff ffc7       bl      100 <fma>
 172:   4603            mov     r3, r0
 174:   607b            str     r3, [r7, #4]
 176:   2300            movs    r3, #0
 178:   4618            mov     r0, r3
 17a:   3708            adds    r7, #8
 17c:   46bd            mov     sp, r7
 17e:   bd80            pop     {r7, pc}
 180:   40200000        .word   0x40200000
 184:   40400000        .word   0x40400000
 188:   41200000        .word   0x41200000
 18c:   40e00000        .word   0x40e00000
 190:   f04f 0cff       mov.w   ip, #255        @ 0xff
 194:   ea1c 52d0       ands.w  r2, ip, r0, lsr #23
 198:   bf1e            ittt    ne
 19a:   ea1c 53d1       andsne.w        r3, ip, r1, lsr #23
 19e:   ea92 0f0c       teqne   r2, ip
 1a2:   ea93 0f0c       teqne   r3, ip
 1a6:   d06f            beq.n   288 <main+0x160>
 1a8:   441a            add     r2, r3
 1aa:   ea80 0c01       eor.w   ip, r0, r1
 1ae:   0240            lsls    r0, r0, #9
 1b0:   bf18            it      ne
 1b2:   ea5f 2141       movsne.w        r1, r1, lsl #9
 1b6:   d01e            beq.n   1f6 <main+0xce>
 1b8:   f04f 6300       mov.w   r3, #134217728  @ 0x8000000
 1bc:   ea43 1050       orr.w   r0, r3, r0, lsr #5
 1c0:   ea43 1151       orr.w   r1, r3, r1, lsr #5
 1c4:   fba0 3101       umull   r3, r1, r0, r1
 1c8:   f00c 4000       and.w   r0, ip, #2147483648     @ 0x80000000
 1cc:   f5b1 0f00       cmp.w   r1, #8388608    @ 0x800000
 1d0:   bf3e            ittt    cc
 1d2:   0049            lslcc   r1, r1, #1
 1d4:   ea41 71d3       orrcc.w r1, r1, r3, lsr #31
 1d8:   005b            lslcc   r3, r3, #1
 1da:   ea40 0001       orr.w   r0, r0, r1
 1de:   f162 027f       sbc.w   r2, r2, #127    @ 0x7f
 1e2:   2afd            cmp     r2, #253        @ 0xfd
 1e4:   d81d            bhi.n   222 <main+0xfa>
 1e6:   f1b3 4f00       cmp.w   r3, #2147483648 @ 0x80000000
 1ea:   eb40 50c2       adc.w   r0, r0, r2, lsl #23
 1ee:   bf08            it      eq
 1f0:   f020 0001       biceq.w r0, r0, #1
 1f4:   4770            bx      lr
 1f6:   f090 0f00       teq     r0, #0
 1fa:   f00c 4c00       and.w   ip, ip, #2147483648     @ 0x80000000
 1fe:   bf08            it      eq
 200:   0249            lsleq   r1, r1, #9
 202:   ea4c 2050       orr.w   r0, ip, r0, lsr #9
 206:   ea40 2051       orr.w   r0, r0, r1, lsr #9
 20a:   3a7f            subs    r2, #127        @ 0x7f
 20c:   bfc2            ittt    gt
 20e:   f1d2 03ff       rsbsgt  r3, r2, #255    @ 0xff
 212:   ea40 50c2       orrgt.w r0, r0, r2, lsl #23
 216:   4770            bxgt    lr
 218:   f440 0000       orr.w   r0, r0, #8388608        @ 0x800000
 21c:   f04f 0300       mov.w   r3, #0
 220:   3a01            subs    r2, #1
 222:   dc5d            bgt.n   2e0 <main+0x1b8>
 224:   f112 0f19       cmn.w   r2, #25
 228:   bfdc            itt     le
 22a:   f000 4000       andle.w r0, r0, #2147483648     @ 0x80000000
 22e:   4770            bxle    lr
 230:   f1c2 0200       rsb     r2, r2, #0
 234:   0041            lsls    r1, r0, #1
 236:   fa21 f102       lsr.w   r1, r1, r2
 23a:   f1c2 0220       rsb     r2, r2, #32
 23e:   fa00 fc02       lsl.w   ip, r0, r2
 242:   ea5f 0031       movs.w  r0, r1, rrx
 246:   f140 0000       adc.w   r0, r0, #0
 24a:   ea53 034c       orrs.w  r3, r3, ip, lsl #1
 24e:   bf08            it      eq
 250:   ea20 70dc       biceq.w r0, r0, ip, lsr #31
 254:   4770            bx      lr
 256:   f092 0f00       teq     r2, #0
 25a:   f000 4c00       and.w   ip, r0, #2147483648     @ 0x80000000
 25e:   bf02            ittt    eq
 260:   0040            lsleq   r0, r0, #1
 262:   f410 0f00       tsteq.w r0, #8388608    @ 0x800000
 266:   3a01            subeq   r2, #1
 268:   d0f9            beq.n   25e <main+0x136>
 26a:   ea40 000c       orr.w   r0, r0, ip
 26e:   f093 0f00       teq     r3, #0
 272:   f001 4c00       and.w   ip, r1, #2147483648     @ 0x80000000
 276:   bf02            ittt    eq
 278:   0049            lsleq   r1, r1, #1
 27a:   f411 0f00       tsteq.w r1, #8388608    @ 0x800000
 27e:   3b01            subeq   r3, #1
 280:   d0f9            beq.n   276 <main+0x14e>
 282:   ea41 010c       orr.w   r1, r1, ip
 286:   e78f            b.n     1a8 <main+0x80>
 288:   ea0c 53d1       and.w   r3, ip, r1, lsr #23
 28c:   ea92 0f0c       teq     r2, ip
 290:   bf18            it      ne
 292:   ea93 0f0c       teqne   r3, ip
 296:   d00a            beq.n   2ae <main+0x186>
 298:   f030 4c00       bics.w  ip, r0, #2147483648     @ 0x80000000
 29c:   bf18            it      ne
 29e:   f031 4c00       bicsne.w        ip, r1, #2147483648     @ 0x80000000
 2a2:   d1d8            bne.n   256 <main+0x12e>
 2a4:   ea80 0001       eor.w   r0, r0, r1
 2a8:   f000 4000       and.w   r0, r0, #2147483648     @ 0x80000000
 2ac:   4770            bx      lr
 2ae:   f090 0f00       teq     r0, #0
 2b2:   bf17            itett   ne
 2b4:   f090 4f00       teqne   r0, #2147483648 @ 0x80000000
 2b8:   4608            moveq   r0, r1
 2ba:   f091 0f00       teqne   r1, #0
 2be:   f091 4f00       teqne   r1, #2147483648 @ 0x80000000
 2c2:   d014            beq.n   2ee <main+0x1c6>
 2c4:   ea92 0f0c       teq     r2, ip
 2c8:   d101            bne.n   2ce <main+0x1a6>
 2ca:   0242            lsls    r2, r0, #9
 2cc:   d10f            bne.n   2ee <main+0x1c6>
 2ce:   ea93 0f0c       teq     r3, ip
 2d2:   d103            bne.n   2dc <main+0x1b4>
 2d4:   024b            lsls    r3, r1, #9
 2d6:   bf18            it      ne
 2d8:   4608            movne   r0, r1
 2da:   d108            bne.n   2ee <main+0x1c6>
 2dc:   ea80 0001       eor.w   r0, r0, r1
 2e0:   f000 4000       and.w   r0, r0, #2147483648     @ 0x80000000
 2e4:   f040 40fe       orr.w   r0, r0, #2130706432     @ 0x7f000000
 2e8:   f440 0000       orr.w   r0, r0, #8388608        @ 0x800000
 2ec:   4770            bx      lr
 2ee:   f040 40fe       orr.w   r0, r0, #2130706432     @ 0x7f000000
 2f2:   f440 0040       orr.w   r0, r0, #12582912       @ 0xc00000
 2f6:   4770            bx      lr
```

main 里连算五个式子，每次都是把常量装进 r0/r1 再 `bl`，结果从 r0 挪到栈上的 volatile r。顺带可以直接读出每个浮点常量的位模式：`mov.w r0, #1069547520` 就是 0x3fc00000 = 1.5f；字面量池里依次是 2.5(0x40200000)、10.0(0x41200000)、3.0(0x40400000)、7.0(0x40e00000)、1.0(0x3f800000)。

## M4：VFP 硬件指令

``` asm
00000090 <fadd>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   ed87 0a01       vstr    s0, [r7, #4]
  9a:   edc7 0a00       vstr    s1, [r7]
  9e:   ed97 7a01       vldr    s14, [r7, #4]
  a2:   edd7 7a00       vldr    s15, [r7]
  a6:   ee77 7a27       vadd.f32        s15, s14, s15
  aa:   eeb0 0a67       vmov.f32        s0, s15
  ae:   370c            adds    r7, #12
  b0:   46bd            mov     sp, r7
  b2:   f85d 7b04       ldr.w   r7, [sp], #4
  b6:   4770            bx      lr

000000b8 <fsub>:
  b8:   b480            push    {r7}
  ba:   b083            sub     sp, #12
  bc:   af00            add     r7, sp, #0
  be:   ed87 0a01       vstr    s0, [r7, #4]
  c2:   edc7 0a00       vstr    s1, [r7]
  c6:   ed97 7a01       vldr    s14, [r7, #4]
  ca:   edd7 7a00       vldr    s15, [r7]
  ce:   ee77 7a67       vsub.f32        s15, s14, s15
  d2:   eeb0 0a67       vmov.f32        s0, s15
  d6:   370c            adds    r7, #12
  d8:   46bd            mov     sp, r7
  da:   f85d 7b04       ldr.w   r7, [sp], #4
  de:   4770            bx      lr

000000e0 <fmul>:
  e0:   b480            push    {r7}
  e2:   b083            sub     sp, #12
  e4:   af00            add     r7, sp, #0
  e6:   ed87 0a01       vstr    s0, [r7, #4]
  ea:   edc7 0a00       vstr    s1, [r7]
  ee:   ed97 7a01       vldr    s14, [r7, #4]
  f2:   edd7 7a00       vldr    s15, [r7]
  f6:   ee67 7a27       vmul.f32        s15, s14, s15
  fa:   eeb0 0a67       vmov.f32        s0, s15
  fe:   370c            adds    r7, #12
 100:   46bd            mov     sp, r7
 102:   f85d 7b04       ldr.w   r7, [sp], #4
 106:   4770            bx      lr

00000108 <fdiv>:
 108:   b480            push    {r7}
 10a:   b083            sub     sp, #12
 10c:   af00            add     r7, sp, #0
 10e:   ed87 0a01       vstr    s0, [r7, #4]
 112:   edc7 0a00       vstr    s1, [r7]
 116:   ed97 7a01       vldr    s14, [r7, #4]
 11a:   edd7 7a00       vldr    s15, [r7]
 11e:   eec7 6a27       vdiv.f32        s13, s14, s15
 122:   eef0 7a66       vmov.f32        s15, s13
 126:   eeb0 0a67       vmov.f32        s0, s15
 12a:   370c            adds    r7, #12
 12c:   46bd            mov     sp, r7
 12e:   f85d 7b04       ldr.w   r7, [sp], #4
 132:   4770            bx      lr

00000134 <fma>:
 134:   b480            push    {r7}
 136:   b085            sub     sp, #20
 138:   af00            add     r7, sp, #0
 13a:   ed87 0a03       vstr    s0, [r7, #12]
 13e:   edc7 0a02       vstr    s1, [r7, #8]
 142:   ed87 1a01       vstr    s2, [r7, #4]
 146:   ed97 7a03       vldr    s14, [r7, #12]
 14a:   edd7 7a02       vldr    s15, [r7, #8]
 14e:   ee27 7a27       vmul.f32        s14, s14, s15
 152:   edd7 7a01       vldr    s15, [r7, #4]
 156:   ee77 7a27       vadd.f32        s15, s14, s15
 15a:   eeb0 0a67       vmov.f32        s0, s15
 15e:   3714            adds    r7, #20
 160:   46bd            mov     sp, r7
 162:   f85d 7b04       ldr.w   r7, [sp], #4
 166:   4770            bx      lr
```

函数还是那副“把参数存栈再取回”的空壳（-O0 的锅），但真正干活的两条变了：fadd 里是 `vstr s0/s1`（存）、`vldr s14/s15`（取回）、**`vadd.f32 s15, s14, s15`**、`vmov.f32 s0, s15`（结果放回 s0 返回）。mul/div 同理，换成 `vmul.f32` / `vdiv.f32`。

也就是说：M3 里的一次函数调用，在 M4 里变成了一条指令。浮点参数也不再走 r0/r1，而是走 VFP 寄存器 s0、s1。

（这里没有出现 VPUSH。VPUSH 只在函数需要跨调用保存浮点寄存器时才出现，而本节的这些函数都是叶子，没什么要保的。尾声用的是 `ldr.w r7, [sp], #4` 而不是 `pop {r7}`，效果一样，都是把栈上存的 r7 收回来。）

## M4：浮点参数走 s0/s1

``` asm
00000168 <main>:
 168:   b580            push    {r7, lr}
 16a:   b082            sub     sp, #8
 16c:   af00            add     r7, sp, #0
 16e:   eef0 0a04       vmov.f32        s1, #4  @ 0x40200000  2.5
 172:   eeb7 0a08       vmov.f32        s0, #120        @ 0x3fc00000  1.5
 176:   f7ff ff8b       bl      90 <fadd>
 17a:   eef0 7a40       vmov.f32        s15, s0
 17e:   edc7 7a01       vstr    s15, [r7, #4]
 182:   eef0 0a08       vmov.f32        s1, #8  @ 0x40400000  3.0
 186:   eeb2 0a04       vmov.f32        s0, #36 @ 0x41200000  10.0
 18a:   f7ff ff95       bl      b8 <fsub>
 18e:   eef0 7a40       vmov.f32        s15, s0
 192:   edc7 7a01       vstr    s15, [r7, #4]
 196:   eef0 0a08       vmov.f32        s1, #8  @ 0x40400000  3.0
 19a:   eeb0 0a00       vmov.f32        s0, #0  @ 0x40000000  2.0
 19e:   f7ff ff9f       bl      e0 <fmul>
 1a2:   eef0 7a40       vmov.f32        s15, s0
 1a6:   edc7 7a01       vstr    s15, [r7, #4]
 1aa:   eef0 0a00       vmov.f32        s1, #0  @ 0x40000000  2.0
 1ae:   eeb1 0a0c       vmov.f32        s0, #28 @ 0x40e00000  7.0
 1b2:   f7ff ffa9       bl      108 <fdiv>
 1b6:   eef0 7a40       vmov.f32        s15, s0
 1ba:   edc7 7a01       vstr    s15, [r7, #4]
 1be:   eeb7 1a00       vmov.f32        s2, #112        @ 0x3f800000  1.0
 1c2:   eef0 0a08       vmov.f32        s1, #8  @ 0x40400000  3.0
 1c6:   eeb0 0a00       vmov.f32        s0, #0  @ 0x40000000  2.0
 1ca:   f7ff ffb3       bl      134 <fma>
 1ce:   eef0 7a40       vmov.f32        s15, s0
 1d2:   edc7 7a01       vstr    s15, [r7, #4]
 1d6:   2300            movs    r3, #0
 1d8:   4618            mov     r0, r3
 1da:   3708            adds    r7, #8
 1dc:   46bd            mov     sp, r7
 1de:   bd80            pop     {r7, pc}
```

main 的对比更直接：M3 版是把常量写进 r0/r1 再 `bl`；M4 版是写进 **s0/s1**（`vmov.f32 s0, #120` 这种，120 是 1.5f 的 VFP 立即数编码），再 `bl`，返回值在 s0 里。VFP 有一套专门的浮点立即数编码，所以像 1.5、2.0、3.0 这类“规整”的数不用访问内存，一条 vmov 就装进寄存器了。

最后提醒一句：M4 这里是 fpv4-**sp**-d16，只有**单精度**。本节所有运算都是 float；一旦出现 double，照样得回软件库——下一个实验的 float_to_double 会看到这一点。

# 类型转换的指令代价

``` c
/*
 * 观察目标: 类型转换的指令代价
 *
 * 编译: make 24-cast.elf
 * 反汇编: arm-none-eabi-objdump -d 24-cast.elf
 *
 * 关注点:
 *   1. float ←→ int: VCVT 指令 (M4) 或 __aeabi_f2iz / __aeabi_i2f (M3)
 *   2. 浮点截断 vs 四舍五入: C 强制转换是向零截断
 *   3. double ←→ float: 精度转换指令
 */

static int float_to_int(float f) {
    return (int)f;
}

static float int_to_float(int i) {
    return (float)i;
}

static float truncate_test(float f) {
    return (int)f;       /* 1.9 → 1,  -1.9 → -1 */
}

static double float_to_double(float f) {
    return (double)f;
}

static int unsigned_cast(unsigned int u) {
    return (int)u;       /* 大 unsigned → signed */
}

int main(void) {
    volatile int ri;
    volatile float rf;
    volatile double rd;

    ri = float_to_int(3.14f);
    rf = int_to_float(42);
    ri = truncate_test(1.9f);
    rd = float_to_double(3.14f);
    ri = unsigned_cast(0xFFFFFF00u);
    return 0;
}
```

## M3：每个转换都是一次库调用

``` asm
00000090 <float_to_int>:
  90:   b580            push    {r7, lr}
  92:   b082            sub     sp, #8
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6878            ldr     r0, [r7, #4]
  9a:   f000 fb2f       bl      6fc <__aeabi_f2iz>
  9e:   4603            mov     r3, r0
  a0:   4618            mov     r0, r3
  a2:   3708            adds    r7, #8
  a4:   46bd            mov     sp, r7
  a6:   bd80            pop     {r7, pc}

000000a8 <int_to_float>:
  a8:   b580            push    {r7, lr}
  aa:   b082            sub     sp, #8
  ac:   af00            add     r7, sp, #0
  ae:   6078            str     r0, [r7, #4]
  b0:   6878            ldr     r0, [r7, #4]
  b2:   f000 facf       bl      654 <__aeabi_i2f>
  b6:   4603            mov     r3, r0
  b8:   4618            mov     r0, r3
  ba:   3708            adds    r7, #8
  bc:   46bd            mov     sp, r7
  be:   bd80            pop     {r7, pc}

000000c0 <truncate_test>:
  c0:   b580            push    {r7, lr}
  c2:   b082            sub     sp, #8
  c4:   af00            add     r7, sp, #0
  c6:   6078            str     r0, [r7, #4]
  c8:   6878            ldr     r0, [r7, #4]
  ca:   f000 fb17       bl      6fc <__aeabi_f2iz>
  ce:   4603            mov     r3, r0
  d0:   4618            mov     r0, r3
  d2:   f000 fabf       bl      654 <__aeabi_i2f>
  d6:   4603            mov     r3, r0
  d8:   4618            mov     r0, r3
  da:   3708            adds    r7, #8
  dc:   46bd            mov     sp, r7
  de:   bd80            pop     {r7, pc}

000000e0 <float_to_double>:
  e0:   b580            push    {r7, lr}
  e2:   b082            sub     sp, #8
  e4:   af00            add     r7, sp, #0
  e6:   6078            str     r0, [r7, #4]
  e8:   6878            ldr     r0, [r7, #4]
  ea:   f000 f9a1       bl      430 <__aeabi_f2d>
  ee:   4602            mov     r2, r0
  f0:   460b            mov     r3, r1
  f2:   4610            mov     r0, r2
  f4:   4619            mov     r1, r3
  f6:   3708            adds    r7, #8
  f8:   46bd            mov     sp, r7
  fa:   bd80            pop     {r7, pc}
```

四个函数各买各账：
- `float_to_int` → `bl __aeabi_f2iz`（f→signed int，iz 表示向零取整）；
- `int_to_float` → `bl __aeabi_i2f`；
- `truncate_test` → 先 `__aeabi_f2iz` 再 `__aeabi_i2f`（函数返回 float，而 `(int)f` 是向零截断，转成 int 之后又得转回 float）；
- `float_to_double` → `bl __aeabi_f2d`，返回值占 **r0:r1 两个寄存器**，因为 double 是 64 位。

## M3：unsigned ↔ signed 是零成本

``` asm
000000fc <unsigned_cast>:
  fc:   b480            push    {r7}
  fe:   b083            sub     sp, #12
 100:   af00            add     r7, sp, #0
 102:   6078            str     r0, [r7, #4]
 104:   687b            ldr     r3, [r7, #4]
 106:   4618            mov     r0, r3
 108:   370c            adds    r7, #12
 10a:   46bd            mov     sp, r7
 10c:   bc80            pop     {r7}
 10e:   4770            bx      lr
```

`(int)u` 编译出来只有 `mov r0, r3`，没有任何实际运算。因为 unsigned→signed 只是同一串比特换个解释，位模式一模一样，CPU 什么也不用做。

## M4：VCVT 一条指令

``` asm
00000090 <float_to_int>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   ed87 0a01       vstr    s0, [r7, #4]
  9a:   edd7 7a01       vldr    s15, [r7, #4]
  9e:   eefd 7ae7       vcvt.s32.f32    s15, s15
  a2:   ee17 3a90       vmov    r3, s15
  a6:   4618            mov     r0, r3
  a8:   370c            adds    r7, #12
  aa:   46bd            mov     sp, r7
  ac:   f85d 7b04       ldr.w   r7, [sp], #4
  b0:   4770            bx      lr

000000b2 <int_to_float>:
  b2:   b480            push    {r7}
  b4:   b083            sub     sp, #12
  b6:   af00            add     r7, sp, #0
  b8:   6078            str     r0, [r7, #4]
  ba:   687b            ldr     r3, [r7, #4]
  bc:   ee07 3a90       vmov    s15, r3
  c0:   eef8 7ae7       vcvt.f32.s32    s15, s15
  c4:   eeb0 0a67       vmov.f32        s0, s15
  c8:   370c            adds    r7, #12
  ca:   46bd            mov     sp, r7
  cc:   f85d 7b04       ldr.w   r7, [sp], #4
  d0:   4770            bx      lr

000000d2 <truncate_test>:
  d2:   b480            push    {r7}
  d4:   b083            sub     sp, #12
  d6:   af00            add     r7, sp, #0
  d8:   ed87 0a01       vstr    s0, [r7, #4]
  dc:   edd7 7a01       vldr    s15, [r7, #4]
  e0:   eefd 7ae7       vcvt.s32.f32    s15, s15
  e4:   eef8 7ae7       vcvt.f32.s32    s15, s15
  e8:   eeb0 0a67       vmov.f32        s0, s15
  ec:   370c            adds    r7, #12
  ee:   46bd            mov     sp, r7
  f0:   f85d 7b04       ldr.w   r7, [sp], #4
  f4:   4770            bx      lr
```

- `float_to_int`：`vcvt.s32.f32 s15, s15`——一条指令把 float 转成 int。这条不带舍入后缀的 VCVT 默认就是**向零取整**，正好对上 C 的强制转换语义。
- `int_to_float`：`vmov s15, r3` 把整数挪进浮点寄存器，再 `vcvt.f32.s32 s15, s15`。
- `truncate_test`：`vcvt.s32.f32` 再 `vcvt.f32.s32`，两条来回，同样一条库调用都没有。

## M4：double 仍然走软件库

``` asm
000000f6 <float_to_double>:
  f6:   b580            push    {r7, lr}
  f8:   b082            sub     sp, #8
  fa:   af00            add     r7, sp, #0
  fc:   ed87 0a01       vstr    s0, [r7, #4]
 100:   6878            ldr     r0, [r7, #4]
 102:   f000 f9af       bl      464 <__aeabi_f2d>
 106:   4602            mov     r2, r0
 108:   460b            mov     r3, r1
 10a:   ec43 2b17       vmov    d7, r2, r3
 10e:   eeb0 0a47       vmov.f32        s0, s14
 112:   eef0 0a67       vmov.f32        s1, s15
 116:   3708            adds    r7, #8
 118:   46bd            mov     sp, r7
 11a:   bd80            pop     {r7, pc}

0000011c <unsigned_cast>:
 11c:   b480            push    {r7}
 11e:   b083            sub     sp, #12
 120:   af00            add     r7, sp, #0
 122:   6078            str     r0, [r7, #4]
 124:   687b            ldr     r3, [r7, #4]
 126:   4618            mov     r0, r3
 128:   370c            adds    r7, #12
 12a:   46bd            mov     sp, r7
 12c:   f85d 7b04       ldr.w   r7, [sp], #4
 130:   4770            bx      lr
```

即使 M4 带 FPU，`float → double` 还是 `bl __aeabi_f2d`。因为 fpv4-sp-d16 只带单精度硬件，double（64 位）在硬件层面根本不存在。转换完之后结果用 `vmov d7, r2, r3` 塞进一个双字浮点寄存器——但计算本身，还是软件干的。

（顺带：M4 版的 `unsigned_cast` 依旧是 `mov r0, r3`，和 M3 一样是零成本。）
# 优化等级

前面所有实验都跑在 -O0 下——那纯粹是为了“看清每一步”。但真实工程都开优化，所以这一节把同一份代码在 -O0 / -O1 / -O2 / -Os 下各编一遍，看编译器到底动了多少手脚。

``` c
/*
 * 观察目标: 不同优化等级对同一代码的指令差异
 *
 * 对比:
 *   make 25-optimization.elf                 → -O0
 *   make CFLAGS="-O1" 25-optimization.elf    → -O1
 *   make CFLAGS="-O2" 25-optimization.elf    → -O2
 *   make CFLAGS="-Os" 25-optimization.elf    → -Os
 *
 * 观察方式:
 *   arm-none-eabi-objdump -d 25-optimization.elf | wc -l           (指令总量)
 *   arm-none-eabi-objdump -d 25-optimization.elf | grep '<main>:' -A 30 (main 大小)
 *
 * 关注点:
 *   1. -O0: 每个 C 语句独立, 变量存在栈上 → 指令多, 有大量 LDR/STR
 *   2. -O1: 基本优化, 变量尽量留寄存器 → 指令减少一半
 *   3. -O2: 更激进, 可能循环展开 → 指令更多但执行更快
 *   4. -Os: 侧重代码大小, 可能用较慢但更短的指令序列
 */

static int sum_array(int *arr, int n) {
    int sum = 0;
    for (int i = 0; i < n; i++)
        sum += arr[i];
    return sum;
}

static int double_value(int x) {
    return x * 2;
}

static int compute(int a, int b) {
    int x = a + b;
    int y = a - b;
    return double_value(x) + double_value(y);
}

int main(void) {
    int data[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    volatile int r;
    r = sum_array(data, 10);
    r = compute(100, 50);
    return 0;
}
```

``` bash
make 25-optimization.elf
make CFLAGS="-O1 -mthumb -mcpu=cortex-m3 -ffreestanding" 25-optimization.elf
make CFLAGS="-O2 -mthumb -mcpu=cortex-m3 -ffreestanding" 25-optimization.elf
make CFLAGS="-Os -mthumb -mcpu=cortex-m3 -ffreestanding" 25-optimization.elf
```

（改 CFLAGS 时记得补回 `-mthumb -mcpu=cortex-m3`，否则会编出 ARM 指令，M3 跑不了。）

## -O0

``` asm
00000090 <sum_array>:
  90:   b480            push    {r7}
  92:   b085            sub     sp, #20
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6039            str     r1, [r7, #0]
  9a:   2300            movs    r3, #0
  9c:   60fb            str     r3, [r7, #12]
  9e:   2300            movs    r3, #0
  a0:   60bb            str     r3, [r7, #8]
  a2:   e00a            b.n     ba <sum_array+0x2a>
  a4:   68bb            ldr     r3, [r7, #8]
  a6:   009b            lsls    r3, r3, #2
  a8:   687a            ldr     r2, [r7, #4]
  aa:   4413            add     r3, r2
  ac:   681b            ldr     r3, [r3, #0]
  ae:   68fa            ldr     r2, [r7, #12]
  b0:   4413            add     r3, r2
  b2:   60fb            str     r3, [r7, #12]
  b4:   68bb            ldr     r3, [r7, #8]
  b6:   3301            adds    r3, #1
  b8:   60bb            str     r3, [r7, #8]
  ba:   68ba            ldr     r2, [r7, #8]
  bc:   683b            ldr     r3, [r7, #0]
  be:   429a            cmp     r2, r3
  c0:   dbf0            blt.n   a4 <sum_array+0x14>
  c2:   68fb            ldr     r3, [r7, #12]
  c4:   4618            mov     r0, r3
  c6:   3714            adds    r7, #20
  c8:   46bd            mov     sp, r7
  ca:   bc80            pop     {r7}
  cc:   4770            bx      lr

000000ce <double_value>:
  ce:   b480            push    {r7}
  d0:   b083            sub     sp, #12
  d2:   af00            add     r7, sp, #0
  d4:   6078            str     r0, [r7, #4]
  d6:   687b            ldr     r3, [r7, #4]
  d8:   005b            lsls    r3, r3, #1
  da:   4618            mov     r0, r3
  dc:   370c            adds    r7, #12
  de:   46bd            mov     sp, r7
  e0:   bc80            pop     {r7}
  e2:   4770            bx      lr

000000e4 <compute>:
  e4:   b590            push    {r4, r7, lr}
  e6:   b085            sub     sp, #20
  e8:   af00            add     r7, sp, #0
  ea:   6078            str     r0, [r7, #4]
  ec:   6039            str     r1, [r7, #0]
  ee:   687a            ldr     r2, [r7, #4]
  f0:   683b            ldr     r3, [r7, #0]
  f2:   4413            add     r3, r2
  f4:   60fb            str     r3, [r7, #12]
  f6:   687a            ldr     r2, [r7, #4]
  f8:   683b            ldr     r3, [r7, #0]
  fa:   1ad3            subs    r3, r2, r3
  fc:   60bb            str     r3, [r7, #8]
  fe:   68f8            ldr     r0, [r7, #12]
 100:   f7ff ffe5       bl      ce <double_value>
 104:   4604            mov     r4, r0
 106:   68b8            ldr     r0, [r7, #8]
 108:   f7ff ffe1       bl      ce <double_value>
 10c:   4603            mov     r3, r0
 10e:   4423            add     r3, r4
 110:   4618            mov     r0, r3
 112:   3714            adds    r7, #20
 114:   46bd            mov     sp, r7
 116:   bd90            pop     {r4, r7, pc}

00000118 <main>:
 118:   b5b0            push    {r4, r5, r7, lr}
 11a:   b08c            sub     sp, #48 @ 0x30
 11c:   af00            add     r7, sp, #0
 11e:   4b0f            ldr     r3, [pc, #60]   @ (15c <main+0x44>)
 120:   f107 0408       add.w   r4, r7, #8
 124:   461d            mov     r5, r3
 126:   cd0f            ldmia   r5!, {r0, r1, r2, r3}
 128:   c40f            stmia   r4!, {r0, r1, r2, r3}
 12a:   cd0f            ldmia   r5!, {r0, r1, r2, r3}
 12c:   c40f            stmia   r4!, {r0, r1, r2, r3}
 12e:   e895 0003       ldmia.w r5, {r0, r1}
 132:   e884 0003       stmia.w r4, {r0, r1}
 136:   f107 0308       add.w   r3, r7, #8
 13a:   210a            movs    r1, #10
 13c:   4618            mov     r0, r3
 13e:   f7ff ffa7       bl      90 <sum_array>
 142:   4603            mov     r3, r0
 144:   607b            str     r3, [r7, #4]
 146:   2132            movs    r1, #50 @ 0x32
 148:   2064            movs    r0, #100        @ 0x64
 14a:   f7ff ffcb       bl      e4 <compute>
 14e:   4603            mov     r3, r0
 150:   607b            str     r3, [r7, #4]
 152:   2300            movs    r3, #0
 154:   4618            mov     r0, r3
 156:   3730            adds    r7, #48 @ 0x30
 158:   46bd            mov     sp, r7
 15a:   bdb0            pop     {r4, r5, r7, pc}
 15c:   00000160        .word   0x00000160
 160:   00000001        .word   0x00000001
 164:   00000002        .word   0x00000002
 168:   00000003        .word   0x00000003
 16c:   00000004        .word   0x00000004
 170:   00000005        .word   0x00000005
 174:   00000006        .word   0x00000006
 178:   00000007        .word   0x00000007
 17c:   00000008        .word   0x00000008
 180:   00000009        .word   0x00000009
 184:   0000000a        .word   0x0000000a
```

-O0 下一切照本宣科：sum_array 每次迭代都老老实实 `ldr` 数组元素、`lsls r3, r3, #2` 算下标偏移；compute 先把 x、y 存到栈上，再两次 `bl double_value`；main 把 .rodata 里那 10 个常量用 `ldmia/stmia` 拷到栈上的 data[]，再依次调用。指令很碎，但每一句都能对上源码。

## -O1

``` asm
000000a4 <main>:
  a4:   b410            push    {r4}
  a6:   b08d            sub     sp, #52 @ 0x34
  a8:   f10d 0c08       add.w   ip, sp, #8
  ac:   4c0d            ldr     r4, [pc, #52]   @ (e4 <main+0x40>)
  ae:   cc0f            ldmia   r4!, {r0, r1, r2, r3}
  b0:   e8ac 000f       stmia.w ip!, {r0, r1, r2, r3}
  b4:   cc0f            ldmia   r4!, {r0, r1, r2, r3}
  b6:   e8ac 000f       stmia.w ip!, {r0, r1, r2, r3}
  ba:   e894 0003       ldmia.w r4, {r0, r1}
  be:   e88c 0003       stmia.w ip, {r0, r1}
  c2:   ab02            add     r3, sp, #8
  c4:   a80c            add     r0, sp, #48     @ 0x30
  c6:   2200            movs    r2, #0
  c8:   f853 1b04       ldr.w   r1, [r3], #4
  cc:   440a            add     r2, r1
  ce:   4283            cmp     r3, r0
  d0:   d1fa            bne.n   c8 <main+0x24>
  d2:   9201            str     r2, [sp, #4]
  d4:   f44f 73c8       mov.w   r3, #400        @ 0x190
  d8:   9301            str     r3, [sp, #4]
  da:   2000            movs    r0, #0
  dc:   b00d            add     sp, #52 @ 0x34
  de:   bc10            pop     {r4}
  e0:   4770            bx      lr
  e2:   bf00            nop
  e4:   000000e8        .word   0x000000e8
  e8:   00000001        .word   0x00000001
  ec:   00000002        .word   0x00000002
  f0:   00000003        .word   0x00000003
  f4:   00000004        .word   0x00000004
  f8:   00000005        .word   0x00000005
  fc:   00000006        .word   0x00000006
 100:   00000007        .word   0x00000007
 104:   00000008        .word   0x00000008
 108:   00000009        .word   0x00000009
 10c:   0000000a        .word   0x0000000a
```

到 -O1，三个 helper 全被内联进了 main，而且 `compute(100,50)` 的结果在编译期就算出来了：`mov.w r3, #400`（(100+50)*2 + (100-50)*2 = 300 + 100 = 400）。sum_array 也被内联成一个内嵌的小循环（`ldr.w r1,[r3],#4; add r2,r1; cmp; bne`，把 10 个数累加到 r2，结果是 55）。整个文件里已经找不到 sum_array/compute 这些独立函数了。

## -O2

``` asm
000000a4 <main>:
  a4:   b570            push    {r4, r5, r6, lr}
  a6:   2400            movs    r4, #0
  a8:   b08c            sub     sp, #48 @ 0x30
  aa:   4d0e            ldr     r5, [pc, #56]   @ (e4 <main+0x40>)
  ac:   f10d 0e08       add.w   lr, sp, #8
  b0:   cd0f            ldmia   r5!, {r0, r1, r2, r3}
  b2:   e8ae 000f       stmia.w lr!, {r0, r1, r2, r3}
  b6:   cd0f            ldmia   r5!, {r0, r1, r2, r3}
  b8:   e8ae 000f       stmia.w lr!, {r0, r1, r2, r3}
  bc:   e895 0003       ldmia.w r5, {r0, r1}
  c0:   e88e 0003       stmia.w lr, {r0, r1}
  c4:   ae0c            add     r6, sp, #48     @ 0x30
  c6:   f10d 0c08       add.w   ip, sp, #8
  ca:   f85c 3b04       ldr.w   r3, [ip], #4
  ce:   45b4            cmp     ip, r6
  d0:   441c            add     r4, r3
  d2:   d1fa            bne.n   ca <main+0x26>
  d4:   f44f 73c8       mov.w   r3, #400        @ 0x190
  d8:   2000            movs    r0, #0
  da:   9401            str     r4, [sp, #4]
  dc:   9301            str     r3, [sp, #4]
  de:   b00c            add     sp, #48 @ 0x30
  e0:   bd70            pop     {r4, r5, r6, pc}
  e2:   bf00            nop
  e4:   000000e8        .word   0x000000e8
  e8:   00000001        .word   0x00000001
  ec:   00000002        .word   0x00000002
  f0:   00000003        .word   0x00000003
  f4:   00000004        .word   0x00000004
  f8:   00000005        .word   0x00000005
  fc:   00000006        .word   0x00000006
 100:   00000007        .word   0x00000007
 104:   00000008        .word   0x00000008
 108:   00000009        .word   0x00000009
 10c:   0000000a        .word   0x0000000a
```

-O2 和 -O1 的结果很接近，寄存器分配更紧一点：累加器提前初始化成 r4，循环体少了几次搬运，但结构完全一样。

## -Os

``` asm
00000080 <main>:
  80:   b530            push    {r4, r5, lr}
  82:   4d0d            ldr     r5, [pc, #52]   @ (b8 <main+0x38>)
  84:   b08d            sub     sp, #52 @ 0x34
  86:   ac02            add     r4, sp, #8
  88:   cd0f            ldmia   r5!, {r0, r1, r2, r3}
  8a:   c40f            stmia   r4!, {r0, r1, r2, r3}
  8c:   cd0f            ldmia   r5!, {r0, r1, r2, r3}
  8e:   c40f            stmia   r4!, {r0, r1, r2, r3}
  90:   e895 0003       ldmia.w r5, {r0, r1}
  94:   2300            movs    r3, #0
  96:   461a            mov     r2, r3
  98:   e884 0003       stmia.w r4, {r0, r1}
  9c:   a902            add     r1, sp, #8
  9e:   f851 0b04       ldr.w   r0, [r1], #4
  a2:   3201            adds    r2, #1
  a4:   2a0a            cmp     r2, #10
  a6:   4403            add     r3, r0
  a8:   d1f9            bne.n   9e <main+0x1e>
  aa:   9301            str     r3, [sp, #4]
  ac:   2000            movs    r0, #0
  ae:   f44f 73c8       mov.w   r3, #400        @ 0x190
  b2:   9301            str     r3, [sp, #4]
  b4:   b00d            add     sp, #52 @ 0x34
  b6:   bd30            pop     {r4, r5, pc}
  b8:   000000bc        .word   0x000000bc
  bc:   00000001        .word   0x00000001
  c0:   00000002        .word   0x00000002
  c4:   00000003        .word   0x00000003
  c8:   00000004        .word   0x00000004
  cc:   00000005        .word   0x00000005
  d0:   00000006        .word   0x00000006
  d4:   00000007        .word   0x00000007
  d8:   00000008        .word   0x00000008
  dc:   00000009        .word   0x00000009
  e0:   0000000a        .word   0x0000000a
```

-Os 优先代码尺寸，指令最少。它把循环改成了显式计数器版本（`adds r2,#1; cmp r2,#10`），寄存器用得更省，连栈帧的排布都变了。代价是循环控制多一条指令，但换来更短的代码。

## 指令量对比

把整个 ELF（含 startup 的 Reset_Handler）数一遍：

| 优化等级 | 指令条数 |
|---------|---------|
| -O0 | 123 |
| -O1 | 57 |
| -O2 | 58 |
| -Os | 42 |

从 -O0 到 -O1 直接砍掉一半多，主要就来自“内联 + 常量折叠 + 变量留寄存器”。-O2 比 -O1 略多几条，是因为它更激进地展开/重排，指令数不一定最少，但执行更快；真正拼尺寸要用 -Os。

# 尾调用优化

尾调用优化（TCO）指的是：如果一个函数的最后一步是 `return f(x);`，那么 f 返回之后本函数也没别的事可做了，于是没必要再压一个栈帧——编译器可以把 `bl f; pop {pc}` 直接换成一条 `b f`。

``` c
/*
 * 观察目标: 尾调用优化
 *
 * 对比:
 *   make 26-tail-call.elf                → -O0, 无尾调用优化
 *   make CFLAGS="-O2" 26-tail-call.elf   → -O2, 有尾调用优化
 *
 * 关注点:
 *   1. 无优化: 尾部调用也 PUSH {LR} → BL → POP {PC}, 栈增长
 *   2. 优化后: 尾部调用变成 B (直接跳转), 不消耗栈
 *   3. 尾递归 → 循环 (汇编上看到 B 跳回自身)
 */

/* 尾递归: 最后一步是递归调用, 编译器可优化为循环 */
static int tail_factorial(int n, int acc) {
    if (n <= 1)
        return acc;
    return tail_factorial(n - 1, acc * n);
}

/* 非尾递归: 最后一步是乘法而非递归调用, 无法优化 */
static int factorial(int n) {
    if (n <= 1)
        return 1;
    return n * factorial(n - 1);
}

/* 尾调用: 直接 return 另一个函数的结果 */
static int helper(int x) {
    return x + 1;
}

static int tail_call(int x) {
    return helper(x);     /* 可优化为 B helper (不新建栈帧) */
}

/* 非尾调用: 返回前还有操作 */
static int non_tail_call(int x) {
    int r = helper(x);
    return r + 1;
}

int main(void) {
    volatile int r;
    r = factorial(5);
    r = tail_factorial(5, 1);
    r = tail_call(42);
    r = non_tail_call(42);
    return 0;
}
```

## -O0：全部老老实实调用

``` asm
00000090 <tail_factorial>:
  90:   b580            push    {r7, lr}
  92:   b082            sub     sp, #8
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6039            str     r1, [r7, #0]
  9a:   687b            ldr     r3, [r7, #4]
  9c:   2b01            cmp     r3, #1
  9e:   dc01            bgt.n   a4 <tail_factorial+0x14>
  a0:   683b            ldr     r3, [r7, #0]
  a2:   e009            b.n     b8 <tail_factorial+0x28>
  a4:   687b            ldr     r3, [r7, #4]
  a6:   1e58            subs    r0, r3, #1
  a8:   683b            ldr     r3, [r7, #0]
  aa:   687a            ldr     r2, [r7, #4]
  ac:   fb02 f303       mul.w   r3, r2, r3
  b0:   4619            mov     r1, r3
  b2:   f7ff ffed       bl      90 <tail_factorial>
  b6:   4603            mov     r3, r0
  b8:   4618            mov     r0, r3
  ba:   3708            adds    r7, #8
  bc:   46bd            mov     sp, r7
  be:   bd80            pop     {r7, pc}

000000c0 <factorial>:
  c0:   b580            push    {r7, lr}
  c2:   b082            sub     sp, #8
  c4:   af00            add     r7, sp, #0
  c6:   6078            str     r0, [r7, #4]
  c8:   687b            ldr     r3, [r7, #4]
  ca:   2b01            cmp     r3, #1
  cc:   dc01            bgt.n   d2 <factorial+0x12>
  ce:   2301            movs    r3, #1
  d0:   e008            b.n     e4 <factorial+0x24>
  d2:   687b            ldr     r3, [r7, #4]
  d4:   3b01            subs    r3, #1
  d6:   4618            mov     r0, r3
  d8:   f7ff fff2       bl      c0 <factorial>
  dc:   4602            mov     r2, r0
  de:   687b            ldr     r3, [r7, #4]
  e0:   fb02 f303       mul.w   r3, r2, r3
  e4:   4618            mov     r0, r3
  e6:   3708            adds    r7, #8
  e8:   46bd            mov     sp, r7
  ea:   bd80            pop     {r7, pc}

00000102 <tail_call>:
 102:   b580            push    {r7, lr}
 104:   b082            sub     sp, #8
 106:   af00            add     r7, sp, #0
 108:   6078            str     r0, [r7, #4]
 10a:   6878            ldr     r0, [r7, #4]
 10c:   f7ff ffee       bl      ec <helper>
 110:   4603            mov     r3, r0
 112:   4618            mov     r0, r3
 114:   3708            adds    r7, #8
 116:   46bd            mov     sp, r7
 118:   bd80            pop     {r7, pc}

0000011a <non_tail_call>:
 11a:   b580            push    {r7, lr}
 11c:   b084            sub     sp, #16
 11e:   af00            add     r7, sp, #0
 120:   6078            str     r0, [r7, #4]
 122:   6878            ldr     r0, [r7, #4]
 124:   f7ff ffe2       bl      ec <helper>
 128:   60f8            str     r0, [r7, #12]
 12a:   68fb            ldr     r3, [r7, #12]
 12c:   3301            adds    r3, #1
 12e:   4618            mov     r0, r3
 130:   3710            adds    r7, #16
 132:   46bd            mov     sp, r7
 134:   bd80            pop     {r7, pc}
```

-O0 不做任何 TCO。tail_factorial 结尾是 `bl tail_factorial`（又一次递归调用）然后才 `pop {r7, pc}` 返回——栈帧一层层压，虽然它本质上等价于一个循环。tail_call 也一样：`bl helper` 之后还要 `pop {r7, pc}` 才能真正返回。

## -O2：常量折叠先行

``` asm
000000a4 <main>:
  a4:   2378            movs    r3, #120        @ 0x78
  a6:   212b            movs    r1, #43 @ 0x2b
  a8:   222c            movs    r2, #44 @ 0x2c
  aa:   2000            movs    r0, #0
  ac:   b082            sub     sp, #8
  ae:   9301            str     r3, [sp, #4]
  b0:   9301            str     r3, [sp, #4]
  b2:   9101            str     r1, [sp, #4]
  b4:   9201            str     r2, [sp, #4]
  b6:   b002            add     sp, #8
  b8:   4770            bx      lr
  ba:   bf00            nop
```

这里出现了和上一节类似的“意外”：因为 main 里所有参数都是编译期常量，-O2 把四个函数全内联 + 常量折叠了——factorial(5)=120、tail_factorial(5,1)=120、tail_call(42)=43、non_tail_call(42)=44。最后 main 里只剩一串 movs/str。尾调用优化“做没做”已经看不出来了。

## 拓展：让参数在编译期不可知

要单独观察 TCO，就得让参数编译期不知道。把 helper 和两个调用者都标上 `noinline`，参数从一个 volatile 全局来：

``` c
volatile int gx;
__attribute__((noinline)) int helper(int x) { return x + 1; }
__attribute__((noinline)) int tail_call(int x) { return helper(x); }
__attribute__((noinline)) int non_tail_call(int x) { int r = helper(x); return r + 1; }
int main(void) { return tail_call(gx) + non_tail_call(gx); }
```

同样用 -O2 编，再看：

``` asm
000000a4 <helper>:
  a4:   3001            adds    r0, #1
  a6:   4770            bx      lr

000000a8 <tail_call>:
  a8:   f7ff bffc       b.w     a4 <helper>

000000ac <non_tail_call>:
  ac:   b508            push    {r3, lr}
  ae:   f7ff fff9       bl      a4 <helper>
  b2:   3001            adds    r0, #1
  b4:   bd08            pop     {r3, pc}
  b6:   bf00            nop
```

这下就清楚了：
- **tail_call**：`b.w helper`——直接跳过去，不压栈、不碰 lr。因为 helper 返回后 tail_call 没有任何事要做，栈帧可以原地丢弃。
- **non_tail_call**：`push {r3, lr}` … `bl helper` … `adds r0, #1` … `pop {r3, pc}`——它还得在返回值上加 1，所以必须先存 lr、老老实实走一次完整调用。

这就是 TCO 的判断标准：**返回之后还有没有活干**。没有，就是 `b`；有，就必须 `bl` + 保存返回地址。

# 死代码消除与内联

``` c
/*
 * 观察目标: 死代码消除与 inline 效果
 *
 * 对比:
 *   make 27-dead-code.elf              → -O0, 保留所有代码
 *   make CFLAGS="-O2" 27-dead-code.elf → -O2, 消除无用代码
 *
 * 关注点:
 *   1. 定义了但从未调用的函数 → -O2 下整个函数被移除
 *   2. 计算结果从未使用的表达式 → 被消除
 *   3. 条件永远为真的 if → 分支消除
 *   4. inline 函数: 无调用开销但增加代码体积
 */

static int never_called(void) {
    return 42;           /* -O2 下整个函数消失 */
}

static int dead_code(int x) {
    volatile int a = x * x; /* 计算结果从未使用 → 加 volatile 阻止消除 */
    (void)a;
    int b = x + 1;
    return b;            /* -O2: a 的计算仍被消除 */
}

static int dead_condition(int x) {
    if (0)               /* 恒假, 整个分支被消除 */
        return 100;
    return x;
}

static inline int add_inline(int a, int b) {
    return a + b;
}

int main(void) {
    volatile int r;
    r = dead_code(10);
    r = dead_condition(20);
    r = add_inline(3, 4);    /* -O2: 内联为 MOV + ADDS */
    return 0;
}
```

## -O0

``` asm
00000090 <never_called>:
  90:   b480            push    {r7}
  92:   af00            add     r7, sp, #0
  94:   232a            movs    r3, #42 @ 0x2a
  96:   4618            mov     r0, r3
  98:   46bd            mov     sp, r7
  9a:   bc80            pop     {r7}
  9c:   4770            bx      lr

0000009e <dead_code>:
  9e:   b480            push    {r7}
  a0:   b085            sub     sp, #20
  a2:   af00            add     r7, sp, #0
  a4:   6078            str     r0, [r7, #4]
  a6:   687b            ldr     r3, [r7, #4]
  a8:   fb03 f303       mul.w   r3, r3, r3
  ac:   60bb            str     r3, [r7, #8]
  ae:   68bb            ldr     r3, [r7, #8]
  b0:   687b            ldr     r3, [r7, #4]
  b2:   3301            adds    r3, #1
  b4:   60fb            str     r3, [r7, #12]
  b6:   68fb            ldr     r3, [r7, #12]
  b8:   4618            mov     r0, r3
  ba:   3714            adds    r7, #20
  bc:   46bd            mov     sp, r7
  be:   bc80            pop     {r7}
  c0:   4770            bx      lr

000000c2 <dead_condition>:
  c2:   b480            push    {r7}
  c4:   b083            sub     sp, #12
  c6:   af00            add     r7, sp, #0
  c8:   6078            str     r0, [r7, #4]
  ca:   687b            ldr     r3, [r7, #4]
  cc:   4618            mov     r0, r3
  ce:   370c            adds    r7, #12
  d0:   46bd            mov     sp, r7
  d2:   bc80            pop     {r7}
  d4:   4770            bx      lr

000000d6 <add_inline>:
  d6:   b480            push    {r7}
  d8:   b083            sub     sp, #12
  da:   af00            add     r7, sp, #0
  dc:   6078            str     r0, [r7, #4]
  de:   6039            str     r1, [r7, #0]
  e0:   687a            ldr     r2, [r7, #4]
  e2:   683b            ldr     r3, [r7, #0]
  e4:   4413            add     r3, r2
  e6:   4618            mov     r0, r3
  e8:   370c            adds    r7, #12
  ea:   46bd            mov     sp, r7
  ec:   bc80            pop     {r7}
  ee:   4770            bx      lr
```

-O0 下：never_called 明明从没人调用，照样编出来了；add_inline 虽然写了 `inline`，也还是编成一个独立函数（-O0 不内联）。

两个有意思的地方：
- **dead_code**：`volatile int a = x * x;` 后面 a 根本没被用，但 volatile 逼着编译器保留了这次 `mul.w` + `str`——否则这一整句都会被消掉。
- **dead_condition**：`if (0) return 100;` 这种恒假分支，**连 -O0 都直接消掉了**——汇编里只剩 `return x`，没有 cmp、没有跳转。这说明“恒假条件消除”不走优化管线，在很早就做了。

## -O2

``` asm
000000a4 <main>:
  a4:   b410            push    {r4}
  a6:   2464            movs    r4, #100        @ 0x64
  a8:   210b            movs    r1, #11
  aa:   2214            movs    r2, #20
  ac:   2307            movs    r3, #7
  ae:   2000            movs    r0, #0
  b0:   b083            sub     sp, #12
  b2:   9401            str     r4, [sp, #4]
  b4:   9c01            ldr     r4, [sp, #4]
  b6:   9100            str     r1, [sp, #0]
  b8:   9200            str     r2, [sp, #0]
  ba:   9300            str     r3, [sp, #0]
  bc:   b003            add     sp, #12
  be:   bc10            pop     {r4}
  c0:   4770            bx      lr
  c2:   bf00            nop
```

-O2 下除了 main，所有函数都消失了：
- never_called 被整个删除；
- dead_code / dead_condition / add_inline 全部内联 + 折叠成常量：main 里就是 `movs r4, #100`（x*x）、`movs r1, #11`（x+1）、`movs r2, #20`、`movs r3, #7`，然后往 volatile r 里存。

整个 ELF 从 -O0 的 97 条指令缩到 -O2 的 50 条。这就是“死代码消除 + 内联 + 常量传播”叠在一起的威力：源码里那些函数名，在优化后的汇编里一个字都剩不下。

顺带一提：在 -O2 的 main 里，每次 `str` 前面都先 `movs` 一个常量——看起来“多此一举”，其实是 volatile 强制的结果（它不能被合并成一次写）。
# 指针强转与越界访问

前面基本都在讲“规范的 C”。从这里开始往后，是常见 C 错误在 CPU 眼里的样子。头一个就是指针强转：`uint16_t*` 和 `uint32_t*` 互转，是很多隐蔽 bug 的温床。

``` c
/*
 * 观察目标: 指针类型强转导致的对齐访问与 OOB
 *
 * 编译: make 30-pointer-cast.elf
 * 反汇编: arm-none-eabi-objdump -d 30-pointer-cast.elf
 * GDB:  make qemu-gdb-30-pointer-cast
 *   在 GDB 中设断点观察每次 LDR 的地址
 *
 * 背景: uint16* → uint32* 强转是两个常见问题的温床
 *
 * 问题 1 - 对齐: uint16 数组按 2 字节对齐, 强转 uint32* 后如果从奇数
 *                位置读取, 产生非对齐访问。Cortex-M3 默认不开启 UNALIGN_TRP
 *                时支持非对齐 LDR, 但 LDREX/LDM 不支持, 性能也差。
 *
 * 问题 2 - OOB: 从 &arr[n-1] 处读 4 字节, 其中 2 字节越界。
 *               汇编上只是 LDR from addr, CPU 不感知"越界"概念。
 *
 * 问题 3 - 严格别名: uint16* 和 uint32* 指向同一内存,
 *               编译器假设它们不别名, 可能生成错误代码顺序。
 */

#include <stdint.h>

static uint16_t arr16[4] = {0x0001, 0x0002, 0x0003, 0x0004};

/* OOB: 指针强转导致的越界读 */
static uint32_t oob_read(void) {
    uint32_t *p32 = (uint32_t *)&arr16[3];  /* arr16[3] 还剩 2 字节 */
    return *p32;  /* 读 4 字节: arr16[3] + 后面的 2 个未知字节 */
}

/* 对齐: 非对齐地址的 uint32 读取 */
static uint32_t unaligned_read(void) {
    uint8_t *base = (uint8_t *)arr16;
    uint32_t *p32 = (uint32_t *)(base + 1);  /* 奇数地址 → 非对齐 */
    return *p32;
}

/* 严格别名: 两个不同类型的指针指向同一块内存 */
static uint32_t strict_alias_test(void) {
    uint32_t val = 0x12345678;
    uint16_t *p16 = (uint16_t *)&val;
    uint32_t a = p16[0];             /* 低 16 位 */
    uint32_t b = p16[1];             /* 高 16 位 */
    return a + b;
}

int main(void) {
    volatile uint32_t r;
    r = oob_read();
    r = unaligned_read();
    r = strict_alias_test();
    return 0;
}
```

## 越界读取

``` asm
00000090 <oob_read>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   4b04            ldr     r3, [pc, #16]   @ (a8 <oob_read+0x18>)
  98:   607b            str     r3, [r7, #4]
  9a:   687b            ldr     r3, [r7, #4]
  9c:   681b            ldr     r3, [r3, #0]
  9e:   4618            mov     r0, r3
  a0:   370c            adds    r7, #12
  a2:   46bd            mov     sp, r7
  a4:   bc80            pop     {r7}
  a6:   4770            bx      lr
  a8:   20000006        .word   0x20000006
```

oob_read 拿的是 `&arr16[3]`（arr16 只有 4 个 uint16），然后当 uint32 读 4 字节。汇编上，先 `ldr r3, [pc, #16]` 取个字面量——对应 `&arr16[3]` 的地址 0x20000006，然后 `ldr r3, [r3, #0]`，一条普通的 4 字节读。

CPU 完全不知道“这里只剩 2 字节了”，它只会照做：把这一格和后面那一格一起读进来。所谓“越界”，是 C 语言层面的概念，指令集里并不存在——对 CPU 来说，就是从一个对齐或没对齐的地址读 4 字节而已。

## 非对齐读取

``` asm
000000ac <unaligned_read>:
  ac:   b480            push    {r7}
  ae:   b083            sub     sp, #12
  b0:   af00            add     r7, sp, #0
  b2:   4b06            ldr     r3, [pc, #24]   @ (cc <unaligned_read+0x20>)
  b4:   607b            str     r3, [r7, #4]
  b6:   687b            ldr     r3, [r7, #4]
  b8:   3301            adds    r3, #1
  ba:   603b            str     r3, [r7, #0]
  bc:   683b            ldr     r3, [r7, #0]
  be:   681b            ldr     r3, [r3, #0]
  c0:   4618            mov     r0, r3
  c2:   370c            adds    r7, #12
  c4:   46bd            mov     sp, r7
  c6:   bc80            pop     {r7}
  c8:   4770            bx      lr
  ca:   bf00            nop
  cc:   20000000        .word   0x20000000
```

`base + 1` 得到一个奇数地址，再当 uint32 读，同样只是一条 `ldr`。Cortex-M3 在默认配置（CCR.UNALIGN_TRP = 0）下允许普通 LDR/STR 做非对齐访问，所以这里不会炸，只是慢——硬件要把一次非对齐访问拆成两次总线访问。但如果程序里开了 `SCB->CCR |= SCB_CCR_UNALIGN_TRP_Msk`，同样的代码就会触发 UsageFault。

## 严格别名（-O0 版）

``` asm
000000d0 <strict_alias_test>:
  d0:   b480            push    {r7}
  d2:   b085            sub     sp, #20
  d4:   af00            add     r7, sp, #0
  d6:   4b09            ldr     r3, [pc, #36]   @ (fc <strict_alias_test+0x2c>)
  d8:   603b            str     r3, [r7, #0]
  da:   463b            mov     r3, r7
  dc:   60fb            str     r3, [r7, #12]
  de:   68fb            ldr     r3, [r7, #12]
  e0:   881b            ldrh    r3, [r3, #0]
  e2:   60bb            str     r3, [r7, #8]
  e4:   68fb            ldr     r3, [r7, #12]
  e6:   3302            adds    r3, #2
  e8:   881b            ldrh    r3, [r3, #0]
  ea:   607b            str     r3, [r7, #4]
  ec:   68ba            ldr     r2, [r7, #8]
  ee:   687b            ldr     r3, [r7, #4]
  f0:   4413            add     r3, r2
  f2:   4618            mov     r0, r3
  f4:   3714            adds    r7, #20
  f6:   46bd            mov     sp, r7
  f8:   bc80            pop     {r7}
  fa:   4770            bx      lr
  fc:   12345678        .word   0x12345678
```

把 `uint32_t*` 当 `uint16_t*` 用，读低 16 位和高 16 位，汇编里就是两次 `ldrh`（`ldrh r3, [r3, #0]` 和 `ldrh r3, [r3, #2]`）。在 -O0 下这么写没问题。但一旦开优化，这就撞上严格别名规则了——见下一个实验。

# 严格别名违规

严格别名规则说：不同类型（char 除外）的指针不会指向同一块内存。编译器会拿这条规则当“承诺”，据此优化。这个实验就是把承诺打破，看会怎样。

``` c
/*
 * 观察目标: 严格别名违规 —— 编译器基于"不别名假设"生成错误代码
 *
 * 编译: make 31-strict-aliasing.elf
 * 对比: make CFLAGS="-O2 -fno-strict-aliasing" 31-strict-aliasing.elf
 *       make CFLAGS="-O2" 31-strict-aliasing.elf
 *
 * 关注点:
 *   1. C 标准要求不同类型指针不指向同一内存 (char* 除外)
 *   2. 编译器利用此假设优化: 认为 *pi 和 *ps 不会互相影响
 *   3. -O2 下, 如果违反规则, 读到的值可能不符合预期
 *   4. -fno-strict-aliasing 关闭此优化, 结果正确但性能降低
 *   5. 经典体现: uint16_t* 和 uint32_t* 指向同一地址
 */

#include <stdint.h>

static uint32_t strict_alias_violation(uint32_t *pi, uint16_t *ps) {
    *pi = 0x12345678;
    *ps = 0xAAAA;       /* 编译器认为 ps 和 pi 不别名, 重排后可能先执行 */
    return *pi;          /* 预期 0x1234AAAA, 但可能直接返回 0x12345678 */
}

static uint32_t safe_via_char(uint32_t *pi, uint16_t *ps) {
    /* 通过 char* 做类型双关是合法的 */
    *pi = 0x12345678;
    char *pc = (char *)pi;
    pc[0] = 0xAA; pc[1] = 0xAA;
    return *pi;
}

int main(void) {
    uint32_t val = 0;
    volatile uint32_t r;

    r = strict_alias_violation(&val, (uint16_t *)&val);
    r = safe_via_char(&val, (uint16_t *)&val);
    return 0;
}
```

``` bash
make CFLAGS="-O2 -mthumb -mcpu=cortex-m3 -ffreestanding" 31-strict-aliasing.elf
make CFLAGS="-O2 -fno-strict-aliasing -mthumb -mcpu=cortex-m3 -ffreestanding" 31-strict-aliasing.elf
```

## -O2

``` asm
000000a4 <main>:
  a4:   2000            movs    r0, #0
  a6:   4a03            ldr     r2, [pc, #12]   @ (b4 <main+0x10>)
  a8:   4b03            ldr     r3, [pc, #12]   @ (b8 <main+0x14>)
  aa:   b082            sub     sp, #8
  ac:   9201            str     r2, [sp, #4]
  ae:   9301            str     r3, [sp, #4]
  b0:   b002            add     sp, #8
  b2:   4770            bx      lr
  b4:   12345678        .word   0x12345678
  b8:   1234aaaa        .word   0x1234aaaa
```

-O2 把两个函数都内联进了 main，最后只剩两条常量：`0x12345678` 和 `0x1234aaaa`，按顺序写进 volatile r。对照源码：
- `strict_alias_violation(&val, (uint16_t*)&val)`：先 `*pi = 0x12345678`，再 `*ps = 0xAAAA`，然后 `return *pi`。按内存直觉，第二次写会把低 16 位改成 0xAAAA，应该返回 0x1234AAAA。但编译器依据“pi 和 ps 不别名”的假设，认为 `*ps` 的写不会影响 `*pi`，于是把 `return *pi` **直接折叠成了刚才写进去的 0x12345678**——读到了过期值。汇编里就是第一条 `str` 写的那个 0x12345678。
- `safe_via_char(&val, (uint16_t*)&val)`：用 char* 逐字节改，char 是严格别名规则的例外，编译器不敢乱来，老老实实返回了正确的 0x1234AAAA（第二条 `str` 的值）。

所以同一个 main 里，两次“目的一样”的操作，一次拿到 0x12345678（错的），一次拿到 0x1234AAAA（对的）。

## -O2 -fno-strict-aliasing

``` asm
000000a4 <main>:
  a4:   2000            movs    r0, #0
  a6:   4b03            ldr     r3, [pc, #12]   @ (b4 <main+0x10>)
  a8:   b082            sub     sp, #8
  aa:   9301            str     r3, [sp, #4]
  ac:   9301            str     r3, [sp, #4]
  ae:   b002            add     sp, #8
  b0:   4770            bx      lr
  b2:   bf00            nop
  b4:   1234aaaa        .word   0x1234aaaa
```

关掉严格别名假设后，编译器必须假设两次写可能互相影响，于是两处都变成 0x1234AAAA：字面量池里只剩一个 `0x1234aaaa`，两条 `str` 写的是同一个寄存器。结果正确了，代价是丢掉了优化机会——这就是严格别名规则“两头都得罪”的地方。

工程里最常见的踩法不是手写类型双关，而是“用 uint16_t* 和 uint32_t* 访问同一块协议缓冲区 / 硬件寄存器映射”。一旦编译器和代码对“谁跟谁别名”的理解不一致，就会冒出这种极难查的错。

# 整数溢出与回绕

C 里无符号溢出是明确定义的（模 2^N 回绕），有符号溢出却是未定义行为。CPU 不管这一套——它只是做二进制加法，顺手把标志位摆好。这一节看看两种溢出在汇编上长什么样。

``` c
/*
 * 观察目标: 整数溢出与回绕 —— CPU 自检测但 C 标准不保证
 *
 * 编译: make 32-integer-overflow.elf
 * 反汇编: arm-none-eabi-objdump -d 32-integer-overflow.elf
 *
 * 关注点:
 *   1. INT_MAX + 1: ADDS 运算, 结果回绕到 INT_MIN (二进制: 0x7FFFFFFF+1 = 0x80000000)
 *   2. 无符号回绕是 C 标准定义行为 (UINT_MAX + 1 = 0)
 *   3. 有符号溢出是 C 未定义行为 (编译器可假设不发生)
 *   4. APSR 寄存器中的 V/C flag 由 ADDS/SUBS 设置, 但 C 不检查它
 *   5. __aeabi_idiv 内部会做溢出检查
 */

#include <limits.h>

static int signed_overflow(void) {
    int a = INT_MAX;
    return a + 1;        /* 回绕: 0x80000000 即 INT_MIN */
}

static unsigned int unsigned_wrap(void) {
    unsigned int u = 0;
    return u - 1;        /* 回绕: 0xFFFFFFFF 即 UINT_MAX */
}

static int overflow_in_loop(void) {
    /* 经典错误: 有符号 i 可能溢出 */
    int i;
    for (i = 0; i >= 0; i++)
        if (i == INT_MAX) break;
    return i;            /* i = INT_MAX → i++ → 溢出 */
}

static int detect_overflow(void) {
    int a = INT_MAX;
    int b = 1;
    int result = a + b;
    /* 检查 V flag 理论上可行, 但 C 无法直接获取 */
    return result;
}

int main(void) {
    volatile int r;
    r = signed_overflow();
    r = unsigned_wrap();
    r = overflow_in_loop();
    r = detect_overflow();
    return 0;
}
```

## 有符号溢出

``` asm
00000090 <signed_overflow>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   f06f 4300       mvn.w   r3, #2147483648 @ 0x80000000
  9a:   607b            str     r3, [r7, #4]
  9c:   687b            ldr     r3, [r7, #4]
  9e:   3301            adds    r3, #1
  a0:   4618            mov     r0, r3
  a2:   370c            adds    r7, #12
  a4:   46bd            mov     sp, r7
  a6:   bc80            pop     {r7}
  a8:   4770            bx      lr

000000aa <unsigned_wrap>:
  aa:   b480            push    {r7}
  ac:   b083            sub     sp, #12
  ae:   af00            add     r7, sp, #0
  b0:   2300            movs    r3, #0
  b2:   607b            str     r3, [r7, #4]
  b4:   687b            ldr     r3, [r7, #4]
  b6:   3b01            subs    r3, #1
  b8:   4618            mov     r0, r3
  ba:   370c            adds    r7, #12
  bc:   46bd            mov     sp, r7
  be:   bc80            pop     {r7}
  c0:   4770            bx      lr
```

`int a = INT_MAX; return a + 1;` 编译出来是：`mvn.w r3, #0x80000000`（这个花招得到 0x7FFFFFFF = INT_MAX），然后 `adds r3, #1`。就这么一条 `adds`——它会算出 0x80000000，并把 APSR 的 V（溢出）标志置 1，但 C 代码根本不看标志位，直接把它当 int 返回了（也就是 INT_MIN）。

所以“溢出”在 CPU 层不是异常，只是一次普通加法外加一个没人理会的标志位。有符号溢出之所以危险，恰恰是因为编译器有权假设它“不会发生”，从而做出各种出乎意料的优化。

对比 `unsigned u = 0; return u - 1;`：`subs r3, #1`，得到 0xFFFFFFFF。无符号回绕是 C 标准保证的，这段代码完全合法、可移植。两边生成的指令一模一样，区别只在“C 标准是否背书”。

## 循环里的溢出

``` asm
000000c2 <overflow_in_loop>:
  c2:   b480            push    {r7}
  c4:   b083            sub     sp, #12
  c6:   af00            add     r7, sp, #0
  c8:   2300            movs    r3, #0
  ca:   607b            str     r3, [r7, #4]
  cc:   e007            b.n     de <overflow_in_loop+0x1c>
  ce:   687b            ldr     r3, [r7, #4]
  d0:   f06f 4200       mvn.w   r2, #2147483648 @ 0x80000000
  d4:   4293            cmp     r3, r2
  d6:   d006            beq.n   e6 <overflow_in_loop+0x24>
  d8:   687b            ldr     r3, [r7, #4]
  da:   3301            adds    r3, #1
  dc:   607b            str     r3, [r7, #4]
  de:   687b            ldr     r3, [r7, #4]
  e0:   2b00            cmp     r3, #0
  e2:   daf4            bge.n   ce <overflow_in_loop+0xc>
  e4:   e000            b.n     e8 <overflow_in_loop+0x26>
  e6:   bf00            nop
  e8:   687b            ldr     r3, [r7, #4]
  ea:   4618            mov     r0, r3
  ec:   370c            adds    r7, #12
  ee:   46bd            mov     sp, r7
  f0:   bc80            pop     {r7}
  f2:   4770            bx      lr

000000f4 <detect_overflow>:
  f4:   b480            push    {r7}
  f6:   b085            sub     sp, #20
  f8:   af00            add     r7, sp, #0
  fa:   f06f 4300       mvn.w   r3, #2147483648 @ 0x80000000
  fe:   60fb            str     r3, [r7, #12]
 100:   2301            movs    r3, #1
 102:   60bb            str     r3, [r7, #8]
 104:   68fa            ldr     r2, [r7, #12]
 106:   68bb            ldr     r3, [r7, #8]
 108:   4413            add     r3, r2
 10a:   607b            str     r3, [r7, #4]
 10c:   687b            ldr     r3, [r7, #4]
 10e:   4618            mov     r0, r3
 110:   3714            adds    r7, #20
 112:   46bd            mov     sp, r7
 114:   bc80            pop     {r7}
 116:   4770            bx      lr
```

overflow_in_loop 里那句 `if (i == INT_MAX) break;` 确实起了作用，汇编里能清楚地看到：`cmp r3, #0; bge` 是循环条件（有符号比较），循环体内又用 `mvn.w r2, #0x80000000; cmp r3, r2; beq` 判断是否到达 INT_MAX 并跳出。也就是说这个循环被显式保护住了，不会真溢出；把 break 那句删掉，`i++` 才会从 INT_MAX 回绕成 INT_MIN 然后继续。

detect_overflow 同样只是一条 `adds`。源码注释说“理论上可以查 V 标志，但 C 无法直接获取”——确实如此，标准 C 里没有访问 APSR 的手段。真要在 C 层检测加法溢出，只能写成 `if (a > INT_MAX - b)` 这种不看标志位的代数判断。

## 小结

- 无符号回绕：定义行为，`adds/subs` 照常算。
- 有符号溢出：CPU 也只是算，V 标志悄悄置位，但 C 层拿不到、也不检查；编译器还会趁机做优化。
# 有符号与无符号比较

`-1 > 5u` 为什么是 true？因为比较时 int 被转成了 unsigned：-1 变成 0xFFFFFFFF，当然比 5 大。这一节看编译器怎么用条件码把这种差异体现出来。

``` c
/*
 * 观察目标: 有符号 vs 无符号比较的陷阱
 *
 * 编译: make 33-signed-compare.elf
 * 反汇编: arm-none-eabi-objdump -d 33-signed-compare.elf
 *
 * 关注点:
 *   1. 有符号比较: CMP + BGT/BLT/BGE/BLE (有符号条件)
 *   2. 无符号比较: CMP + BHI/BLO/BHS/BLS (无符号条件)
 *   3. 混用时: int i vs unsigned int len → 隐式类型转换, i 变成无符号
 *   4. 经典 bug: for (i = 0; i < len; i++) 当 len 为 unsigned 且 i 为 signed
 *      → 无符号比较, 正常工作。但 if (i < len) 中 i=-1 时, -1 变成 0xFFFFFFFF
 */

static int signed_compare(int a, int b) {
    if (a > b) return 1;
    return -1;
}

static int unsigned_compare(unsigned int a, unsigned int b) {
    if (a > b) return 1;
    return -1;
}

static int mixed_compare(int a, unsigned int b) {
    /* a 被隐式转换为 unsigned int */
    if (a > b) return 1;    /* a=-1 → 0xFFFFFFFF > b, 永远为真! */
    return -1;
}

static int classic_bug(void) {
    unsigned int len = 5;
    int i;
    /* 经典 bug: for 倒序遍历 */
    for (i = len - 2; i < len; i--) {
        if (i < 0)          /* i 被转成 unsigned, 永不 < 0 */
            break;
    }
    return i;
}

int main(void) {
    volatile int r;
    r = signed_compare(10, 20);
    r = unsigned_compare(10, 20);
    r = mixed_compare(-1, 5);
    r = classic_bug();
    return 0;
}
```

## 有符号比较

``` asm
00000090 <signed_compare>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   6078            str     r0, [r7, #4]
  98:   6039            str     r1, [r7, #0]
  9a:   687a            ldr     r2, [r7, #4]
  9c:   683b            ldr     r3, [r7, #0]
  9e:   429a            cmp     r2, r3
  a0:   dd01            ble.n   a6 <signed_compare+0x16>
  a2:   2301            movs    r3, #1
  a4:   e001            b.n     aa <signed_compare+0x1a>
  a6:   f04f 33ff       mov.w   r3, #4294967295 @ 0xffffffff
  aa:   4618            mov     r0, r3
  ac:   370c            adds    r7, #12
  ae:   46bd            mov     sp, r7
  b0:   bc80            pop     {r7}
  b2:   4770            bx      lr
```

`signed_compare(a, b)` 的 `if (a > b) return 1; return -1;` 编译成 `cmp r2, r3; ble`（ble = 有符号“小于等于”）。有符号比较用 blt/ble/bgt/bge 这一组条件码。

## 无符号比较

``` asm
000000b4 <unsigned_compare>:
  b4:   b480            push    {r7}
  b6:   b083            sub     sp, #12
  b8:   af00            add     r7, sp, #0
  ba:   6078            str     r0, [r7, #4]
  bc:   6039            str     r1, [r7, #0]
  be:   687a            ldr     r2, [r7, #4]
  c0:   683b            ldr     r3, [r7, #0]
  c2:   429a            cmp     r2, r3
  c4:   d901            bls.n   ca <unsigned_compare+0x16>
  c6:   2301            movs    r3, #1
  c8:   e001            b.n     ce <unsigned_compare+0x1a>
  ca:   f04f 33ff       mov.w   r3, #4294967295 @ 0xffffffff
  ce:   4618            mov     r0, r3
  d0:   370c            adds    r7, #12
  d2:   46bd            mov     sp, r7
  d4:   bc80            pop     {r7}
  d6:   4770            bx      lr
```

一模一样的写法，参数换成 unsigned 之后条件码变成 `bls`（无符号“小于等于”）。所以有符号和无符号的差别，在汇编层就是**选了哪一组条件码**。

## 混合比较的陷阱

``` asm
000000d8 <mixed_compare>:
  d8:   b480            push    {r7}
  da:   b083            sub     sp, #12
  dc:   af00            add     r7, sp, #0
  de:   6078            str     r0, [r7, #4]
  e0:   6039            str     r1, [r7, #0]
  e2:   687b            ldr     r3, [r7, #4]
  e4:   683a            ldr     r2, [r7, #0]
  e6:   429a            cmp     r2, r3
  e8:   d201            bcs.n   ee <mixed_compare+0x16>
  ea:   2301            movs    r3, #1
  ec:   e001            b.n     f2 <mixed_compare+0x1a>
  ee:   f04f 33ff       mov.w   r3, #4294967295 @ 0xffffffff
  f2:   4618            mov     r0, r3
  f4:   370c            adds    r7, #12
  f6:   46bd            mov     sp, r7
  f8:   bc80            pop     {r7}
  fa:   4770            bx      lr
```

`mixed_compare(int a, unsigned b)` 里的 `a > b`：因为一边是 unsigned，a 被隐式转成 unsigned，比较随之变成无符号的。汇编里是 `cmp r2, r3; bcs`（bcs = 无符号“大于等于”），而且操作数顺序被调了一下（`cmp b, a`，然后判断“b >= a”）。

后果就是：调用 `mixed_compare(-1, 5)`，-1 变成 0xFFFFFFFF，永远返回 1。这就是“有符号量悄悄变成无符号量”的经典坑——它不会报警告，只会在某个边界值上悄悄给你错误答案。

## 那个经典 bug

``` asm
000000fc <classic_bug>:
  fc:   b480            push    {r7}
  fe:   b083            sub     sp, #12
 100:   af00            add     r7, sp, #0
 102:   2305            movs    r3, #5
 104:   603b            str     r3, [r7, #0]
 106:   683b            ldr     r3, [r7, #0]
 108:   3b02            subs    r3, #2
 10a:   607b            str     r3, [r7, #4]
 10c:   e005            b.n     11a <classic_bug+0x1e>
 10e:   687b            ldr     r3, [r7, #4]
 110:   2b00            cmp     r3, #0
 112:   db07            blt.n   124 <classic_bug+0x28>
 114:   687b            ldr     r3, [r7, #4]
 116:   3b01            subs    r3, #1
 118:   607b            str     r3, [r7, #4]
 11a:   687b            ldr     r3, [r7, #4]
 11c:   683a            ldr     r2, [r7, #0]
 11e:   429a            cmp     r2, r3
 120:   d8f5            bhi.n   10e <classic_bug+0x12>
 122:   e000            b.n     126 <classic_bug+0x2a>
 124:   bf00            nop
 126:   687b            ldr     r3, [r7, #4]
 128:   4618            mov     r0, r3
 12a:   370c            adds    r7, #12
 12c:   46bd            mov     sp, r7
 12e:   bc80            pop     {r7}
 130:   4770            bx      lr
```

源码想演示的是 `for (i = len - 2; i < len; i--)` 这种倒序循环：i 是 int、len 是 unsigned，比较会被转成无符号，汇编里循环条件确实是无符号的（`cmp r2, r3; bhi`，即 `len > (unsigned)i`）。

不过实际跑下来这个循环**会正常退出**：i 从 3 一路减到 0，再减到 -1 时，无符号比较 `5 > 0xFFFFFFFF` 为假，循环结束，返回 -1——方向恰好对了。源码注释里担心的 `if (i < 0)` 也确实是有效的：两个操作数都是 int，编译成了有符号的 `cmp r3, #0; blt`。

真正经典的死循环写法是 `for (unsigned i = n; i >= 0; i--)`（i 无符号，`i >= 0` 恒真），或者循环变量的符号和增减方向不匹配的那些变体。判据很简单：**先看比较用了哪组条件码，再看循环变量是什么符号**。

# 空指针解引用

空指针解引用在 CPU 层是什么？不是“异常”，就是一条地址为 0 的 LDR 或 STR。会不会炸、炸成什么样，取决于地址 0 那块内存是什么属性。这个实验正好能看出“读”和“写”的不对称。

``` c
/*
 * 观察目标: 空指针解引用 —— CPU 层面发生了什么
 *
 * 编译: make 34-null-ptr.elf
 * QEMU: make qemu-gdb-34-null-ptr
 *   另一个终端: gdb-multiarch -q -ex "target remote :1234" 34-null-ptr.elf
 *   在 GDB: continue → 观察触发哪个异常
 *
 * 关注点:
 *   1. 空指针读: LDR R0, [R0, #0] 从地址 0 读取
 *   2. 空指针写: STR R0, [R1, #0] 写入地址 0
 *   3. Cortex-M3 的 0 地址是向量表 (FLASH), 读可能成功但意义不对
 *   4. 写 0 地址 → BusFault 或 HardFault
 *   5. 在 QEMU 中会触发异常, 观察 Default_Handler 死循环
 */

static int null_read(void) {
    volatile int *p = (int *)0;
    return *p;               /* LDR from 0x00000000 → 读取向量表第一项 (MSP) */
}

static void null_write(void) {
    volatile int *p = (int *)0;
    *p = 0xDEAD;             /* STR to 0x00000000 → 写 FLASH 区域 → BusFault */
}

static int null_arithmetic(void) {
    int *p = 0;
    return p[10];            /* LDR from 0x00000028 → 读取另一个向量表项 */
}

int main(void) {
    volatile int r;

    /* 逐一取消注释观察不同的行为 */
    r = null_read();
    /* null_write(); */      /* 会触发 HardFault */
    /* r = null_arithmetic(); */

    return 0;
}
```

## 空指针读

``` asm
00000090 <null_read>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   2300            movs    r3, #0
  98:   607b            str     r3, [r7, #4]
  9a:   687b            ldr     r3, [r7, #4]
  9c:   681b            ldr     r3, [r3, #0]
  9e:   4618            mov     r0, r3
  a0:   370c            adds    r7, #12
  a2:   46bd            mov     sp, r7
  a4:   bc80            pop     {r7}
  a6:   4770            bx      lr

000000c4 <null_arithmetic>:
  c4:   b480            push    {r7}
  c6:   b083            sub     sp, #12
  c8:   af00            add     r7, sp, #0
  ca:   2300            movs    r3, #0
  cc:   607b            str     r3, [r7, #4]
  ce:   687b            ldr     r3, [r7, #4]
  d0:   6a9b            ldr     r3, [r3, #40]   @ 0x28
  d2:   4618            mov     r0, r3
  d4:   370c            adds    r7, #12
  d6:   46bd            mov     sp, r7
  d8:   bc80            pop     {r7}
  da:   4770            bx      lr

000000a8 <null_write>:
  a8:   b480            push    {r7}
  aa:   b083            sub     sp, #12
  ac:   af00            add     r7, sp, #0
  ae:   2300            movs    r3, #0
  b0:   607b            str     r3, [r7, #4]
  b2:   687b            ldr     r3, [r7, #4]
  b4:   f64d 62ad       movw    r2, #57005      @ 0xdead
  b8:   601a            str     r2, [r3, #0]
  ba:   bf00            nop
  bc:   370c            adds    r7, #12
  be:   46bd            mov     sp, r7
  c0:   bc80            pop     {r7}
  c2:   4770            bx      lr
```

`null_read`：`movs r3, #0` 把 0 存进 p，然后 `ldr r3, [r3, #0]`——从地址 0 读 4 字节。在链接脚本里地址 0 是 FLASH，放着向量表，所以这个读不会炸，读到的是向量表第一项。用 GDB 瞄一眼：

``` bash
(gdb) print/x null_read()
$1 = 0x20010000
(gdb) x/4xw 0x0
0x0 <vector_table>:    0x20010000    0x00000041    0x00000089    0x00000089
```

0x20010000 是初始 MSP（向量表第 0 项，复位后装进 SP 的值），0x41 是 Reset_Handler 的地址（0x40 | 1，Thumb 位）。null_read “成功”了——但它读到的完全不是任何有用的东西。

`null_arithmetic` 的 `p[10]` 则是 `ldr r3, [r3, #40]`，从 0x28 读，也就是向量表第 10 项——我们没填过，是 0。

## 空指针写

`null_write` 是 `str r2, [r3, #0]`，往地址 0 写 0xDEAD。源码注释预期“触发 BusFault/HardFault”，但实际在 QEMU 上**没有**：地址 0 在 QEMU 的 lm3s6965evb 模型里是一块 256KB 的 **rom** 区域（`monitor info mtree` 能看到 `stellaris.flash`），对 rom 的写入被静默丢弃。

把 null_write 打开（等价于取消源码里那行注释）再跑一遍：

``` bash
(gdb) break *0x88          # Default_Handler(硬故障入口)
(gdb) break *0xee          # null_write 之后的下一句
(gdb) continue
Breakpoint 2, main () at 34-fault.c:40
40        return 0;
(gdb) x/4xw 0x0
0x0 <vector_table>:    0x20010000    0x00000041    0x00000089    0x00000089
(gdb) printf "CFSR = %#x\n", *(unsigned int*)0xE000ED28
CFSR = 0
```

停下来的是 `0xee`（null_write 之后），不是 `0x88`（故障入口）；内存一个字都没变，CFSR（可配置故障状态寄存器）也是 0——确实没发生任何故障。

所以这个实验给出两条结论：
- **读**空指针：地址 0 是可读的 FLASH，不炸，但读到的是向量表，语义完全错。
- **写**空指针：在 QEMU 这块板子上被无声丢弃。真实芯片的行为取决于 flash 控制器——有的直接丢弃写入，有的触发 BusFault，不能一概而论。想稳稳拿到一个 HardFault，得让地址落在真正未映射、且会报错的空间，或者用 MPU 把只读区域配成“访问即 fault”。

“解引用空指针会触发异常”是被过度简化的说法。CPU 只认地址和那个地址的属性：读一块合法的只读区可能毫无反应地读出错数据，写一块只读区可能被丢弃、也可能 fault。真正能指望的，是**语义一定错**。
# 栈缓冲区溢出

这个实验本想演示“越界写覆盖返回地址，函数返回时 `pop {pc}` 跳飞”。但真跑起来，会先撞上一个更基础、也更生动的教训。

``` c
/*
 * 观察目标: 栈缓冲区溢出 —— 返回地址被篡改
 *
 * 编译: make 35-stack-overflow.elf
 * GDB:  make qemu-gdb-35-stack-overflow
 *   在 GDB: break main; continue; stepi... 观察 SP 和栈上数据
 *
 * 关注点:
 *   1. 局部数组越界写入 → 覆盖相邻栈上的内容
 *   2. 函数返回时 POP {PC} 加载被篡改的返回地址 → 跳转到意外位置
 *   3. 递归深度过大 → SP 递减超过 SRAM 范围 → 访问无效内存
 *   4. Cortex-M3 有 MPU 可检测栈溢出, 但默认未启用
 */

static int buffer_overflow(void) {
    int arr[4];
    int secret = 0x12345678;

    /* arr[4], arr[5], ... 越界写入 → 覆盖 secret 和返回地址 */
    for (int i = 0; i <= 8; i++)
        arr[i] = 0xAAAAAAAA;

    return secret;     /* 可能已被覆盖为 0xAAAAAAAA */
}

static int recursive_overflow(int depth) {
    int buf[64];       /* 每层递归 256 字节栈 */
    buf[0] = depth;
    if (depth == 0)
        return 0;
    return recursive_overflow(depth - 1) + buf[0];
}

int main(void) {
    volatile int r;
    r = buffer_overflow();          /* 观察返回值和返回地址 */
    /* r = recursive_overflow(200); */   /* 取消注释观察栈溢出 HardFault */
    return 0;
}
```

先看 -O0 的汇编：

``` asm
00000090 <buffer_overflow>:
  90:   b480            push    {r7}
  92:   b087            sub     sp, #28
  94:   af00            add     r7, sp, #0
  96:   4b0c            ldr     r3, [pc, #48]   @ (c8 <buffer_overflow+0x38>)
  98:   613b            str     r3, [r7, #16]
  9a:   2300            movs    r3, #0
  9c:   617b            str     r3, [r7, #20]
  9e:   e00a            b.n     b6 <buffer_overflow+0x26>
  a0:   697b            ldr     r3, [r7, #20]
  a2:   009b            lsls    r3, r3, #2
  a4:   3318            adds    r3, #24
  a6:   443b            add     r3, r7
  a8:   f04f 32aa       mov.w   r2, #2863311530 @ 0xaaaaaaaa
  ac:   f843 2c18       str.w   r2, [r3, #-24]
  b0:   697b            ldr     r3, [r7, #20]
  b2:   3301            adds    r3, #1
  b4:   617b            str     r3, [r7, #20]
  b6:   697b            ldr     r3, [r7, #20]
  b8:   2b08            cmp     r3, #8
  ba:   ddf1            ble.n   a0 <buffer_overflow+0x10>
  bc:   693b            ldr     r3, [r7, #16]
  be:   4618            mov     r0, r3
  c0:   371c            adds    r7, #28
  c2:   46bd            mov     sp, r7
  c4:   bc80            pop     {r7}
  c6:   4770            bx      lr
  c8:   12345678        .word   0x12345678

000000cc <recursive_overflow>:
  cc:   b580            push    {r7, lr}
  ce:   b0c2            sub     sp, #264        @ 0x108
  d0:   af00            add     r7, sp, #0
  d2:   f507 7384       add.w   r3, r7, #264    @ 0x108
  d6:   f5a3 7382       sub.w   r3, r3, #260    @ 0x104
  da:   6018            str     r0, [r3, #0]
  dc:   f507 7384       add.w   r3, r7, #264    @ 0x108
  e0:   f5a3 7380       sub.w   r3, r3, #256    @ 0x100
  e4:   f507 7284       add.w   r2, r7, #264    @ 0x108
  e8:   f5a2 7282       sub.w   r2, r2, #260    @ 0x104
  ec:   6812            ldr     r2, [r2, #0]
  ee:   601a            str     r2, [r3, #0]
  f0:   f507 7384       add.w   r3, r7, #264    @ 0x108
  f4:   f5a3 7382       sub.w   r3, r3, #260    @ 0x104
  f8:   681b            ldr     r3, [r3, #0]
  fa:   2b00            cmp     r3, #0
  fc:   d101            bne.n   102 <recursive_overflow+0x36>
  fe:   2300            movs    r3, #0
 100:   e00f            b.n     122 <recursive_overflow+0x56>
 102:   f507 7384       add.w   r3, r7, #264    @ 0x108
 106:   f5a3 7382       sub.w   r3, r3, #260    @ 0x104
 10a:   681b            ldr     r3, [r3, #0]
 10c:   3b01            subs    r3, #1
 10e:   4618            mov     r0, r3
 110:   f7ff ffdc       bl      cc <recursive_overflow>
 114:   4602            mov     r2, r0
 116:   f507 7384       add.w   r3, r7, #264    @ 0x108
 11a:   f5a3 7380       sub.w   r3, r3, #256    @ 0x100
 11e:   681b            ldr     r3, [r3, #0]
 120:   4413            add     r3, r2
 122:   4618            mov     r0, r3
 124:   f507 7784       add.w   r7, r7, #264    @ 0x108
 128:   46bd            mov     sp, r7
 12a:   bd80            pop     {r7, pc}
```

把函数帧摊开看：`push {r7}` 之后 `sub sp, #28`，r7 落在帧底。用 GDB 在函数入口断下来（r7 = 0x2000ffd0），各变量的落点是这样的：

| C 变量 | 地址 | 说明 |
|--------|------|------|
| arr[0..3] | r7+0 … r7+12 | 4 个 int |
| secret | r7+16 | **正好是 arr[4]** |
| 循环变量 i | r7+20 | **正好是 arr[5]** |
| 保存的 r7 | r7+28 | =0x2000fff0，调用者的 r7 |
| main 的返回地址 | r7+44 | **arr[11]**，0x6f |

循环 `for (i = 0; i <= 8; i++) arr[i] = 0xAAAAAAAA;` 里，每次写 arr[i] 就是 `str r2, [r7 + 4*i]`（源码写成 `r7 + i*4 + 24` 再 `[r3, #-24]`，效果一样）。于是：

- i=4 时把 secret 写成 0xAAAAAAAA（这是源码预期的）；
- **i=5 时把循环变量 i 自己写成了 0xAAAAAAAA！**

i 一旦变成 0xAAAAAAAA，下一轮 `adds r3, #1` 得到 0xAAAAAAAB（当有符号数看是负数），再比较 `cmp r3, #8; ble`——负数当然 ≤ 8，于是接着循环，数组下标彻底失控。GDB 里逐次打印下标和目标地址，看得清清楚楚：

``` bash
iter4: i=3  store=r7+12=0x2000ffdc
iter5: i=4  store=r7+16=0x2000ffe0   ← arr[4] = secret
iter6: i=5  store=r7+20=0x2000ffe4   ← arr[5] = 循环变量自己
iter7: i=-1431655765  store=0xcaabaa7c
iter8: i=-1431655764  store=0xcaabaa80
```

（0xAAAAAAAA 按有符号看是 -1431655766，加 1 得到 -1431655765。）从 iter7 那一轮起，每一次写都落在离栈很远的地方，函数再也不会正常返回。

这就是这一节真正的教训，比“覆盖返回地址”更直白：**越界写在汇编层面没有任何检查，它就是一条普通 STR。**它踩到哪一格完全由地址决定——这一次，它先踩掉了同帧里的兄弟变量，再踩掉了循环变量本身。

那返回地址在哪？在这个帧布局里，buffer_overflow 是用 `bx lr` 返回的（它没把 lr 入栈），真正要保护的是调用者 main 保存的返回地址，位置在 [r7+44]（也就是 arr[11]）。只要越界的脚步能走到那里，main 尾声的 `pop {r7, pc}` 就会把被改写的值装进 PC——这就是经典的“栈溢出劫持返回地址”。本实验没走到那一步，是因为循环在 i=5 时已经因为踩到自己而失控了。

（顺带说一句 recursive_overflow：它每层递归 `sub sp, #264`，200 层约 54KB，而这块板子的 SRAM 只有 64KB，还没到溢出边界；想让它真的把栈撑破，得再加深度或者减小 `buf`。）

# 返回局部变量指针

“返回局部变量地址”是典型 UB。这个实验里其实藏着两个不同的坑：一个是编译器对 `return &x` 的处理，另一个才是真正意义上的“栈空间被复用”。

``` c
/*
 * 观察目标: 返回局部变量指针 —— 栈空间被回收后的陷阱
 *
 * 编译: make 36-use-after-return.elf
 * GDB:  make qemu-gdb-36-use-after-return
 *
 * 关注点:
 *   1. 函数返回后栈空间被回收 (ADD SP / POP)
 *   2. 指向局部变量的指针变成"悬空指针"
 *   3. 后续函数调用重用同一段栈空间 → 旧值被覆盖
 *   4. 汇编上: 第一次调用后指针指向的地址内容正确,
 *              第二次调用后内容被新函数的局部变量覆盖
 *   5. 有时能用, 有时不能 → 最痛苦的 bug 类型
 */

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wreturn-local-addr"

static int *dangling(void) {
    int x = 42;
    return &x;
}

#pragma GCC diagnostic pop

static volatile int *safe_ptr;

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdangling-pointer="

static void capture(void) {
    volatile int y = 0xDEAD;
    safe_ptr = &y;
}

#pragma GCC diagnostic pop

static void overwrite(void) {
    volatile int z = 0xCAFE;
    (void)z;
}

int main(void) {
    volatile int *p;
    volatile int r;

    p = dangling();
    r = *p;
    overwrite();
    r = *p;

    capture();
    r = *safe_ptr;
    overwrite();
    r = *safe_ptr;
    return 0;
}
```

## `return &x`：GCC 直接给 NULL

``` asm
00000090 <dangling>:
  90:   b480            push    {r7}
  92:   b083            sub     sp, #12
  94:   af00            add     r7, sp, #0
  96:   232a            movs    r3, #42 @ 0x2a
  98:   607b            str     r3, [r7, #4]
  9a:   2300            movs    r3, #0
  9c:   4618            mov     r0, r3
  9e:   370c            adds    r7, #12
  a0:   46bd            mov     sp, r7
  a2:   bc80            pop     {r7}
  a4:   4770            bx      lr

000000a6 <capture>:
  a6:   b480            push    {r7}
  a8:   b083            sub     sp, #12
  aa:   af00            add     r7, sp, #0
  ac:   f64d 63ad       movw    r3, #57005      @ 0xdead
  b0:   607b            str     r3, [r7, #4]
  b2:   4a04            ldr     r2, [pc, #16]   @ (c4 <capture+0x1e>)
  b4:   1d3b            adds    r3, r7, #4
  b6:   6013            str     r3, [r2, #0]
  b8:   bf00            nop
  ba:   370c            adds    r7, #12
  bc:   46bd            mov     sp, r7
  be:   bc80            pop     {r7}
  c0:   4770            bx      lr
  c2:   bf00            nop
  c4:   20000000        .word   0x20000000

000000c8 <overwrite>:
  c8:   b480            push    {r7}
  ca:   b083            sub     sp, #12
  cc:   af00            add     r7, sp, #0
  ce:   f64c 23fe       movw    r3, #51966      @ 0xcafe
  d2:   607b            str     r3, [r7, #4]
  d4:   687b            ldr     r3, [r7, #4]
  d6:   bf00            nop
  d8:   370c            adds    r7, #12
  da:   46bd            mov     sp, r7
  dc:   bc80            pop     {r7}
  de:   4770            bx      lr
```

`dangling()` 里是 `int x = 42; return &x;`。看汇编：`movs r3, #42` 把 42 写进 x，然后 `movs r3, #0; mov r0, r3`——**返回的是 0（NULL）**。GCC 压根没把 `&x` 交出来，而是直接把这个 UB 确定性化成了一个空指针。

所以 main 里 `r = *p;` 实际是在从地址 0 读——又是向量表，和上一个实验的下场一样（读到 0x20010000）。这个实验的前半段，就这样被编译器“提前终止”了。

## 真正演示栈复用：capture / safe_ptr

实验的后半段换了个方式：`capture()` 把局部变量 y 的地址存进全局 `safe_ptr`，`overwrite()` 再用自己局部的 z 去写栈。汇编上，capture 里 `adds r3, r7, #4; str r3, [r2, #0]`——把 y 的地址（栈上）存进 safe_ptr；overwrite 里 z 也是 `str r3, [r7, #4]`，落在同一个偏移。

因为 capture 和 overwrite 的帧布局一模一样，overwrite 一运行，就会踩在 capture 已经失效的那格栈上。GDB 里跑一遍：

``` bash
(gdb) capture() 之后：
safe_ptr = 0x2000ffe4        # 指向已经返回的 capture 帧里的 y
(gdb) print *safe_ptr
$ = 0xdead                   # 读出来还是 capture 当初写的值
(gdb) overwrite() 之后：
$ = 0xcafe                   # 同一格栈被 overwrite 的局部 z 覆盖了
```

一次“已经死掉”的栈帧，被下一次函数调用原样接手——指针还指着那个地址，可内存里现在是什么，已经没人保证。这就是“有时能用、有时出错”的来源，也是最难查的那类 bug。

顺带对照一下 dangling：同样是“返回局部地址”，`return &x` 被编译器一步堵死成 NULL；而 `&y` 经由一个全局指针流出去，编译器管不着，栈帧就这么堂而皇之地漏了出去。两条路，两条完全不同的下场。


---

# 尾声

到这里，从 C 到汇编的这一趟就走完了。数一下，三十多个实验，覆盖了运算、控制流、函数调用、内存与数据、并发同步、浮点、编译器优化，以及一批“常见 C 错误在 CPU 眼里的样子”。

回头看，真正需要背下来的指令其实没几条——翻来覆去就是 `ldr/str`、`adds/subs`、`cmp` + 条件跳转、`bl/bx`、`push/pop`。剩下的都是同一套方法：写一小段 C，编译，反汇编，然后问一句“为什么是这个指令”。指令集是用来查的，不是用来背的，这一点在亲手做完之后体会格外深。

也正因为结论都是“动手做出来的”，文中有好几处“预期”和“实测”并不一致——GCC 会把 `return &x` 直接变成 NULL，QEMU 对写只读地址不报错，越界写在汇编层完全没有边界，倒序循环因为方向恰好对了而安然退出。这些意外反而比“如期发生”更有价值，因为它们才是真实的编译器 / 模拟器 / CPU 行为，也是把这套方法坚持下去的理由。

下一篇会顺着书往下读，把异常与中断（NVIC、优先级、SysTick）单独拎出来做一轮实验，把这一篇里只有雏形的“中断并发”补齐。

感谢阅读~

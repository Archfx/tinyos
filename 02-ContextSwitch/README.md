# ContextSwitch - RISC-V 


In the previous episode [HelloWorld](https://archfx.github.io/posts/2023/08/tinyos1/) of *TinyOS*, we discussed how to print strings to the UART serial port for a specific processor on QEMU that utilises RISC-V architecture. This episode takes us further into the operating system territory, introducing the concept of "Context-Switch."

## Main File (os.c)

This time, in addition to stuff that we had earlier, we have a function called `task`

You can find the complete code [os.c](https://github.com/Archfx/tinyos/blob/master/02-ContextSwitch/os.c) from [here](https://github.com/Archfx/tinyos/tree/master/02-ContextSwitch).

```c
#include "os.h"

#define STACK_SIZE 1024
uint8_t task0_stack[STACK_SIZE];
struct context ctx_os;
struct context ctx_task;

extern void sys_switch();

void user_task0(void)
{
	lib_puts("Task0: Context Switch Success !\n");
	while (1) {} // stop here.
}

int os_main(void)
{
	lib_puts("OS start\n");
	ctx_task.ra = (reg_t) user_task0;
	ctx_task.sp = (reg_t) &task0_stack[STACK_SIZE-1];
	sys_switch(&ctx_os, &ctx_task);
	return 0;
}
```

Task `task` is a function, which is `user_task0`` in the main file. In order to switch, we set `ctx_task.ra` as `user_task0`. Since `ra` is a return address register, its function is to set the return adress (`ra`) to the program counter (`pc`), so that it can jump to this function to execute when executing the `ret` instruction.

```c
	ctx_task.ra = (reg_t) user_task0;
	ctx_task.sp = (reg_t) &task0_stack[STACK_SIZE-1];
	sys_switch(&ctx_os, &ctx_task);
```

However, each task needs stack space to execute function calls within the C context. As a result, we allocate stack space for `task0` and utilize `ctx_task.sp` to reference the stack's starting point.

## System Switch function

Then we can use `sys_switch(&ctx_os, &ctx_task)` to switch from the main program to `task0`, where `sys_switch` is located in [sys.s](https://github.com/Archfx/tinyos/blob/master/02-ContextSwitch/sys.s) to combine language functions, the content is as follows:

```c
# Context switch
#
#   void sys_switch(struct context *old, struct context *new);
# 
# Save current registers in old. Load from new.

.globl sys_switch
.align 4
sys_switch:
        ctx_save a0  # a0 => struct context *old
        ctx_load a1  # a1 => struct context *new
        ret          # pc=ra; swtch to new task (new->ra)
```

In RISC-V, the parameters are mainly placed in the temporary registers `a0`, `a1`, ..., `a7`. When there are more than eight parameters, they will be passed on the stack.

The C language function corresponding to `sys_switch` is as follows:

```c
void sys_switch(struct context *old, struct context *new);
```

In the above program, `a0` corresponds to old value (the context of the old task), and a1 corresponds to new value (the context of the new task). The function of the entire `sys_switch` is to store the context of the old task, and then load the context of the new task to start execution.

The last `ret` instruction is very important, because when the context of the new task is loaded, the `ra` register will also be loaded, so when `ret` is executed, it will set `pc=ra`, and then jump to the new task (such as `void user_task0 (void)`) that needs to be executed next.

`ctx_save` and `ctx_load` in sys_switch are two assembly [macros](https://en.wikipedia.org/wiki/Macro_(computer_science)), which are defined as follows:

```c
# ============ MACRO ==================
.macro ctx_save base
        sw ra, 0(\base)
        sw sp, 4(\base)
        sw s0, 8(\base)
        sw s1, 12(\base)
        sw s2, 16(\base)
        sw s3, 20(\base)
        sw s4, 24(\base)
        sw s5, 28(\base)
        sw s6, 32(\base)
        sw s7, 36(\base)
        sw s8, 40(\base)
        sw s9, 44(\base)
        sw s10, 48(\base)
        sw s11, 52(\base)
.endm

.macro ctx_load base
        lw ra, 0(\base)
        lw sp, 4(\base)
        lw s0, 8(\base)
        lw s1, 12(\base)
        lw s2, 16(\base)
        lw s3, 20(\base)
        lw s4, 24(\base)
        lw s5, 28(\base)
        lw s6, 32(\base)
        lw s7, 36(\base)
        lw s8, 40(\base)
        lw s9, 44(\base)
        lw s10, 48(\base)
        lw s11, 52(\base)
.endm
# ============ Macro END   ==================
```

RISC-V must store `ra`, `sp`, `s0`, ... `s11` and other temporary registers when switching between schedules. The above code is from the [xv6](https://github.com/mit-pdos/xv6-riscv/blob/riscv/kernel/swtch.S) teaching operating system kernel and modified for RISC-V 32-bit application.

## Struct for Register Contents

In [riscv.h](https://github.com/ccc-c/mini-riscv-os/blob/master/02-ContextSwitch/riscv.h) header file, we have to define corresponding struct for context related registers. 

```c
// Saved registers for kernel context switches.
struct context {
  reg_t ra;
  reg_t sp;

  // callee-saved
  reg_t s0;
  reg_t s1;
  reg_t s2;
  reg_t s3;
  reg_t s4;
  reg_t s5;
  reg_t s6;
  reg_t s7;
  reg_t s8;
  reg_t s9;
  reg_t s10;
  reg_t s11;
};
```
Now from the main file, we need to set the task pointers to the `ra` and `sp`, and we can use the `sys_switch` function to smoothly switch from `os_main` to `user_task0`.

```c
int os_main(void)
{
	lib_puts("OS start\n");
	ctx_task.ra = (reg_t) user_task0;
	ctx_task.sp = (reg_t) &task0_stack[STACK_SIZE-1];
	sys_switch(&ctx_os, &ctx_task);
	return 0;
}
```

## Execute with QEMU

You can run the simulation on QEMU with the [archfx/rv32i:qemu](https://hub.docker.com/repository/docker/archfx/rv32i/general) docker containter mounted with the [tinyos repo](https://github.com/archfx/tinyos) following the below steps;

```shell
cd 03-ContextSwitch 
make 
```
<code>riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s sys.s lib.c os.c</code>


```shell
make qemu
```
<code>
Press Ctrl-A and then X to exit QEMU<br>
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf<br>
OS start<br>
Task0: Context Switch Success !<br>
QEMU: Terminated<br>
</code>

We looked at the basic details about the implementation of the "Context-Switch" mechanism within the RISC-V architecture. This method showcases how tasks are managed and their execution contexts transitioned, contributing to the overall functionality and efficiency of the system.
# 02-ContextSwitch -- RISC-V 


In the previous chapter [01-HelloOs](01-HelloOs.md), we introduced how to print strings to the UART serial port under the RISC-V architecture. In this chapter, we will move forward to the operating system and introduce The mysterious "Context-Switch" technology.

## os.c

The following is the main program os.c of 02-ContextSwitch. In addition to the os itself, this program also has a "task".
* https://github.com/ccc-c/mini-riscv-os/blob/master/02-ContextSwitch/os.c

```cpp
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

Task `task` is a function, which is user_task0 in the above os.c. In order to switch, we set ctx_task.ra as user_task0. Since ra is a return address register, its function is to use Ra replaces the program counter pc, so that it can jump to this function to execute when executing the ret instruction.

```cpp
	ctx_task.ra = (reg_t) user_task0;
	ctx_task.sp = (reg_t) &task0_stack[STACK_SIZE-1];
	sys_switch(&ctx_os, &ctx_task);
```

But each task must have stack space to make function calls in the C locale. So we allocate the stack space for task0 and use ctx_task.sp to point to the beginning of the stack.
Then we called `sys_switch(&ctx_os, &ctx_task)` to switch from the main program to task0, where sys_switch is located in [sys.s](https://github.com/ccc-c/mini-riscv-os/blob/ master/02-ContextSwitch/sys.s) to combine language functions, the content is as follows:

```s
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

In RISC-V, the parameters are mainly placed in the temporary registers a0, a1, ..., a7. When there are more than eight parameters, they will be passed on the stack.

The C language function corresponding to sys_switch is as follows:

```cpp
void sys_switch(struct context *old, struct context *new);
```

In the above program, a0 corresponds to old (the context of the old task), and a1 corresponds to new (the context of the new task). The function of the entire sys_switch is to store the context of the old task, and then load the context of the new task to start execution.

The last ret instruction is very important, because when the context of the new task is loaded, the ra register will also be loaded, so when ret is executed, it will set pc=ra, and then jump to the new task (such as `void user_task0 (void)` went to execute.

`ctx_save` and `ctx_load` in sys_switch are two assembly language macros, which are defined as follows:

```s
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

RISC-V must store ra, sp, s0, ... s11 and other temporary registers when switching between schedules. The above code is basically copied from the xv6 teaching operating system and modified to RISC-V 32-bit version , its original URL is as follows:

* https://github.com/mit-pdos/xv6-riscv/blob/riscv/kernel/swtch.S

In [riscv.h](https://github.com/ccc-c/mini-riscv-os/blob/master/02-ContextSwitch/riscv.h) this header file, we defined the corresponding struct context The C language structure of , its content is as follows:

```cpp
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
In this way, we have introduced the details of the "Content Switching" task, so the following main program can smoothly switch from os_main to user_task0.

```cpp
int os_main(void)
{
	lib_puts("OS start\n");
	ctx_task.ra = (reg_t) user_task0;
	ctx_task.sp = (reg_t) &task0_stack[STACK_SIZE-1];
	sys_switch(&ctx_os, &ctx_task);
	return 0;
}
```

The following are the execution results of the entire project:

```sh
cd 03-ContextSwitch 
$ make 
riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s sys.s lib.c os.c

cd 03-ContextSwitch 
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
Task0: Context Switch Success !
QEMU: Terminated
```

The above is the implementation method of the "Context-Switch" mechanism in RISC-V!
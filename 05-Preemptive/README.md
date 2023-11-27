# Preemptive Multitasking

[lib.c]: https://github.com/ccc-c/mini-riscv-os/blob/master/05-Preemptive/lib.c
[os.c]: https://github.com/ccc-c/mini-riscv-os/blob/master/05-Preemptive/os.c
[timer.c]: https://github.com/ccc-c/mini-riscv-os/blob/master/05-Preemptive/timer.c
[sys.s]: https://github.com/ccc-c/mini-riscv-os/blob/master/05-Preemptive/sys.s
[task.c]: https://github.com/ccc-c/mini-riscv-os/blob/master/05-Preemptive/task.c
[user.c]: https://github.com/ccc-c/mini-riscv-os/blob/master/05-Preemptive/user.c


In [03-MultiTasking](03-MultiTasking.md) in Chapter 3, we implemented a "Cooperative Multitasking" operating system. However, since no time interruption mechanism is introduced, it cannot become a "Preemptive" multi-tasking system.

In [04-TimerInterrupt](04-TimerInterrupt.md) in Chapter 4, we demonstrate the principle of RISC-V’s time interrupt mechanism.

Finally, we have reached Chapter 5. We plan to combine the technology of the first two chapters to implement a "Preemptive" operating system with forced time interruption. Such a system can be regarded as a miniature embedded operating system.


## System execution

First, let us take a look at the execution status of the system. You can see that in the following execution results, the system switches between OS, Task0, and Task1 in turn.

```sh
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
OS: Activate next task
Task0: Created!
Task0: Running...
Task0: Running...
Task0: Running...
timer_handler: 1
OS: Back to OS

OS: Activate next task
Task1: Created!
Task1: Running...
Task1: Running...
Task1: Running...
timer_handler: 2
OS: Back to OS

OS: Activate next task
Task0: Running...
Task0: Running...
Task0: Running...
timer_handler: 3
OS: Back to OS

OS: Activate next task
Task1: Running...
Task1: Running...
Task1: Running...
timer_handler: 4
OS: Back to OS

OS: Activate next task
Task0: Running...
Task0: Running...
Task0: Running...
QEMU: Terminated
```

This situation is very similar to [03-MultiTasking](03-MultiTasking.md) in Chapter 3, both of which have the following execution sequence.

```
OS=>Task0=>OS=>Task1=>OS=>Task0=>OS=>Task1....
```

The only difference is that the user process in Chapter 3 must actively return control to the operating system through `os_kernel()`.
```cpp
void user_task0(void)
{
	lib_puts("Task0: Created!\n");
	lib_puts("Task0: Now, return to kernel mode\n");
	os_kernel();
	while (1) {
		lib_puts("Task0: Running...\n");
		lib_delay(1000);
		os_kernel();
	}
}
```

However, in [05-Preemptive](05-Preemptive.md) of this chapter, the user schedule does not need to be actively handed back to the OS, but the OS forces the switching action through time interruption.
```cpp
void user_task0(void)
{
	lib_puts("Task0: Created!\n");
	while (1) {
		lib_puts("Task0: Running...\n");
		lib_delay(1000);
	}
}
```

The lib_delay in [lib.c] is actually a delay loop and does not return control.

```cpp
void lib_delay(volatile int count)
{
	count *= 50000;
	while (count--);
}
```

On the contrary, the operating system will forcefully take back control through time interruption. (Because lib_delay has a long delay, the operating system usually interrupts its `while (count--)` loop to take back control)

## Operating system [os.c]

- https://github.com/ccc-c/mini-riscv-os/blob/master/05-Preemptive/os.c

The operating system os.c will initially call `user_init()` to allow the user to create tasks (in this example, user_task0 and user_task1 will be created in [user.c].

```cpp
#include "os.h"

void user_task0(void)
{
	lib_puts("Task0: Created!\n");
	while (1) {
		lib_puts("Task0: Running...\n");
		lib_delay(1000);
	}
}

void user_task1(void)
{
	lib_puts("Task1: Created!\n");
	while (1) {
		lib_puts("Task1: Running...\n");
		lib_delay(1000);
	}
}

void user_init() {
	task_create(&user_task0);
	task_create(&user_task1);
}
```

Then the operating system will set the time interrupt through the `timer_init()` function in `os_start()`, and then enter the main loop of `os_main()`, which adopts Round-Robin's large cycle scheduling. Method, each time you switch, select the next task to execute (if you have reached the last task, the next task will be the 0th task).

```cpp

#include "os.h"

void os_kernel() {
	task_os();
}

void os_start() {
	lib_puts("OS start\n");
	user_init();
	timer_init(); // start timer interrupt ...
}

int os_main(void)
{
	os_start();

	int current_task = 0;
	while (1) {
		lib_puts("OS: Activate next task\n");
		task_go(current_task);
		lib_puts("OS: Back to OS\n");
		current_task = (current_task + 1) % taskTop; // Round Robin Scheduling
		lib_puts("\n");
	}
	return 0;
}
```

In the interrupt mechanism of 05-Preemptive, we modified the interrupt vector table:

```cpp
.globl trap_vector
# the trap vector base address must always be aligned on a 4-byte boundary
.align 4
trap_vector:
	# save context(registers).
	csrrw	t6, mscratch, t6	# swap t6 and mscratch
        reg_save t6
	csrw	mscratch, t6
	# call the C trap handler in trap.c
	csrr	a0, mepc
	csrr	a1, mcause
	call	trap_handler

	# trap_handler will return the return address via a0.
	csrw	mepc, a0

	# load context(registers).
	csrr	t6, mscratch
	reg_load t6
	mret
```

When an interrupt occurs, the interrupt vector table `trap_vector()` will call `trap_handler()`:


```cpp
reg_t trap_handler(reg_t epc, reg_t cause)
{
  reg_t return_pc = epc;
  reg_t cause_code = cause & 0xfff;

  if (cause & 0x80000000)
  {
    /* Asynchronous trap - interrupt */
    switch (cause_code)
    {
    case 3:
      lib_puts("software interruption!\n");
      break;
    case 7:
      lib_puts("timer interruption!\n");
      // disable machine-mode timer interrupts.
      w_mie(~((~r_mie()) | (1 << 7)));
      timer_handler();
      return_pc = (reg_t)&os_kernel;
      // enable machine-mode timer interrupts.
      w_mie(r_mie() | MIE_MTIE);
      break;
    case 11:
      lib_puts("external interruption!\n");
      break;
    default:
      lib_puts("unknown async exception!\n");
      break;
    }
  }
  else
  {
    /* Synchronous trap - exception */
    lib_puts("Sync exceptions!\n");
    while (1)
    {
      /* code */
    }
  }
  return return_pc;
}
```

After jumping to `trap_handler()`, it will call different handlers for different types of interrupts, so we can think of it as an interrupt dispatch task relay station:

```
                         +----------------+
                         | soft_handler() |
                 +-------+----------------+
                 |
+----------------+-------+-----------------+
| trap_handler() |       | timer_handler() |
+----------------+       +-----------------+
                 |
                 +-------+-----------------+
                         | exter_handler() |
                         +-----------------+
```

`trap_handler` can hand over interrupt processing to different handlers according to different interrupt types. This can greatly improve the scalability of the operating system.
```cpp
#include "timer.h"

// a scratch area per CPU for machine-mode timer interrupts.
reg_t timer_scratch[NCPU][5];

#define interval 20000000 // cycles; about 2 second in qemu.

void timer_init()
{
  // each CPU has a separate source of timer interrupts.
  int id = r_mhartid();

  // ask the CLINT for a timer interrupt.
  // int interval = 1000000; // cycles; about 1/10th second in qemu.

  *(reg_t *)CLINT_MTIMECMP(id) = *(reg_t *)CLINT_MTIME + interval;

  // prepare information in scratch[] for timervec.
  // scratch[0..2] : space for timervec to save registers.
  // scratch[3] : address of CLINT MTIMECMP register.
  // scratch[4] : desired interval (in cycles) between timer interrupts.
  reg_t *scratch = &timer_scratch[id][0];
  scratch[3] = CLINT_MTIMECMP(id);
  scratch[4] = interval;
  w_mscratch((reg_t)scratch);

  // enable machine-mode timer interrupts.
  w_mie(r_mie() | MIE_MTIE);
}

static int timer_count = 0;

void timer_handler()
{
  lib_printf("timer_handler: %d\n", ++timer_count);
  int id = r_mhartid();
  *(reg_t *)CLINT_MTIMECMP(id) = *(reg_t *)CLINT_MTIME + interval;
}

```

See `timer_handler()` in [timer.c], it will reset `MTIMECMP`.

```cpp
/* In trap_handler() */
// ...
case 7:
      lib_puts("timer interruption!\n");
      // disable machine-mode timer interrupts.
      w_mie(~((~r_mie()) | (1 << 7)));
      timer_handler();
      return_pc = (reg_t)&os_kernel;
      // enable machine-mode timer interrupts.
      w_mie(r_mie() | MIE_MTIE);
      break;
// ...
```

- In order to avoid interrupt nesting in Timer Interrupt, `trap_handler()` will close the timer interrupt before processing the interrupt, and then open it again after the processing is completed.
- After `timer_handler()` is executed, `trap_handler()` will point mepc to `os_kernel()` to achieve the task switching function.
  In other words, if the interrupt does not belong to Timer Interrupt, the Program counter will jump back to the state before entering the interrupt. This step is defined in `trap_vector()`:

```assembly=
csrr	a0, mepc # a0 => arg1 (return_pc) of trap_handler()
```

> **Note**
> In RISC-V, the parameters of the function will be stored in the a0 - a7 registers first. If there are not enough, they will be stored in the Stack.
> Among them, the a0 and a1 registers also serve as function return values.

Finally, remember to import the trap and timer initialization actions when the Kernel is started:

```cpp
void os_start()
{
	lib_puts("OS start\n");
	user_init();
	trap_init();
	timer_init(); // start timer interrupt ...
}
```

By forcibly taking back control through time interruption, we don't have to worry about a bully schedule taking over the CPU, and the system will not be stuck by the bully and completely paralyzed. This is the most important "schedule management mechanism" in modern operating systems. .

Although mini-riscv-os is just a micro embedded operating system, it still demonstrates the design principle of a specific and micro "preemptible operating system" through relatively streamlined code.

Of course, there is still a long way to go to learn "Operating System Design". mini-riscv-os does not have "File System", and I have not learned the control and switching methods of super mode and user mode in RISC-V, nor have I introduced it. RISC-V's virtual memory mechanism, so the code in this chapter still only uses machine mode, so it is unable to provide a more complete "Permissions and Protection Mechanism".

Fortunately, someone has already done these things. You can learn more about these more complex mechanisms by studying xv6-riscv, a teaching operating system designed by MIT. The source code of xv6-riscv has a total of more than 8,000 lines. , although not too few, xv6-riscv is a very streamlined system compared to Linux/Windows, which can run from millions to tens of millions of lines.

- https://github.com/mit-pdos/xv6-riscv

However, xv6-riscv can only be compiled and executed under Linux, but I modified mkfs/mkfs.c and it can be compiled and executed in the same environment as mini-riscv-os such as windows + git bash.

You can get the windows version of xv6-riscv source code from the following URL, and then compile and execute it. You should be able to learn more advanced operating system design principles through xv6-riscv based on mini-riscv-os. .

- https://github.com/ccc-c/xv6-riscv-win

The following provides more learning resources about RISC-V, so that everyone can learn RISC-V operating system design without having to go through too much exploration.

- [AwesomeCS Wiki](https://github.com/ianchen0119/AwesomeCS/wiki)
- [Step by step, learn to develop an operating system on RISC-V](https://github.com/plctlab/riscv-operating-system-mooc)
- [RISC-V Manual - A guide to the open source instruction set (PDF)](http://crva.ict.ac.cn/documents/RISC-V-Reader-Chinese-v2p1.pdf)
- [The RISC-V Instruction Set Manual Volume II: Privileged Architecture Privileged Architecture (PDF)](https://riscv.org//wp-content/uploads/2019/12/riscv-spec-20191213.pdf)
- [RISC-V Assembly Programmer's Manual](https://github.com/riscv/riscv-asm-manual/blob/master/riscv-asm.md)
- https://github.com/riscv/riscv-opcodes
  - https://github.com/riscv/riscv-opcodes/blob/master/opcodes-rv32i
- [SiFive Interrupt Cookbook (SiFive's RISC-V interrupt manual)](https://gitlab.com/ccc109/sp/-/blob/master/10-riscv/mybook/riscv-interrupt/sifive-interrupt-cookbook- zh.md)
- [SiFive Interrupt Cookbook -- Version 1.0 (PDF)](https://sifive.cdn.prismic.io/sifive/0d163928-2128-42be-a75a-464df65e04e0_sifive-interrupt-cookbook.pdf)
- Advanced: [proposal for a RISC-V Core-Local Interrupt Controller (CLIC)](https://github.com/riscv/riscv-fast-interrupt/blob/master/clic.adoc)
- original article by Chen Zhongcheng.

I hope this mini-riscv-os textbook can help readers save some valuable time in learning RISC-V OS design!



# Preemptive Multitasking


In the [MultiTasking](https://archfx.github.io/posts/2023/09/tinyos3/) episode of the **TinyOS**🐞 tutorial series, we implemented "Cooperative Multitasking". Next in [TimerInterrupt](https://archfx.github.io/posts/2023/09/tinyos4/) episode, we discussed how the RISC-V time interrupt mechanism works. If you have missed them, I highly recommend going through them before proceeding.

In this episode, we plan to combine the two techniques of the above episodes to implement a "Preemptive" operating system with forced time interruption. Technically, TinyOS is going to be a real-time operating system (RTOS) at the end of this episode.



## Simulation

As we discussed in earlier episodes, we know that where there are multple processes running parallely, they need share the same set of resources between them. So with that in mind, let's run the simulation. Simulation steps are as usual.

If you missed the first article about setting up the environment, you can check it from [here](https://archfx.github.io/posts/2023/08/tinyos0/).



First let's take a look at the system's behaviour.
```sh
cd tinyos/05-Preemptive
make qemu
```
<code>
Press Ctrl-A and then X to exit QEMU<br>
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf<br>
OS start<br>
OS: Activate next task<br>
Task0: Created! <br>
Task0: Running... <br>
Task0: Running... <br>
Task0: Running... <br>
timer_handler: 1 <br>
OS: Back to OS <br>
&nbsp; <br>
OS: Activate next task <br>
Task1: Created! <br>
Task1: Running... <br>
Task1: Running... <br>
Task1: Running... <br>
timer_handler: 2 <br>
OS: Back to OS <br>
&nbsp; <br>
OS: Activate next task <br>
Task0: Running... <br>
Task0: Running... <br>
Task0: Running... <br>
timer_handler: 3 <br>
OS: Back to OS <br>
&nbsp; <br>
OS: Activate next task
Task1: Running... <br>
Task1: Running... <br>
Task1: Running... <br>
timer_handler: 4<br>
OS: Back to OS<br>
&nbsp; <br>
OS: Activate next task<br>
Task0: Running... <br>
Task0: Running... <br>
Task0: Running... <br>
QEMU: Terminated<br>
</code>

As we can see, system switches the context between OS, Task0, and Task1 during the execution This situation is very similar to the simulation of [MultiTasking](https://archfx.github.io/posts/2023/09/tinyos3/) episode, where both of which have the following execution sequence.

<pre class="mermaid">
    stateDiagram-v2
    direction LR
    State1 :OS
	State2 : Task0
	State3 : OS
	State4 :Task1
	State5 : OS
	State6 : Task0
	State7 : OS
	State8 : Task1
	
    State1 --> State2
	State2 --> State3
	State3 --> State4
	State4 --> State5
	State5 --> State6
	State6 --> State7
	State7 --> State8

</pre>

The only difference is that the user process in [MultiTasking](https://archfx.github.io/posts/2023/09/tinyos3/) episode must actively return control to the operating system through `os_kernel()`.

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

However, during this simulation, the user schedule does not need to be actively handed back to the OS, but the OS forces the switching action through time interruption.

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

The lib_delay in [lib.c](https://github.com/Archfx/tinyos/05-Preemptive/lib.c) is actually a delay loop and does not return control.

```cpp
void lib_delay(volatile int count)
{
	count *= 50000;
	while (count--);
}
```

On the contrary, the operating system will forcefully take back control through time interruption. (Because lib_delay has a long delay, the operating system usually interrupts its `while (count--)` loop to take back control)

## OS Kernel



The operating system [os.c](https://github.com/Archfx/tinyos/05-Preemptive/os.c) will initially call `user_init()` to allow the user to create tasks (in this example, user_task0 and user_task1 will be created in [user.c](https://github.com/Archfx/tinyos/05-Preemptive/user.c).

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

Then the operating system will set the time interrupt through the `timer_init()` function in `os_start()`, and then enter the main loop of `os_main()`, which adopts Round-Robin scheduling. In Round robin scheduling each process is assigned a fixed time slice in a cyclic manner, ensuring fairness by giving each process equal time on the CPU regardless of its priority or execution time. 

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

In the  interrupt mechanism  of [sys.s](https://github.com/Archfx/tinyos/05-Preemptive/sys.s), we modified the interrupt vector table as below.

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

Essentially what it does is when an interrupt occurs, the interrupt vector table `trap_vector()` will call `trap_handler()` in [trap.c](https://github.com/Archfx/tinyos/05-Preemptive/trap.c).


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

After jumping to `trap_handler()`, it will call different handlers for different types of interrupts, so we can think of it as an interrupt dispatch task relay station.

<pre class="mermaid">
graph LR
    C[trap_handler] --> D[soft_handler]
    C --> E[timer_handler]
    C --> F[exter_handler]

</pre>


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

If you observe the function `timer_handler()` in [timer.c](https://github.com/Archfx/tinyos/05-Preemptive/timer.c), you can see that it invokes reset `MTIMECMP`.

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

In order to avoid interrupt nesting in Timer Interrupt, `trap_handler()` will close the timer interrupt before processing the interrupt, and then open it again after the processing is completed.

After `timer_handler()` is executed, `trap_handler()` will point mepc to `os_kernel()` to achieve the task switching function.
  In other words, if the interrupt does not belong to Timer Interrupt, the Program counter will jump back to the state before entering the interrupt. This step is defined in `trap_vector()` as below. 

```c
csrr	a0, mepc # a0 => arg1 (return_pc) of trap_handler()
```

> **Note**
> In RISC-V, the parameters of the function will be first stored in the a0 - a7 registers. If the space is not enough, they will be stored in the Stack.
> Among them, the a0 and a1 registers also serve as function return values.

Finally, we import the trap and timer initialization actions when the Kernel is started as illustrated below.

```cpp
void os_start()
{
	lib_puts("OS start\n");
	user_init();
	trap_init();
	timer_init(); // start timer interrupt ...
}
```

By forcibly taking back control through time interruption, we don't have to worry about a bully schedule taking over the CPU, and the system will not be stuck by the bully and completely paralyzed. This is the most important "schedule management mechanism" in modern operating systems. 

## Remarks

Although TinyOS is just a "tiny" embedded operating system, it still demonstrates the design principle of a specific and simple "preemptible operating system" through relatively streamlined code.

Of course, there is still a long way to go to learn "Operating System Design". In particular,  TinyOS does not have a "File System", and we haven't even touched on the areas related to control and switching methods of supervisor mode and user mode in RISC-V. Further, OS needs to handle virtual memory mechanisms, so that processes cannot steal other process's data.

Fortunately, you can learn more about these more complex mechanisms by studying [xv6-riscv](https://github.com/mit-pdos/xv6-riscv), a teaching operating system designed by MIT. The source code of xv6-riscv has a total of more than 8,000 lines, although not too few, xv6-riscv is a very streamlined system compared to modern Linux and Windows, which can run from millions to tens of millions of lines.

I hope this episode of TinyOS tutorial series gave you the basic understanging about how the preemptive multitasking is working on RISC-V environment. In the next episode let's discuss about Spinlocks in RISC-V.



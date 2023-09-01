# 03-MultiTasking -- RISC-V 的協同式多工

[os.c]:https://github.com/ccc-c/mini-riscv-os/blob/master/03-MultiTasking/os.c

[task.c]:https://github.com/ccc-c/mini-riscv-os/blob/master/03-MultiTasking/task.c

[user.c]:https://github.com/ccc-c/mini-riscv-os/blob/master/03-MultiTasking/user.c

[sys.s]:https://github.com/ccc-c/mini-riscv-os/blob/master/03-MultiTasking/sys.s

Project -- https://github.com/ccc-c/mini-riscv-os/tree/master/03-MultiTasking

In the previous chapter [02-ContextSwitch](02-ContextSwitch.md), we introduced the context switching mechanism under the RISC-V architecture. Multitasking" operating system.

## Cooperative multitasking

Modern operating systems have a "Preemptive" function that forcibly terminates the process through time interruption, so that when a certain process occupies the CPU for too long, it is forcibly interrupted and switched to another process for execution.

However, in a system without a time interruption mechanism, the operating system "cannot interrupt the bully's schedule", so it must rely on each schedule to actively return control to the operating system in order to allow all schedules to have a chance to execute.

This multi-travel system that relies on an automatic return mechanism is called a "Coorperative Multitasking" system.

Windows 3.1 launched by Microsoft in 1991, as well as [HeliOS] (https://github.com/MannyPeterson/HeliOS) on the single-board computer arduino, are all operating systems of the "cooperative multitasking" mechanism.

In this chapter, we will design a "cooperative multitasking" job system on a RISC-V processor.

First let's take a look at the system's performance.
```sh
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
OS: Activate next task
Task0: Created!
Task0: Now, return to kernel mode
OS: Back to OS

OS: Activate next task
Task1: Created!
Task1: Now, return to kernel mode
OS: Back to OS

OS: Activate next task
Task0: Running...
OS: Back to OS

OS: Activate next task
Task1: Running...
OS: Back to OS

OS: Activate next task
Task0: Running...
OS: Back to OS

OS: Activate next task
Task1: Running...
OS: Back to OS

OS: Activate next task
Task0: Running...
OS: Back to OS

OS: Activate next task
Task1: Running...
OS: Back to OS

OS: Activate next task
Task0: Running...
QEMU: Terminated
```

You can see that the system keeps switching between two tasks Task0, Task1, but the actual switching process is as follows:

```
OS=>Task0=>OS=>Task1=>OS=>Task0=>OS=>Task1  …
```

## User tasks [user.c]

In [user.c] we define two tasks, user_task0 and user_task1, and finally initialize these two tasks in the user_init function.
* https://github.com/ccc-c/mini-riscv-os/blob/master/03-MultiTasking/user.c

```cpp
#include "os.h"

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

void user_task1(void)
{
	lib_puts("Task1: Created!\n");
	lib_puts("Task1: Now, return to kernel mode\n");
	os_kernel();
	while (1) {
		lib_puts("Task1: Running...\n");
		lib_delay(1000);
		os_kernel();
	}
}

void user_init() {
	task_create(&user_task0);
	task_create(&user_task1);
}
```

## main program [os.c]

Then, in the main program os.c of the operating system, we use the big cycle method to arrange each process to be executed sequentially.
* https://github.com/ccc-c/mini-riscv-os/blob/master/03-MultiTasking/os.c

```cpp
#include "os.h"

void os_kernel() {
	task_os();
}

void os_start() {
	lib_puts("OS start\n");
	user_init();
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

The above scheduling method is in principle consistent with [Round Robin Scheduling](https://en.wikipedia.org/wiki/Round-robin_scheduling), but Round Robin Scheduling must be equipped with a time interruption mechanism in principle, but the code in this chapter has no time Interruption, so it can only be said to be the Round Robin Scheduling of the collaborative multitasking version.

Cooperative multitasking must rely on each task to actively return control. For example, in user_task0, whenever the os_kernel() function is called, the context switching mechanism will be called to return control to the operating system [os.c] .
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

The os_kernel() of [os.c] will call the task_os() of [task.c]
```cpp
void os_kernel() {
	task_os();
}
```

And task_os() will call sys_switch in assembly language [sys.s] to switch back to the operating system.
```cpp
// switch back to os
void task_os() {
	struct context *ctx = ctx_now;
	ctx_now = &ctx_os;
	sys_switch(ctx, &ctx_os);
}
```

So the whole system is executed in turn in a polite way under the cooperation of os_main(), user_task0(), user_task1().

[os.c]

```cpp
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

[user.c]

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

void user_task1(void)
{
	lib_puts("Task1: Created!\n");
	lib_puts("Task1: Now, return to kernel mode\n");
	os_kernel();
	while (1) {
		lib_puts("Task1: Running...\n");
		lib_delay(1000);
		os_kernel();
	}
}
```

The above is an example of a specific and micro cooperative multitasking system on the RISC-V processor!

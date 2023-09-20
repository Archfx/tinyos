# TimerInterrupts 



In the previous episode [MultiTasking](https://archfx.github.io/posts/2023/09/tinyos3/), we implemented a operating system with "Cooperative Multitasking". However, it's important to note that without the implementation of an interruption mechanism, our system cannot support preemptive multitasking.

This episode will lay the foundation for a "Preemptive Multitasking System" by introducing the utilization of the "Time Interrupt Mechanism" in RISC-V processors. Through time interrupts, we gain the ability to regain control at predefined intervals, ensuring that a third-party application cannot indefinitely seize control of the system without yielding control back to the operating system.

## Main Concepts for TimerInterrupts

Before learning how the system implements the time interruption mechanism, we must first understand a few things:

- Generating Timer Interrupts
- Interrupt Vector Table
- Control and Status Registers (CSR)

Lets go throgh each of the concept one by one.

### Generating Timer Interrupts


The RISC-V architecture specifies that the system platform must include a timer, and this timer must feature two 64-bit registers: `mtime` and `mtimecmp`. The purpose of these registers is as follows:

1. `mtime` (Machine Time): This register is utilized to keep track of the current counter value of the timer. It serves as a continuously incrementing counter, recording the passage of time in the system.

2. `mtimecmp` (Machine Time Compare): The mtimecmp register is employed to set a comparison value against which the value of mtime is compared. When the value of mtime becomes greater than the value stored in mtimecmp, an interrupt is triggered.

These registers are integral for implementing time-based interrupt handling in RISC-V systems. By comparing mtime with the value stored in mtimecmp, the system can generate interrupts at specific time intervals, facilitating various timing-related tasks and enabling features such as preemptive multitasking and real-time scheduling.
You can find the definitions for these two registers in [riscv.h](https://github.com/Archfx/tinyos/blob/master/04-TimerInterrupt/riscv.h):

After understanding the mechanism for generating a Timer interrupt, we will examine a piece of code that defines the time interval (Interval) for each interrupt trigger in the upcoming explanation.

```cpp
// ================== Timer Interrput ====================

#define NCPU 8             // maximum number of CPUs
#define CLINT 0x2000000
#define CLINT_MTIMECMP(hartid) (CLINT + 0x4000 + 4*(hartid))
#define CLINT_MTIME (CLINT + 0xBFF8) // cycles since boot.
```

Additionally, during system initialization, it's essential to enable the Timer interrupt. This can be achieved by setting the corresponding field in the `mie` (Machine Interrupt Enable) register to 1.

### What is the Interrupt Vector Table?


The interrupt vector table is a data structure managed by the system program. It serves as a mapping between interrupt numbers or types and their corresponding interrupt handlers. When a specific interrupt or exception occurs, the system will look up the corresponding Interrupt Handler in this table.

Here's how it works:

1. When an interrupt, such as a time interrupt, occurs, the processor first stops executing the current program's instructions.

2. It then looks up the interrupt or exception type in the interrupt vector table to find the associated Interrupt_Handler.

3. The processor transfers control to the Interrupt_Handler, which is a predefined piece of code responsible for handling that specific type of interrupt or exception.

4. The Interrupt_Handler performs the necessary processing, which may include saving the current context, handling the interrupt's specific tasks, and eventually returning control to the interrupted program.

5. After completing the handling of the interrupt, the processor jumps back to the original instruction address in the interrupted program, allowing it to continue execution as if the interrupt never occurred.

This mechanism is essential for managing and responding to various interrupts and exceptions in a systematic and controlled manner, ensuring that the system remains stable and responsive. The interrupt vector table plays a crucial role in facilitating this process by directing the processor to the appropriate interrupt handling routines.

> Note:
> When an exception or interrupt occurs, the processor will stop the current process, point the address of the Program counter to the address pointed by `mtvec` and start execution. Such behavior is like actively jumping into a trap. Therefore, this action is defined as Trap in the RISC-V architecture. In the xv6 (risc-v) operating system, we can also find a series of Operations to handle Interrupt (mostly defined in Trap.c).

### Control and Status Registers (CSR) 

The RISC-V architecture encompasses numerous registers, including a category known as Control and Status Registers (CSRs), as highlighted in the title. CSRs serve the crucial role of configuring and recording the processor's operational status.

- CSR (Control and Status Registers):

    - `mtvec`: This register specifies the address that the Program Counter (PC) will jump to when an exception occurs, allowing exception handling to begin.
    - `mcause`: It records the reason for encountering an exception or anomaly.
    - `mtval`: This register is used to store additional information or messages related to the encountered exception.
    - `mepc`: Before entering an exception, it holds the address pointed to by the PC, which can be read to resume execution after handling the exception.
    - `mstatus`: This register's fields are updated by hardware when an exception is entered, reflecting various status changes.
    - `mie`: It determines whether interrupts are enabled or disabled.
    - `mip`: This register indicates the pending status of different types of interrupts.

- Memory Address Mapped:

    - `mtime`: Records the current value of the timer.
    - `mtimecmp`: Stores a comparison value for the timer, against which mtime is compared to generate timer interrupts.
    - `msip`: Used for generating or clearing software interrupts.
    - Platform-Level Interrupt Controller (PLIC): This external hardware component handles and manages interrupts from various sources and devices in the system, ensuring that they are appropriately routed to the processor for handling.

In addition, RISC-V defines a series of instructions that allow developers to operate the CSR register:

- `csrs`: Set the specified bit in the CSR to 1.

```c
csrsi mstatus, (1 << 2)
```

The above command will set the third position of mstatus from the LSB to 1.

- `csrc`
  Set the specified bit in the CSR to 0.

```c
csrsi mstatus, (1 << 2)
```

The above instruction will set the third position of mstatus from the LSB to 0.

- `csrr`[c|s]
  Read the value of CSR into the general scratchpad.

```c
csrr to, mscratch
```

- `csrw`
  Write the value of the general scratchpad to the CSR.

```c
csrw mepc, a0
```

- `csrrw`[i]
  Write the value of csr to rd and the value of rs1 to csr .

```c
csrrw rd, csr, rs1/imm
```

Think about it from another perspective:

```c
csrrw t6, mscratch, t6
```

The above operation can interchange the values ​​of register `t6` and `mscratch`.

## Simulation

You can clone the [tinyos](https://github.com/Archfx/tinyos) repository if you havent already. If you missed the introduction episode of this series, you can check it out from [here](https://archfx.github.io/posts/2023/08/tinyos0/). Then from the docker environment, navegate to `04-TimerInterrupt` folder on the mounted repo. After you use make clean, make and other commands to build the project, you can use make qemu to start simulation. The results are as follows:

```sh
make
```

<code>riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s sys.s lib.c timer.c os.c</code>
```sh
makeqemu
```
<code>
Press Ctrl-A and then X to exit QEMU<br>
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf<br>
OS start<br>
timer_handler: 1<br>
timer_handler: 2<br>
timer_handler: 3<br>
timer_handler: 4<br>
timer_handler: 5<br>
timer_handler: 6<br>
timer_handler: 7<br>
timer_handler: 8<br>
timer_handler: 9<br>
</code>

The system will consistantly print out a message like `timer_handler: i` about once per second, which means that the time interrupt mechanism is successfully started and interrupts are performed regularly.

## Discussion

Before explaining time interruption, let us first take a look at the contents of the operating system main program [os.c](https://github.com/Archfx/tinyos/blob/master/04-TimerInterrupt/os.c).

```cpp
#include "os.h"

int os_main(void)
{
lib_puts("OS start\n");
timer_init(); // start timer interrupt ...
while (1) {} // os : do nothing, just loop!
return 0;
}
```

Basically, after this program prints `OS start`, it starts the time interrupt, and then enters the os_loop() infinite loop function and gets stuck.

But why does the system print a message like `timer_handler: i` later?

```
timer_handler: 1
timer_handler: 2
timer_handler: 3
```

This is of course caused by the time interruption mechanism!

Let's take a look at the contents of [timer.c](https://github.com/Archfx/tinyos/blob/master/04-TimerInterrupt/timer.c). Please pay special attention to the line `w_mtvec((reg_t)sys_timer)`. When a time interrupt occurs, the program will jump to the `sys_timer` macro in [sys.s](https://github.com/Archfx/tinyos/blob/master/04-TimerInterrupt/sys.s).

```cpp
#include "timer.h"

#define interval 10000000 // cycles; about 1 second in qemu.

void timer_init()
{
  // each CPU has a separate source of timer interrupts.
  int id = r_mhartid();

  // ask the CLINT for a timer interrupt.
  *(reg_t*)CLINT_MTIMECMP(id) = *(reg_t*)CLINT_MTIME + interval;

  // set the machine-mode trap handler.
  w_mtvec((reg_t)sys_timer);

  // enable machine-mode interrupts.
  w_mstatus(r_mstatus() | MSTATUS_MIE);

  // enable machine-mode timer interrupts.
  w_mie(r_mie() | MIE_MTIE);
}
```
The `sys_timer` function in [sys.s](https://github.com/Archfx/tinyos/blob/master/04-TimerInterrupt/sys.s) will use the csrr privileged instruction to temporarily store the `mepc` privileged register (the address that stores the interrupt point) in `a0` for storage. After` timer_handler() `is executed, it can do a `mret` return to the interruption point.
```c
sys_timer:
	# call the C timer_handler(reg_t epc, reg_t cause)
	csrr	a0, mepc
	csrr	a1, mcause
	call	timer_handler

	# timer_handler will return the return address via a0.
	csrw	mepc, a0

	mret # back to interrupt location (pc=mepc)
```

Note that RISC-V defines three execution modes in their privilage level extention, namely "machine mode, super mode and user mode".

All **TinyOS** tutorials  are executed in machine mode, and super mode (user mode is not used).

`mepc` means that when an interrupt occurs in machine mode, the hardware will automatically execute the action of `mepc=pc`.

When `sys_timer` executes `mret`, the hardware will execute the action of `pc=mepc`, and then jump back to the original interruption point to continue execution. (As if nothing happened)

I've provided a basic overview of the RISC-V interrupt mechanism. However, to gain a deeper understanding of the process, it's crucial to understand the machine mode-related privilege registers of the RISC-V processor, including `mhartid` (processor core identifier), `mstatus` (status register), `mie` (interrupt enable register), and more.

```cpp
#define interval 10000000 // cycles; about 1 second in qemu.

void timer_init()
{
  // each CPU has a separate source of timer interrupts.
  int id = r_mhartid();

  // ask the CLINT for a timer interrupt.
  *(reg_t*)CLINT_MTIMECMP(id) = *(reg_t*)CLINT_MTIME + interval;

  // set the machine-mode trap handler.
  w_mtvec((reg_t)sys_timer);

  // enable machine-mode interrupts.
  w_mstatus(r_mstatus() | MSTATUS_MIE);

  // enable machine-mode timer interrupts.
  w_mie(r_mie() | MIE_MTIE);
}
```
In addition, it is required to understand the memory mapping area in the RISC-V QEMU virtual machine, such as `CLINT_MTIME`, `CLINT_MTIMECMP`, etc.

The time interrupt mechanism of RISC-V is to compare the two values ​​​​of `CLINT_MTIME` and `CLINT_MTIMECMP`. When `CLINT_MTIME` exceeds `CLINT_MTIMECMP`, an interrupt occurs.

Therefore, the `timer_init()` function has the following instructions

```cpp
 *(reg_t*)CLINT_MTIMECMP(id) = *(reg_t*)CLINT_MTIME + interval;
```

This command is to set the first interruption time.

Similarly, in timer_handler of [timer.c](https://github.com/Archfx/tinyos/blob/master/04-TimerInterrupt/timer.c), you also need to set the next interrupt time as illustrated in below code.

```cpp
reg_t timer_handler(reg_t epc, reg_t cause)
{
  reg_t return_pc = epc;
  // disable machine-mode timer interrupts.
  w_mie(~((~r_mie()) | (1 << 7)));
  lib_printf("timer_handler: %d\n", ++timer_count);
  int id = r_mhartid();
  *(reg_t *)CLINT_MTIMECMP(id) = *(reg_t *)CLINT_MTIME + interval;
  // enable machine-mode timer interrupts.
  w_mie(r_mie() | MIE_MTIE);
  return return_pc;
}
```

In this way, the next time the `CLINT_MTIMECMP` time comes, `CLINT_MTIME` will be greater than `CLINT_MTIMECMP`, and the interrupt will occur again.

In this episode of **TinyOS**, we looked the process of generating TimerInterrupts. This is a huge increment of the process of implementing preemptive muti tasking. In the Next episode, we will be specifically looking at that!

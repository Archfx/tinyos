# ExternInterrupt

# 07-ExterInterrupt -- RISC-V embedded operating system

## Prerequisite knowledge

###PIC

PIC (Programmable Interrupt Controller) is a special-purpose circuit that helps the processor handle interrupt requests from different sources (simultaneously). It helps prioritize IRQs, allowing CPU execution to switch to the most appropriate interrupt handler.

### Interrupt

Let’s first review the types of interrupts in RISC-V, which can be broken down into several major items:

- Local Interrupt
  - Software Interrupt
  - Timer Interrupt
- Global Interrupt
  - External Interrupt

The Exception Code of various interrupts is also defined in detail in the specification:

![](https://camo.githubusercontent.com/9f3e34c3f929a4b693a1c198586e0a67c78f8e3d42773fafde0746355196030d/68747470733a2f2f692e696d6775722e636f6d2f7a6d756b6e51722e706e67)

> Exception code will be recorded in the mcause register.

If we want system programs running in RISC-V to support interrupt processing, we also need to set the field value of the MIE Register:
```cpp
// Machine-mode Interrupt Enable
#define MIE_MEIE (1 << 11) // external
#define MIE_MTIE (1 << 7)  // timer
#define MIE_MSIE (1 << 3)  // software
// enable machine-mode timer interrupts.
w_mie(r_mie() | MIE_MTIE);
```

### PLIC

After roughly reviewing the interrupt handling introduced previously, let us return to the focus of this article: **PLIC**.
PLIC (Platform-Level Interrupt Controller) is a PIC built for the RISC-V platform.
In fact, there will be multiple interrupt sources (keyboard, mouse, hard disk...) connected to PLIC. PLIC will determine the priority of these interrupts and then allocate them to the processor's Hart (the minimum hardware thread in RISC-V). unit) for interrupt processing.

###IRQ

> In computer science, an interrupt means that the processor receives a signal from hardware or software, indicating that an event has occurred and should be noted. This situation is called an interrupt. Usually, after receiving an asynchronous signal from peripheral hardware or a synchronous signal from software, the processor will perform corresponding hardware/software processing. Sending such a signal is called an interrupt request (IRQ). -- wikipedia
Taking the RISC-V virtual machine - Virt in Qemu as an example, its [source code](https://github.com/qemu/qemu/blob/master/include/hw/riscv/virt.h) defines IRQs for different interrupts:

```cpp
enum {
    UART0_IRQ = 10,
    RTC_IRQ = 11,
    VIRTIO_IRQ = 1, /* 1 to 8 */
    VIRTIO_COUNT = 8,
    PCIE_IRQ = 0x20, /* 32 to 35 */
    VIRTIO_NDEV = 0x35 /* Arbitrary maximum number of interrupts */
};
```

When we are writing an operating system, we can use the IRQ code to identify the type of external interrupt and solve the problems of keyboard input and disk reading and writing. Regarding these contents, the author will give a more in-depth introduction in subsequent articles.

### Memory Map of PLIC

As for how we should communicate with PLIC?
PLIC adopts a Memory Map mechanism, which maps some important information to Main Memory. In this way, we can communicate with PLIC by accessing the memory.
We can continue to see [Virt’s source code](https://github.com/qemu/qemu/blob/master/hw/riscv/virt.c), which defines the virtual location of PLIC:
```cpp
static const MemMapEntry virt_memmap[] = {
    [VIRT_DEBUG] =       {        0x0,         0x100 },
    [VIRT_MROM] =        {     0x1000,        0xf000 },
    [VIRT_TEST] =        {   0x100000,        0x1000 },
    [VIRT_RTC] =         {   0x101000,        0x1000 },
    [VIRT_CLINT] =       {  0x2000000,       0x10000 },
    [VIRT_PCIE_PIO] =    {  0x3000000,       0x10000 },
    [VIRT_PLIC] =        {  0xc000000, VIRT_PLIC_SIZE(VIRT_CPUS_MAX * 2) },
    [VIRT_UART0] =       { 0x10000000,         0x100 },
    [VIRT_VIRTIO] =      { 0x10001000,        0x1000 },
    [VIRT_FW_CFG] =      { 0x10100000,          0x18 },
    [VIRT_FLASH] =       { 0x20000000,     0x4000000 },
    [VIRT_PCIE_ECAM] =   { 0x30000000,    0x10000000 },
    [VIRT_PCIE_MMIO] =   { 0x40000000,    0x40000000 },
    [VIRT_DRAM] =        { 0x80000000,           0x0 },
};
```
Each PLIC interrupt source will be represented by a temporary register. By adding `PLIC_BASE` to the offset `offset` of the temporary register, we can know the location where the temporary register is mapped to the main memory.

```
0xc000000 (PLIC_BASE) + offset = Mapped Address of register
```
## Let’s get to the point: enable mini-riscv-os to support external interrupts

First, see `plic_init()`, which is defined in `plic.c`:

```cpp
void plic_init()
{
  int hart = r_tp();
  // QEMU Virt machine support 7 priority (1 - 7),
  // The "0" is reserved, and the lowest priority is "1".
  *(uint32_t *)PLIC_PRIORITY(UART0_IRQ) = 1;

  /* Enable UART0 */
  *(uint32_t *)PLIC_MENABLE(hart) = (1 << UART0_IRQ);

  /* Set priority threshold for UART0. */

  *(uint32_t *)PLIC_MTHRESHOLD(hart) = 0;

  /* enable machine-mode external interrupts. */
  w_mie(r_mie() | MIE_MEIE);

  // enable machine-mode interrupts.
  w_mstatus(r_mstatus() | MSTATUS_MIE);
}
```
Seeing the above example, `plic_init()` mainly performs these initialization actions:

- Set the priority of UART_IRQ
  Because PLIC can manage multiple external interrupt sources, we must set priorities for different interrupt sources. When these interrupt sources conflict, PLIC will know which IRQ to process first.
- Enable UART interrupt for hart0
- Set threshold
  IRQs less than or equal to this threshold will be ignored by PLIC. If we change the example to:

```cpp
*(uint32_t *)PLIC_MTHRESHOLD(hart) = 10;
```

In this way, the system will not process the UART's IRQ.

- Enable external interrupts and global interrupts in Machine mode
  It should be noted that this project originally used `trap_init()` to enable global interrupts in Machine mode. After this modification, we changed `plic_init()` to be responsible.

> In addition to PLIC that needs to be initialized, UART also needs to be initialized, such as setting **baud rate** and other actions. `uart_init()` is defined in `lib.c`. Interested readers can do it themselves Check.

### Modify Trap Handler

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

Previously, `trap_handler()` only supported the processing of time interrupts. This time we want to make it support the processing of external interrupts:
```cpp
/* In trap.c */
void external_handler()
{
  int irq = plic_claim();
  if (irq == UART0_IRQ)
  {
    lib_isr();
  }
  else if (irq)
  {
    lib_printf("unexpected interrupt irq = %d\n", irq);
  }

  if (irq)
  {
    plic_complete(irq);
  }
}
```

Because the goal this time is to enable the operating system to process UART IRQ, it is not difficult to find through the above code that we only process UART:
```cpp
/* In lib.c */
void lib_isr(void)
{
    for (;;)
    {
        int c = lib_getc();
        if (c == -1)
        {
            break;
        }
        else
        {
            lib_putc((char)c);
            lib_putc('\n');
        }
    }
}
```

The principle of `lib_isr()` is also quite simple. It just repeatedly detects whether the UART's RHR register has received new data. If it is empty (c == -1), it jumps out of the loop.

> Registers related to UART are defined in `riscv.h`. This time, some register addresses have been added to support `lib_getc()`. The general contents are as follows:
>
> ```cpp
> #define UART 0x10000000L
> #define UART_THR (volatile uint8_t *)(UART + 0x00) // THR:transmitter holding register
> #define UART_RHR (volatile uint8_t *)(UART + 0x00) // RHR:Receive holding register
> #define UART_DLL (volatile uint8_t *)(UART + 0x00) // LSB of Divisor Latch (write mode)
> #define UART_DLM (volatile uint8_t *)(UART + 0x01) // MSB of Divisor Latch (write mode)
> #define UART_IER (volatile uint8_t *)(UART + 0x01) // Interrupt Enable Register
> #define UART_LCR (volatile uint8_t *)(UART + 0x03) // Line Control Register
> #define UART_LSR (volatile uint8_t *)(UART + 0x05) // LSR:line status register
> #define UART_LSR_EMPTY_MASK 0x40                   // LSR Bit 6: Transmitter empty; both the THR and LSR are empty
> ```

The content of the modifications submitted this time is roughly as above. There are some implementation details that are not specifically mentioned. It is recommended that interested readers can trace the source code directly. I believe it will be more rewarding.
With these basics in place, you can then add things like:

- virtio driver & file system
- system call
- mini shell
  and other functions to make **TinyOS** more scalable.

## Reference

- [Step by step, learn to develop an operating system on RISC-V](https://github.com/plctlab/riscv-operating-system-mooc)
- [Qemu](https://github.com/qemu/qemu)
- [AwesomeCS wiki](https://github.com/ianchen0119/AwesomeCS/wiki/2-5-RISC-V::%E4%B8%AD%E6%96%B7%E8%88%87%E7%95%B0%E5%B8%B8%E8%99%95%E7%90%86----PLIC-%E4%BB%8B%E7%B4%B9)


## Build & Run

```sh
cd 07-ExterInterrupt 
$ make
riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -T os.ld -o os.elf start.s sys.s lib.c timer.c task.c os.c user.c trap.c lock.c plic.c

cd 07-ExterInterrupt (feat/getchar)
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
OS: Activate next task
Task0: Created!
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
external interruption!
j
Task0: Running...
Task0: Running...
external interruption!
k
Task0: Running...
Task0: Running...
Task0: Running...
external interruption!
j
Task0: Running...
external interruption!
k
external interruption!
j
Task0: Running...
timer interruption!
timer_handler: 1
OS: Back to OS
QEMU: Terminated
```

## Debug mode

```sh
make debug
riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -T os.ld -o os.elf start.s sys.s lib.c timer.c task.c os.c user.c trap.c lock.c
Press Ctrl-C and then input 'quit' to exit GDB and QEMU
-------------------------------------------------------
Reading symbols from os.elf...
Breakpoint 1 at 0x80000000: file start.s, line 7.
0x00001000 in ?? ()
=> 0x00001000:  97 02 00 00     auipc   t0,0x0

Thread 1 hit Breakpoint 1, _start () at start.s:7
7           csrr t0, mhartid                # read current hart id
=> 0x80000000 <_start+0>:       f3 22 40 f1     csrr    t0,mhartid
(gdb)
```

### set the breakpoint

You can set the breakpoint in any c file:

```sh
(gdb) b trap.c:27
Breakpoint 2 at 0x80008f78: file trap.c, line 27.
(gdb)
```

As the example above, when process running on trap.c, line 27 (Timer Interrupt).
The process will be suspended automatically until you press the key `c` (continue) or `s` (step).

# External Interrupts

A computer needs to communicate with the external world to perform tasks. To facilitate this, we have peripheral hardware. When these peripherals need to talk to the operating system, we have interrupts. In this episode of **TinyOS**🐞 tutorial series, we will be looking at interrupts and how to use them.



### Programmable Interrupt Controller

A Programmable Interrupt Controller (PIC) is a hardware component in the system that is crucial for managing interrupt requests (IRQs) from various peripherals. Its primary function is to prioritize interrupt signals from hardware peripherals based on their urgency and importance, making sure that critical tasks are handled promptly. When an interrupt occurs, the PIC suspends the CPU's current task and directs it to an interrupt handler, which manages the interrupt and executes necessary actions. The PIC also allows for interrupt masking and priority configuration, enabling system designers to customize interrupt handling according to specific requirements. While modern computer systems may utilize more advanced interrupt controllers like the Advanced Programmable Interrupt Controller (APIC), the fundamental role of prioritizing and managing interrupts remains essential for efficient system operation.

### Interrupt

Let’s first review the types of interrupts in RISC-V, which can be broken down into several major categories:

- Local Interrupt
  - Software Interrupt
  - Timer Interrupt
- Global Interrupt
  - External Interrupt

The Exception Code of various interrupts is also defined in detail in the RISC-V specification


> Specifically, the exception code will be recorded in the mcause register.

If we want system programs running in RISC-V to support interrupt processing, we also need to set the field value of the MIE Register:
```cpp
// Machine-mode Interrupt Enable
#define MIE_MEIE (1 << 11) // external
#define MIE_MTIE (1 << 7)  // timer
#define MIE_MSIE (1 << 3)  // software
// enable machine-mode timer interrupts.
w_mie(r_mie() | MIE_MTIE);
```

### PIC in RISC-V

RISC-V has its own Programmable Interrupt Controller implementation known as Platform-Level Interrupt Controller (PLIC). As we discussed earlier, there can be multiple interrupt sources (keyboard, mouse, hard disk...) connected to PLIC of a system. PLIC will determine the priority of these interrupts and then allocate them to the processor's Hart (the minimum hardware thread in RISC-V) for processing by the CPU.

### Interrupt Request

An Interrupt Request is also known as IRQ, is a mechanism used by hardware devices to signal the CPU that they need attention or service. When a hardware device requires the CPU to perform a task, such as processing incoming data or handling an event, it sends an interrupt request. The CPU then temporarily suspends its current operation, saves its state, and jumps to a predefined location in memory known as an interrupt handler. This handler executes the necessary actions to address the request from the device. IRQs are assigned unique numerical identifiers, typically ranging from 0 to 15 in legacy systems, to distinguish between different interrupt sources. Each IRQ is associated with specific hardware components, such as keyboards, mice, storage devices, or network cards, allowing the CPU to prioritize and handle interrupts appropriately.
Taking the RISC-V virtual machine - Virt in Qemu as an example, its [source code](https://github.com/qemu/qemu/blob/master/include/hw/riscv/virt.h) defines IRQs for different interrupts as follows:

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

When we are writing an operating system, we can use the IRQ code to identify the type of external interrupt and solve the problems of keyboard input and disk reading and writing.

### Configuring the PIC

As the name of PIC suggests, it can be programmed. For this purpose, PLIC adopts a Memory Map mechanism, which maps some important information to Main Memory. In this way, we can communicate with PLIC by accessing the memory. We can find these memory map definitions in [Virt’s source code](https://github.com/qemu/qemu/blob/master/hw/riscv/virt.c), which defines the virtual locations of PLIC as follows,
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
Each PIC interrupt source will be represented by a temporary register. By adding `PLIC_BASE` to the offset `offset` of the temporary register, we can know the location where the temporary register is mapped to the main memory.

```sh
0xc000000 (PLIC_BASE) + offset = Mapped Address of register
```


## Interrupts to TinyOS

I think so far we looked at the background of the interrupts. Let's add this functionality to the TinyOS operating system. First, we need to initialize Virt's PLIC controller. For that, we use the `plic_init()` function, which is defined in [plic.c](https://github.com/Archfx/tinyos/blob/master/07-ExterInterrupt/plic.c):

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
As shown in the above example, `plic_init()` mainly performs following initialization actions:

- Set the priority of UART_IRQ. Since PLIC can manage multiple external interrupt sources, we must set priorities for different interrupt sources. Then in case of conflicting requests, PLIC will know which IRQ to process first.
- Enable UART interrupt for hart0
- Set threshold. IRQs less than or equal to this threshold will be ignored by PLIC. We can configure the threshold using,
```cpp
*(uint32_t *)PLIC_MTHRESHOLD(hart) = 10;
```
In this way, the system will not process the UART's IRQ.

- Enable external interrupts and global interrupts in Machine mode. It should be noted that this project originally used `trap_init()` to enable global interrupts in Machine mode. After this modification, we changed `plic_init()` to be responsible.

Note that the peripherals also need configuration. In the case of UART, settings such as **baud rate** and other actions. `uart_init()` is defined in [lib.c](https://github.com/Archfx/tinyos/blob/master/07-ExterInterrupt/lib.c).

### Modify Trap Handler

We discussed about trap hander in the episode [Preemptive Scheduling](https://archfx.github.io/posts/2024/04/tinyos5/). You might remember the following diagram.


<pre class="mermaid">
graph LR
    C[trap_handler] --> D[soft_handler]
    C --> E[timer_handler]
    C --> F[exter_handler]

</pre>

Previously in [Preemptive Scheduling](https://archfx.github.io/posts/2024/04/tinyos5/), `trap_handler()` only supported the processing of time interrupts. This time we want to make it support the processing of external interrupts as well.
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

Because the goal this time is to enable the operating system to process UART IRQ, we need to add that to the interrupt request as above. This will invoke the function `lib_isr()`. 
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

The principle of `lib_isr()` is quite simple. It just repeatedly detects whether the UART's RHR register has received new data. If it is empty (c == -1), it jumps out of the loop. Registers related to UART are defined in [riscv.h](https://github.com/Archfx/tinyos/blob/master/07-ExterInterrupt/riscv.h). Some register addresses have been added to support `lib_getc()`. The general definitions of UART registers are as follows:

 ```cpp
 #define UART 0x10000000L
 #define UART_THR (volatile uint8_t *)(UART + 0x00) // THR:transmitter holding register
 #define UART_RHR (volatile uint8_t *)(UART + 0x00) // RHR:Receive holding register
 #define UART_DLL (volatile uint8_t *)(UART + 0x00) // LSB of Divisor Latch (write mode)
 #define UART_DLM (volatile uint8_t *)(UART + 0x01) // MSB of Divisor Latch (write mode)
 #define UART_IER (volatile uint8_t *)(UART + 0x01) // Interrupt Enable Register
 #define UART_LCR (volatile uint8_t *)(UART + 0x03) // Line Control Register
 #define UART_LSR (volatile uint8_t *)(UART + 0x05) // LSR:line status register
 #define UART_LSR_EMPTY_MASK 0x40                   // LSR Bit 6: Transmitter empty; both the THR and LSR are empty
 ```



## Simulation

Let's see the TinyOS interrupt handler in action. If you have followed the tutorial series continuously, you know the steps.

```sh
cd 07-ExterInterrupt 
make
```
<code>
riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -T os.ld -o os.elf start.s sys.s lib.c timer.c task.c os.c user.c trap.c lock.c plic.c
</code>

Next, you can run the Virt and type letters into the terminal, which will generate interrupt requests.

```sh
make qemu
```
<code>
Press Ctrl-A and then X to exit QEMU<br>
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf<br>
OS start<br>
OS: Activate next task<br>
Task0: Created!<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
external interruption!<br>
j<br>
Task0: Running...<br>
Task0: Running...<br>
external interruption!<br>
k<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
external interruption!<br>
j<br>
Task0: Running...<br>
external interruption!<br>
k<br>
external interruption!<br>
j<br>
Task0: Running...<br>
timer interruption!<br>
timer_handler: 1<br>
OS: Back to OS<br>
QEMU: Terminated<br>
</code>

In this episode, we have looked at configuring external peripherals and generating interrupts with that. I hope this was an interesting episode since this basic functionality is required when you are dealing with embedded systems in the future.

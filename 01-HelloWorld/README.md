# HelloWorld I/O program

In this series of articles, we will introduce how to build an embedded operating system on a RISC-V processor, the operating system name is mini-riscv-os. (actually a series of programs, not a single system)

First of all, in this chapter, we will introduce how to write the simplest program that can print `Hello World!`!

## Quick Run

```shell
cd 01-HelloWorld 
make clean
```
<code>rm -f *.elf</code>

```shell
make 
```
<code>riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s os.c</code>

```shell
$ make qemu
```

<code>
Press Ctrl-A and then X to exit QEMU</br>
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf<br>
Hello OS!</code>

## os.c

Find the file [here](https://github.com/Archfx/tinyos/blob/master/01-HelloWorld/os.c)

```cpp
#include <stdint.h>

#define UART        0x10000000
#define UART_THR    (uint8_t*)(UART+0x00) // THR:transmitter holding register
#define UART_LSR    (uint8_t*)(UART+0x05) // LSR:line status register
#define UART_LSR_EMPTY_MASK 0x40          // LSR Bit 6: Transmitter empty; both the THR and LSR are empty

int lib_putc(char ch) {
	while ((*UART_LSR & UART_LSR_EMPTY_MASK) == 0);
	return *UART_THR = ch;
}

void lib_puts(char *s) {
	while (*s) lib_putc(*s++);
}

int os_main(void)
{
	lib_puts("Hello OS!\n");
	while (1) {}
	return 0;
}
```

The preset RISC-V virtual machine in QEMU is called virt, and the UART memory mapping location starts from 0x10000000, and the mapping method is as follows:

```
UART MemoryMapped IO

0x10000000 THR (Transmitter Holding Register) RHR (Receive Holding Register)
0x10000001 IER (Interrupt Enable Register)
0x10000002 ISR (Interrupt Status Register)
0x10000003 LCR (Line Control Register)
0x10000004 MCR (Modem Control Register)
0x10000005 LSR (Line Status Register)
0x10000006 MSR (Modem Status Register)
0x10000007 SPR (Scratch Pad Register)
```

As long as we send a certain character to the THR of the UART, the character can be printed out, but before sending it, we must confirm whether the sixth bit of the LSR is 1 (meaning that the UART transmission area is empty and can be transmitted).

```
THR Bit 6: Transmitter empty; both the THR and shift register are empty if this is set.
```

So we wrote the following function to send a character to the UART for printing out to the host. (Because the embedded system usually does not have a display device, it will be sent back to the host for display)

```cpp
int lib_putc(char ch) {
	while ((*UART_LSR & UART_LSR_EMPTY_MASK) == 0);
	return *UART_THR = ch;
}
```

Once a word can be printed, a large string of words can be printed with the following lib_puts(s).

```cpp
void lib_puts(char *s) {
	while (*s) lib_putc(*s++);
}
```

So our main program calls lib_puts to print `Hello OS!`.

```cpp
int os_main(void)
{
	lib_puts("Hello World!\n");
	while (1) {}
	return 0;
}
```

Although our main program is only a short 22 lines, the 01-HelloOs project includes not only the main program, but also the startup program start.s, the link file os.ld, and the configuration file Makefile.

## Project build configuration file Makefile

The Makefile in mini-riscv-os is usually similar, the following is the Makefile of 01-HelloOs.

```Makefile
CC = riscv32-unknown-elf-gcc
CFLAGS = -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32

QEMU = qemu-system-riscv32
QFLAGS = -nographic -smp 4 -machine virt -bios none

OBJDUMP = riscv32-unknown-elf-objdump

all: os.elf

os.elf: start.s os.c
	$(CC) $(CFLAGS) -T os.ld -o os.elf $^

qemu: $(TARGET)
	@qemu-system-riscv32 -M ? | grep virt >/dev/null || exit
	@echo "Press Ctrl-A and then X to exit QEMU"
	$(QEMU) $(QFLAGS) -kernel os.elf

clean:
	rm -f *.elf
```

Some of the Makefile syntax is not easy to understand, especially the following symbols:

```
$@ : the target file for this rule (Target file)
$* : represents the files specified by targets, but does not contain the file extension
$< : the first dependency file in the list of dependency files (Dependencies file)
$^ : all dependent files in the dependent file list
$? : A list of files in the dependent file list that are newer than the target file
$* : represents the files specified by targets, but does not contain the file extension

?= Syntax: If the variable is undefined, assign it a new value.
:= Syntax: make will expand the entire Makefile and then determine the value of the variable.
```

So the following two lines in the above Makefile:

```Makefile
os.elf: start.s os.c
	$(CC) $(CFLAGS) -T os.ld -o os.elf $^
```

The `$^` in it is replaced by `start.s os.c`, so the entire line `$(CC) $(CFLAGS) -T os.ld -o os.elf $^` becomes the following instructions.

```
riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s os.c
```

In the Makefile, we use riscv32-unknown-elf-gcc to compile, and then use qemu-system-riscv32 to execute. The execution process of 01-HelloOs is as follows:

```
cd 01-HelloOs (master)
$ make clean
rm -f *.elf

cd 01-HelloOs (master)
$ make
riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s os.c

cd 01-HelloOs (master)
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
Hello OS!
QEMU: Terminated
```

First use make clean to clear the last compilation output, then use make to call the riscv32-unknown-elf-gcc compilation project, the following is the complete compilation instruction

```
$ riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s os.c
```

Among them, `-march=rv32ima` means that we want to [generate code for 32-bit I+M+A instruction set](https://www.sifive.com/blog/all-aboard-part-1-compiler-args) :

```
I: Basic Integer Instruction Set (Integer)
M: Include multiplication and division (Multiply)
A: Contains atomic instructions (Atomic)
C: Use 16-bit compression (Compact) -- Note: We did not add C, so the instruction machine code generated is purely 32-bit instructions, not compressed into 16-bit, because we want the instruction length to be the same, from the beginning to the end The tail is 32 bits.
```

And `-mabi=ilp32` indicates that the integer of the generated binary object code is based on a 32-bit architecture.

- ilp32: int, long, and pointers are all 32-bits long. long long is a 64-bit type, char is 8-bit, and short is 16-bit.
- lp64: long and pointers are 64-bits long, while int is a 32-bit type. The other types remain the same as ilp32.

There is also the `-mcmodel=medany` parameter, which means that the generated symbol address must be within 2GB, and can be addressed by static linking.

- `-mcmodel=medany`
    * Generate code for the medium-any code model. The program and its statically defined symbols must be within any single 2 GiB address range. Programs can be statically or dynamically linked.

More detailed RISC-V gcc parameters can refer to the following documents:

* https://gcc.gnu.org/onlinedocs/gcc/RISC-V-Options.html

In addition, the two parameters `-nostdlib -fno-builtin` are used to indicate that the standard library should not be linked (because it is an embedded system, the library usually needs to be self-made), please refer to the following documents:

* https://gcc.gnu.org/onlinedocs/gcc/Link-Options.html


## Link Script link file (os.ld)

There is also the `-T os.ld` parameter specifying the link script as the os.ld file as follows: (link script is a guide file describing how to put the program segment TEXT, data segment DATA and BSS uninitialized data segment into the memory respectively)

```ld
OUTPUT_ARCH( "riscv" )

ENTRY( _start )

MEMORY
{
  ram   (wxa!ri) : ORIGIN = 0x80000000, LENGTH = 128M
}

PHDRS
{
  text PT_LOAD;
  data PT_LOAD;
  bss PT_LOAD;
}

SECTIONS
{
  .text : {
    PROVIDE(_text_start = .);
    *(.text.init) *(.text .text.*)
    PROVIDE(_text_end = .);
  } >ram AT>ram :text

  .rodata : {
    PROVIDE(_rodata_start = .);
    *(.rodata .rodata.*)
    PROVIDE(_rodata_end = .);
  } >ram AT>ram :text

  .data : {
    . = ALIGN(4096);
    PROVIDE(_data_start = .);
    *(.sdata .sdata.*) *(.data .data.*)
    PROVIDE(_data_end = .);
  } >ram AT>ram :data

  .bss :{
    PROVIDE(_bss_start = .);
    *(.sbss .sbss.*) *(.bss .bss.*)
    PROVIDE(_bss_end = .);
  } >ram AT>ram :bss

  PROVIDE(_memory_start = ORIGIN(ram));
  PROVIDE(_memory_end = ORIGIN(ram) + LENGTH(ram));
}
```

## Start the program (start.s)

In addition to the main program, an embedded system usually needs a startup program written in assembly language. The content of the startup program start.s in 01-HelloOs is as follows: are asleep, which makes things simpler and does not need to consider too many parallel processing issues).
 
```s
.equ STACK_SIZE, 8192

.global _start

_start:
    # setup stacks per hart
    csrr t0, mhartid                # read current hart id
    slli t0, t0, 10                 # shift left the hart id by 1024
    la   sp, stacks + STACK_SIZE    # set the initial stack pointer 
                                    # to the end of the stack space
    add  sp, sp, t0                 # move the current hart stack pointer
                                    # to its place in the stack space

    # park harts with id != 0
    csrr a0, mhartid                # read current hart id
    bnez a0, park                   # if we're not on the hart 0
                                    # we park the hart

    j    os_main                    # hart 0 jump to c

park:
    wfi
    j park

stacks:
    .skip STACK_SIZE * 4            # allocate space for the harts stacks

```

## Execute with QEMU

And when you enter make qemu, Make will execute the following commands

```
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
```

It means to use qemu-system-riscv32 to execute the os.elf kernel file, `-bios none` does not use basic input and output bios, `-nographic` does not use drawing mode, and the specified machine architecture is `-machine virt`, also It is the RISC-V virtual machine virt preset by QEMU.

So when you enter `make qemu`, you will see the following screen!
```
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
Hello OS!
QEMU: Terminated
```

This is the basic appearance of the simplest Hello program in the RISC-V embedded system.




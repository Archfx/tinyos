# ContextSwitch

## Build & Run

```sh
cd 02-ContextSwitch 
$ make clean
rm -f *.elf

cd 02-ContextSwitch 
$ make 
riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -T os.ld -o os.elf start.s sys.s lib.c os.c

cd 02-ContextSwitch 
$ make qemu
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -kernel os.elf
OS start
Task0: Context Switch Success !
QEMU: Terminated
```

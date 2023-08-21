# Hello OS

## Build & Run

```shell
cd 01-HelloOs 
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


# 10-SystemCall

## Build & Run

```
austin@AustindeMacBook-Air   ~/Desktop/riscv/austin362667/mini-riscv-os/10-SystemCall     master  INSERT  make all              3309  0.75G   1.52    10:34:23 
rm -f *.elf *.img
riscv64-unknown-elf-gcc -I./include -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -w -D CONFIG_SYSCALL -T os.ld -o os.elf src/start.s src/sys.s src/mem.s src/lib.c src/timer.c src/os.c src/task.c src/user.c src/trap.c src/lock.c src/plic.c src/virtio.c src/string.c src/alloc.c src/syscall.c src/usys.s
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -drive if=none,format=raw,file=hdd.dsk,id=x0 -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 -kernel os.elf
HEAP_START = 8001500c, HEAP_SIZE = 07feaff4, num of pages = 521903
TEXT:   0x80000000 -> 0x8000af2c
RODATA: 0x8000af2c -> 0x8000b490
DATA:   0x8000c000 -> 0x8000c004
BSS:    0x8000d000 -> 0x8001500c
HEAP:   0x80095100 -> 0x88000000
OS start
Disk init work is success!
buffer init...
block read...
Virtio IRQ
00000050
0000002f
00000009
00000039
0000009f
000000ce
00000037
0000003d
000000df
0000003a

p = 0x80095100
p2 = 0x80095500
p3 = 0x80095700
OS: Activate next task
Task0: Created!
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
timer_handler: 1
OS: Back to OS

OS: Activate next task
Task4: Created!
Environment call from M-mode!
syscall_num: 1
--> sys_gethid, arg0 = 0x8000dc7f
ptr_hid != NULL
system call returned!, hart id is 0
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
Task4: Running...
timer_handler: 2
OS: Back to OS

OS: Activate next task
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
QEMU: Terminated
```
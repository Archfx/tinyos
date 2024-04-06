# Spinlocks



We can roughly guess the function of Spinlock through the name. Like Mutex, Spinlock can be used to protect Critical section. If the execution thread does not acquire the lock, it will enter a loop until it is eligible to be locked, so it is called a spin lock.

### Atomic operations

Atomic operations can ensure that an operation will not be interrupted by other operations before completion. Taking RISC-V as an example, it provides RV32A Instruction set, which are all atomic operations (Atomic).

In order to avoid multiple Spinlocks accessing the same memory at the same time, atomic operations are used in the Spinlock implementation to ensure correct locking.

> In fact, not only Spinlock, mutex lock also requires Atomic operation in implementation.

### Create a simple Spinlock in C language

Consider the following code:
```cpp
typedef struct spinlock{
    volatile uint lock;
} spinlock_t;
void lock(spinlock_t *lock){
    while(xchg(lock−>lock, 1) != 0);
}
void unlock(spinlock_t *lock){
    lock->lock = 0;
}
```

Through the sample code, you can notice a few points:

- `volatile` keyword for lock
  Using the `volatile` keyword lets the compiler know that the variable may be accessed in unexpected circumstances, so do not optimize the variable's instructions to avoid storing the result in the Register, but write it directly to memory.
- lock function
  [`xchg(a,b)`]() The contents of the two variables a and b can be swapped, and the function is an atomic operation. When the lock value is not 0, the execution thread will spin and wait until the lock is 0 (that is, it can be locked )until.
- unlock function
  Since only one thread can obtain the lock at the same time, there is no need to worry about preemption of access when unlocking. Because of this, the example does not use atomic operations.

## Spin lock in mini-riscv-os

### basic lock

First of all, since mini-riscv-os is a Single Hart operating system, in addition to using atomic operations, there is actually a very simple way to achieve the Lock effect:

```cpp
void basic_lock()
{
  w_mstatus(r_mstatus() & ~MSTATUS_MIE);
}

void basic_unlock()
{
  w_mstatus(r_mstatus() | MSTATUS_MIE);
}
```

In [lock.c], we implement a very simple lock. When we call `basic_lock()` in the program, the system's machine mode interrupt mechanism will be turned off. In this way, we can ensure that no There are other programs accessing the Shared memory to avoid the occurrence of Race condition.

### spinlock

The above lock has an obvious flaw: **When the program that acquires the lock has not released the lock, the entire system will be Block**. In order to ensure that the operating system can still maintain the multi-tasking mechanism, we must implement more complex locks :

- [os.h]
- [lock.c]
- [sys.s]

```cpp
typedef struct lock
{
  volatile int locked;
} lock_t;

void lock_init(lock_t *lock)
{
  lock->locked = 0;
}

void lock_acquire(lock_t *lock)
{
  for (;;)
  {
    if (!atomic_swap(lock))
    {
      break;
    }
  }
}

void lock_free(lock_t *lock)
{
  lock->locked = 0;
}
```

In fact, the above program code is basically the same as the previous example of Spinlock. When we implement it in the system, we only need to deal with one more troublesome problem, which is to implement the atomic swap action `atomic_swap()`:

```c
.globl atomic_swap
.align 4
atomic_swap:
        li a5, 1
        amoswap.w.aq a5, a5, 0(a0)
        mv a0, a5
        ret
```

In the above program, we read locked in the lock structure, exchange it with the value `1`, and finally return the contents of the register `a5`.
Further summarizing the execution results of the program, we can draw two Cases:

1. Successfully acquire the lock
   When `lock->locked` is `0`, after the exchange through `amoswap.w.aq`, the value of `lock->locked` is `1` and the return value (Value of a5) is `0`:

```cpp
void lock_acquire(lock_t *lock)
{
  for (;;)
  {
    if (!atomic_swap(lock))
    {
      break;
    }
  }
}
```

When the return value is `0`, `lock_acquire()` will successfully jump out of the infinite loop and enter Critical sections for execution. 2. No lock acquired
Otherwise, continue to try to obtain the lock in an infinite loop.

## Further reading

If you are interested in `Race Condition`, `Critical sections`, and `Mutex`, you can read the Parallel Programming section in [AwesomeCS Wiki](https://github.com/ianchen0119/AwesomeCS/wiki).

## Build & Run

```sh
cd 06-Spinlock 
$ make
riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -T os.ld -o os.elf start.s sys.s lib.c timer.c task.c os.c user.c trap.c lock.c

cd 06-Spinlock (feat/spinlock)
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
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
timer interruption!
timer_handler: 1
OS: Back to OS

OS: Activate next task
Task1: Created!
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
Task1: Running...
timer interruption!
timer_handler: 2
OS: Back to OS

OS: Activate next task
Task2: Created!
The value of shared_var is: 550
The value of shared_var is: 600
The value of shared_var is: 650
The value of shared_var is: 700
The value of shared_var is: 750
The value of shared_var is: 800
The value of shared_var is: 850
The value of shared_var is: 900
The value of shared_var is: 950
The value of shared_var is: 1000
The value of shared_var is: 1050
The value of shared_var is: 1100
The value of shared_var is: 1150
The value of shared_var is: 1200
The value of shared_var is: 1250
The value of shared_var is: 1300
The value of shared_var is: 1350
The value of shared_var is: 1400
The value of shared_var is: 1450
The value of shared_var is: 1500
The value of shared_var is: 1550
The value of shared_var is: 1600
timer interruption!
timer_handler: 3
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
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
timer interruption!
timer_handler: 4
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

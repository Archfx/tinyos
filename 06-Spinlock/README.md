# Spinlocks

In this episode of  episode of the **TinyOS**🐞 tutorial series, we will be looking at how to protect critical sections in processes using spinlocks.  

## What is a Spinlock
A spinlock is a synchronization mechanism used to protect shared resources (such as data structures) from being accessed simultaneously by multiple threads of execution. Unlike other synchronization primitives like mutexes or semaphores, which typically put threads to sleep when the resource they're trying to access is unavailable, a spinlock causes a thread trying to acquire the lock to repeatedly "spin" in a loop (i.e., continuously checking the lock's state) until it becomes available.

The basic idea behind a spinlock is simple: when a thread wants to acquire the lock, it checks to see if the lock is available. If it is, the thread acquires the lock and continues execution. If the lock is not available (i.e., another thread holds it), the thread continuously polls the lock until it becomes available, at which point it acquires the lock and proceeds.


## Atomic operations

Atomic operations can ensure that an operation will not be interrupted by other operations before completion. Taking RISC-V as an example, it provides RV32A Instruction set, which are all atomic operations (Atomic).

In order to avoid multiple Spinlocks accessing the same memory at the same time, atomic operations are used in the Spinlock to ensure correct locking logic implementation.

> In fact, not only Spinlock, mutex lock also requires Atomic operation in implementation.

## Simple Spinlock in C language

Consider the following code:
```c
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

- **Keyword `volatile`**: `volatile` keyword lets the compiler know that the variable may be accessed in unexpected circumstances, so do not optimize the variable's instructions to avoid storing the result in the Register, but write it directly to memory.
- **Lock function**: [`xchg(a,b)`]() The contents of the two variables a and b can be swapped, and the function is an atomic operation. When the lock value is not 0, the execution thread will spin and wait until the lock is 0 (that is, it can be locked )until.
- **Unlock function**: Since only one thread can obtain the lock at the same time, there is no need to worry about preemption of access when unlocking. Because of this, the example does not use atomic operations.

## Simple Lock


First of all, since TinyOS is a Single Hart (hardware thread) operating system, in addition to using atomic operations, there is actually a very simple way to achieve the locking effect:

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

In [lock.c](https://github.com/Archfx/tinyos/blob/master/06-Spinlock/lock.c), we implement a very simple lock. When we invoke `basic_lock()` in the program, the system's machine mode interrupt mechanism will be turned off. In this way, we can ensure that no there are other programs accessing the Shared memory to avoid the occurrence of Race condition.

## Spinlock Implementation

The above lock has an obvious flaw: **When the program that acquires the lock has not released the lock, the entire system will be blocked**. In order to ensure that the operating system can still maintain the multi-tasking mechanism, we must implement a bit more complex lock :


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

As shown in above assembly construct, we can read the lock in the lock structure, exchange it with the value `1`, and finally return the contents of the register `a5`.
Further summarizing the execution results of the program, we can draw two cases:

1. **Case 1- Successfully acquire the lock**: When `lock->locked` is `0`, after the exchange through `amoswap.w.aq`, the value of `lock->locked` is `1` and the return value (Value of a5) is `0`:
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
When the return value is `0`, `lock_acquire()` will successfully jump out of the infinite loop and enter Critical sections for execution. 

2. **Case 2- No lock acquired**: Otherwise, continue to try to obtain the lock in an infinite loop.


## Simulation

If you followed the **TinyOS** tutorial series contnously, you know how to run the simulation of the code. If you missed the first article about setting up the environment, you can check it from [here](https://archfx.github.io/posts/2023/08/tinyos0/).


Now let's take a look at the system's behaviour.
```sh
cd tinyos/06-Spinlock 
make
```
<code>
riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -T os.ld -o os.elf start.s sys.s lib.c timer.c task.c os.c user.c trap.c lock.c
</code>

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
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
timer interruption!<br>
timer_handler: 1<br>
OS: Back to OS<br>
&nbsp; <br>
OS: Activate next task<br>
Task1: Created!<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
Task1: Running...<br>
timer interruption!<br>
timer_handler: 2<br>
OS: Back to OS<br>
&nbsp; <br>
OS: Activate next task<br>
Task2: Created!<br>
The value of shared_var is: 550<br>
The value of shared_var is: 600<br>
The value of shared_var is: 650<br>
The value of shared_var is: 700<br>
The value of shared_var is: 750<br>
The value of shared_var is: 800<br>
The value of shared_var is: 850<br>
The value of shared_var is: 900<br>
The value of shared_var is: 950<br>
The value of shared_var is: 1000<br>
The value of shared_var is: 1050<br>
The value of shared_var is: 1100<br>
The value of shared_var is: 1150<br>
The value of shared_var is: 1200<br>
The value of shared_var is: 1250<br>
The value of shared_var is: 1300<br>
The value of shared_var is: 1350<br>
The value of shared_var is: 1400<br>
The value of shared_var is: 1450<br>
The value of shared_var is: 1500<br>
The value of shared_var is: 1550<br>
The value of shared_var is: 1600<br>
timer interruption!<br>
timer_handler: 3<br>
OS: Back to OS<br>
&nbsp; <br>
OS: Activate next task<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
Task0: Running...<br>
timer interruption!<br>
timer_handler: 4<br>
OS: Back to OS<br>
QEMU: Terminated<br>
</code>


## Debug Mode and Breakpoint

With the QEMU simulation, you can run the simulation in Debug mode with added break points. Following are the steps for running the TinyOS in debug mode.

```sh
make debug
```
<code>
riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -T os.ld -o os.elf start.s sys.s lib.c timer.c task.c os.c user.c trap.c lock.c
&nbsp; <br>
Press Ctrl-C and then input 'quit' to exit GDB and QEMU<br>
-------------------------------------------------------<br>
Reading symbols from os.elf...<br>
Breakpoint 1 at 0x80000000: file start.s, line 7.<br>
0x00001000 in ?? ()<br>
=> 0x00001000:  97 02 00 00     auipc   t0,0x0<br>
&nbsp; <br>
Thread 1 hit Breakpoint 1, _start () at start.s:7<br>
7           csrr t0, mhartid                # read current hart id<br>
=> 0x80000000 <_start+0>:       f3 22 40 f1     csrr    t0,mhartid<br>
(gdb)<br>
</code>


You can set the breakpoint in any c file using the following command,

```sh
(gdb) b trap.c:27
```
<code>
Breakpoint 2 at 0x80008f78: file trap.c, line 27.
(gdb)
</code>


As the example above, when process running on trap.c, line 27 (Timer Interrupt).
The process will be suspended automatically until you press the key `c` (continue) or `s` (step).

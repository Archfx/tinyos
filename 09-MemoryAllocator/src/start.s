.equ STACK_SIZE, 8192

.global _start

_start:
    csrr a0, mhartid                # read kernel codename
    bnez a0, park                   # If it is not core 0, jump to park and stop
    la   sp, stacks + STACK_SIZE    # Core Set Stack No. 0
    j    os_main                    # Core 0 jumps to the main program os_main

park:
    wfi
    j park

stacks:
    .skip STACK_SIZE                # Allocate stack space

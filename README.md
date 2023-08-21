

# tinyos


This is a cloned repository of [mini-risscv-os](https://github.com/cccriscv/mini-riscv-os) that was modified to work with `riscv32i` on Linux. A fully built environment is available as a docker environment. Credits to the original authors.

## Build & Run on Docker

<p align="center"><a href="https://hub.docker.com/r/archfx/rv32i"><img src="https://dockerico.blankenship.io/image/archfx/rv32i"/></a></p>

```shell
docker pull archfx/rv32i:qemu # pull the docker container
git clone https://github.com/Archfx/tinyos #clone this repository
docker run -t -p 6080:6080 -v "${PWD}/:/tinyos" -w /tinyos --name rv32i archfx/rv32i:qemu #Mount the repo to the docker container

# Opern another terminal 
docker exec -it rv32i /bin/bash
```

## Steps

- [HelloOs](01-HelloOs)
  - Enable UART to print trivial greetings
- [ContextSwitch](02-ContextSwitch)
  - Basic switch from OS to user task
- [MultiTasking](03-MultiTasking)
  - Two user tasks are interactively switching
- [TimerInterrupt](04-TimerInterrupt)
  - Enable SysTick for future scheduler implementation
- [Preemptive](05-Preemptive)
  - Basic preemptive scheduling
- [Spinlock](06-Spinlock)
  - Lock implementation to protect critical sections
- [ExterInterrupt](07-ExterInterrupt)
  - Learning PLIC & external interruption
- [BlockDeviceDriver](08-BlockDeviceDriver)
  - Learning VirtIO Protocol & Device driver implementation
- [MemoryAllocator](09-MemoryAllocator)
  - Understanding how to write the linker script & how the heap works
- [SystemCall](10-SystemCall)
  - Invoking a mini ecall from machine mode.


## Building and Simulation

- Changes the current working directory to the specified one and then

```shell
make # Build the OS
make qemu # Simulate the OS
```

Note: `Press Ctrl-A and then X to exit QEMU`

## Licensing

This repo adheres to the original repo licenses. `mini-riscv-os` is freely redistributable under the two-clause BSD License.
Use of this source code is governed by a BSD-style license that can be found in the `LICENSE` file.

## Reference

- [Adventures in RISC-V](https://matrix89.github.io/writes/writes/experiments-in-riscv/)
- [Xv6, a simple Unix-like teaching operating system](https://pdos.csail.mit.edu/6.828/2020/xv6.html)
- [Basics of programming a UART](https://www.activexperts.com/serial-port-component/tutorials/uart/)
- [QEMU RISC-V Virt Machine Platform](https://github.com/riscv/opensbi/blob/master/docs/platform/qemu_virt.md)

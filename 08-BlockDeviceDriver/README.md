# TinyOS Virtual File System


In the previous episodes of the TinyOS tutorial series, we  have implemented external interrupt mechanism and connected UART pheripheral to the system. Since we are perfoming experiments under a host system, we can use VirtIO ISR to read external file system during the simulations.

## VirtIO

VirtIO is a standardized interface for virtual machines (VMs) that allows them to communicate efficiently with their host systems. It aims to provide a common set of drivers for various virtualization platforms, enabling improved performance and interoperability.

Originally developed for the Linux KVM (Kernel-based Virtual Machine) hypervisor, VirtIO has since been adopted by other virtualization platforms such as QEMU, Xen, and VirtualBox.

VirtIO consists of several components:

- VirtIO devices: These are virtualized devices that emulate physical hardware in the VM. Examples include virtual network adapters, disk controllers, and memory ballooning devices.
- VirtIO drivers: These are the device drivers installed in the guest operating system (OS) to communicate with VirtIO devices. Unlike traditional device drivers, VirtIO drivers are lightweight and optimized for virtualized environments.
- VirtIO specification: This defines the communication protocol between the guest OS and the virtualization host. It ensures compatibility and interoperability across different virtualization platforms.

Let's start with adding the VirtIO interrupt to our interrupt handler code.


```cpp
void external_handler()
{
  int irq = plic_claim();
  if (irq == UART0_IRQ)
  {
    lib_isr();
  }
  else if (irq == VIRTIO_IRQ)
  {
    virtio_disk_isr();
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

Let's look at more details about the VirtIO components.

### Descriptor

Descriptor contains information such as address, length, relavant flags and other information.
Using a Descriptor, we can point the device to the correct memory address of any buffer that is stored in the RAM.

```cpp
struct virtq_desc
{
  uint64 addr;
  uint32 len;
  uint16 flags;
  uint16 next;
};
```

- addr: We can tell the device the storage location anywhere within a 64-bit memory address.
- len: Let the Device know how much memory is available.
- flags: used to control descriptor.
- next: tells Device the Index of the next descriptor. The Device only reads this field if `VIRTQ_DESC_F_NEXT` is specified. Otherwise it is invalid.

### AvailableRing

Index used to store Descriptors. When the Device receives the notification, it will check the AvailableRing to confirm which Descriptors need to be read.

> Note: Descriptor and AvailableRing are both stored in RAM.

```cpp
struct virtq_avail
{
  uint16 flags;     // always zero
  uint16 idx;       // driver will write ring[idx] next
  uint16 ring[NUM]; // descriptor numbers of chain heads
  uint16 unused;
};
```

### UsedRing

UsedRing enables the Device to send messages to the OS, so it is often used by the Device to tell the OS that it has completed a previously notified request.
AvailableRing is very similar to UsedRing, the difference is: OS needs to check UsedRing to know which Descriptor has been served.

```cpp
struct virtq_used_elem
{
  uint32 id; // index of start of completed descriptor chain
  uint32 len;
};

struct virtq_used
{
  uint16 flags; // always zero
  uint16 idx;   // device increments when it adds a ring[] entry
  struct virtq_used_elem ring[NUM];
};
```

## Send read and write requests

In order to save time reading VirtIO Spec, this Block Device Driver refers to the implementation of xv6-riscv, but there are many layers in the implementation of xv6 file system:

<pre class="mermaid">
flowchart LR
    File_descriptor <--> Pathname
    Pathname <--> Directory
    Directory <--> Inode
    Inode <--> Logging
    Logging <--> Buffer_cache
    Buffer_cache <--> Disk
</pre>

Completing the Device Driver will make it easier for us to implement the file system in the future. In addition, referring to the design of xv6-riscv, we will also need to implement a layer of Buffer cache to synchronize the data on the hard disk.

### Specify the Sector to write to

```cpp
uint64_t sector = b->blockno * (BSIZE / 512);
```

### Assign descriptor

Because [qemu-virt](https://github.com/qemu/qemu/blob/master/hw/block/virtio-blk.c) will read 3 descriptors at a time, so we need to allocate them before sending the request Good these spaces.

```cpp
static int
alloc3_desc(int *idx)
{
  for (int i = 0; i < 3; i++)
  {
    idx[i] = alloc_desc();
    if (idx[i] < 0)
    {
      for (int j = 0; j < i; j++)
        free_desc(idx[j]);
      return -1;
    }
  }
  return 0;
}
```

### Send Block request

Declare the structure of req:

```cpp
struct virtio_blk_req *buf0 = &disk.ops[idx[0]];
```

Because disks are divided into read and write operations, in order to let qemu know whether to read or write, we need to write **flag** in the `type` member of the request:
```cpp
if(write)
  buf0->type = VIRTIO_BLK_T_OUT; // write the disk
else
  buf0->type = VIRTIO_BLK_T_IN; // read the disk
buf0->reserved = 0; // The reserved portion is used to pad the header to 16 bytes and move the 32-bit sector field to the correct place.
buf0->sector = sector; // specify the sector that we wanna modified.
```

### Fill Descriptor

At this step, we have allocated the basic data of Descriptor and req, and then we can fill in the data for these three Descriptors:

```cpp
disk.desc[idx[0]].addr = buf0;
  disk.desc[idx[0]].len = sizeof(struct virtio_blk_req);
  disk.desc[idx[0]].flags = VRING_DESC_F_NEXT;
  disk.desc[idx[0]].next = idx[1];

  disk.desc[idx[1]].addr = ((uint32)b->data) & 0xffffffff;
  disk.desc[idx[1]].len = BSIZE;
  if (write)
    disk.desc[idx[1]].flags = 0; // device reads b->data
  else
    disk.desc[idx[1]].flags = VRING_DESC_F_WRITE; // device writes b->data
  disk.desc[idx[1]].flags |= VRING_DESC_F_NEXT;
  disk.desc[idx[1]].next = idx[2];

  disk.info[idx[0]].status = 0xff; // device writes 0 on success
  disk.desc[idx[2]].addr = (uint32)&disk.info[idx[0]].status;
  disk.desc[idx[2]].len = 1;
  disk.desc[idx[2]].flags = VRING_DESC_F_WRITE; // device writes the status
  disk.desc[idx[2]].next = 0;

  // record struct buf for virtio_disk_intr().
  b->disk = 1;
  disk.info[idx[0]].b = b;

  // tell the device the first index in our chain of descriptors.
  disk.avail->ring[disk.avail->idx % NUM] = idx[0];

  __sync_synchronize();

  // tell the device another avail ring entry is available.
  disk.avail->idx += 1; // not % NUM ...

  __sync_synchronize();

  *R(VIRTIO_MMIO_QUEUE_NOTIFY) = 0; // value is queue number

  // Wait for virtio_disk_intr() to say request has finished.
  while (b->disk == 1)
  {
  }

  disk.info[idx[0]].b = 0;
  free_chain(idx[0]);

```
When the Descriptor is filled, `*R(VIRTIO_MMIO_QUEUE_NOTIFY) = 0;` will remind VIRTIO to receive our Block request.

In addition, `while (b->disk == 1)` can ensure that the operating system receives the external interrupt issued by Virtio before continuing to execute the following code.

## Implement VirtIO’s ISR

When the system program receives an external interrupt, it will determine which external device initiated the interrupt (VirtIO, UART...) based on the IRQ Number.

```cpp
void external_handler()
{
  int irq = plic_claim();
  if (irq == UART0_IRQ)
  {
    lib_isr();
  }
  else if (irq == VIRTIO_IRQ)
  {
    lib_puts("Virtio IRQ\n");
    virtio_disk_isr();
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
If the interrupt is initiated by VirtIO, it will be transferred to `virtio_disk_isr()` for processing.

```cpp
void virtio_disk_isr()
{

  // the device won't raise another interrupt until we tell it
  // we've seen this interrupt, which the following line does.
  // this may race with the device writing new entries to
  // the "used" ring, in which case we may process the new
  // completion entries in this interrupt, and have nothing to do
  // in the next interrupt, which is harmless.
  *R(VIRTIO_MMIO_INTERRUPT_ACK) = *R(VIRTIO_MMIO_INTERRUPT_STATUS) & 0x3;

  __sync_synchronize();

  // the device increments disk.used->idx when it
  // adds an entry to the used ring.

  while (disk.used_idx != disk.used->idx)
  {
    __sync_synchronize();
    int id = disk.used->ring[disk.used_idx % NUM].id;

    if (disk.info[id].status != 0)
      panic("virtio_disk_intr status");

    struct blk *b = disk.info[id].b;
    b->disk = 0; // disk is done with buf
    disk.used_idx += 1;
  }

}
```
The main job of `virtio_disk_isr()` is to change the status of the disk and tell the system that the previously issued read and write operations have been successfully executed.
Among them, `b->disk = 0;` allows the previously mentioned `while (b->disk == 1)` to jump out smoothly and release the spin lock in disk.
```cpp
int os_main(void)
{
	os_start();
	disk_read();
	int current_task = 0;
	while (1)
	{
		lib_puts("OS: Activate next task\n");
		task_go(current_task);
		lib_puts("OS: Back to OS\n");
		current_task = (current_task + 1) % taskTop; // Round Robin Scheduling
		lib_puts("\n");
	}
	return 0;
}
```

Since mini-riscv-os does not implement a lock that can sleep, the author will execute the `disk_read()` test function once at boot. If you want to implement a higher-level file system, you will need to use sleep lock. This is to avoid deadlock situations when multiple tasks try to access hard disk resources.




## Build & Run

```sh
cd 08-BlockDeviceDriver 
$ make all
rm -f *.elf *.img
riscv32-unknown-elf-gcc -nostdlib -fno-builtin -mcmodel=medany -march=rv32ima -mabi=ilp32 -g -Wall -w -T os.ld -o os.elf start.s sys.s lib.c timer.c task.c os.c user.c trap.c lock.c plic.c virtio.c string.c
Press Ctrl-A and then X to exit QEMU
qemu-system-riscv32 -nographic -smp 4 -machine virt -bios none -drive if=none,format=raw,file=hdd.dsk,id=x0 -device virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0 -kernel os.elf
OS start
Disk init work is success!
buffer init...
block read...
Virtio IRQ
000000fd
000000af
000000f8
000000ab
00000088
00000042
000000cc
00000017
00000022
0000008e

OS: Activate next task
Task0: Created!
Task0: Running...
Task0: Running...
Task0: Running...
Task0: Running...
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

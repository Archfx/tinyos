# 09-MemoryAllocator -- RISC-V embedded operating system

## Prerequisite knowledge: Linker Script writing

Writing Linker Script allows the compiler to place each Section at the memory address of the instruction according to our ideas during the linking stage.

![](https://camo.githubusercontent.com/1d58b18d5a293fe858931e54cce54ac53f4e86b08da25de332a16434688e7434/68747470733a2f2f692e696d6775722e636f6d2f756f7 2425063642e706e67)

Taking the above figure as an example, the system program will put each section into the memory when it is executed. As for which sections should be allocated, the attributes of each section (readable, writable, and executable) need to be determined using Linker Script. Tell the compiler!

### Entry Points and Structure

See the `os.ld` of this project, which is the Linker Script of mini-riscv-os:

```
OUTPUT_ARCH( "riscv" )

ENTRY( _start )

MEMORY
{
  ram   (wxa!ri) : ORIGIN = 0x80000000, LENGTH = 128M
}
```
Observing the above script, we can draw several small conclusions:

- The output executable file will be executed on the `riscv` platform
- The entry point of the program is `_start`
- The memory name is `ram` and its attributes are:
  - [x] W (writable)
  - [x] X (executable)
  - [x] A (assignable)
  - [ ] R (read only)
  - [ ] I (initialization)
- The starting point of the memory is 0x80000000 and the length is 128 MB. In other words, the memory range is: 0x08000000 - 0x88000000.

Next, you can see that the Linker Script has cut several sections in the SECTION section, namely:
- .text
- .rodata
- .data
- .bss

Let’s explain the script with an example from one of the paragraphs:

```
.text : {
    PROVIDE(_text_start = .);
    *(.text.init) *(.text .text.*)
    PROVIDE(_text_end = .);
  } >ram AT>ram :text
```
- `PROVIDE` can help us define symbols, which also represent a memory address
- `*(.text.init) *(.text .text.*)` helps us match the .text section in any object file.
- `>ram AT>ram :text`

  - ram is VMA (Virtual Memory Address). When the program runs, section will get this memory address.
  - ram:text is LMA (Load Memory Address). When the section is loaded, it will be placed at this memory address.

  Finally, the Linker Script also defines the starting and ending Symbols and the location of the Heap:

  ```
  PROVIDE(_memory_start = ORIGIN(ram));
  PROVIDE(_memory_end = ORIGIN(ram) + LENGTH(ram));

  PROVIDE(_heap_start = _bss_end);
  PROVIDE(_heap_size = _memory_end - _heap_start);
  ```

If represented by pictures, the distribution of memory is as follows:

![](https://i.imgur.com/NCJ3BgL.png)

## Into the title

### What is Heap?

The Heap mentioned in this article is different from the data structure Heap. The Heap here refers to the memory space allocated by the operating system and Process. We all know that Stack will store initialized fixed-length data. Compared with Stack, Heap has more flexibility. We can allocate as much space as we want to use, and memory can be recycled after use to avoid waste.
```cpp
#include <stdlib.h>
int *p = (int*) malloc(sizeof(int));
// ...
free(p);
```
The above C language example uses `malloc()` to configure dynamic memory, and calls `free()` to recycle the memory after use.

### Implementation of mini-riscv-os

After understanding the memory structure described by Heap and Linker Script, it is time to enter the focus of this article!
In this unit, we specially cut out a section of space for Heap to use. In this way, functions similar to Memory Allocator can also be implemented in system programs:

```assembly
.section .rodata
.global HEAP_START
HEAP_START: .word _heap_start

.global HEAP_SIZE
HEAP_SIZE: .word _heap_size

.global TEXT_START
TEXT_START: .word _text_start

.global TEXT_END
TEXT_END: .word _text_end

.global DATA_START
DATA_START: .word _data_start

.global DATA_END
DATA_END: .word _data_end

.global RODATA_START
RODATA_START: .word _rodata_start

.global RODATA_END
RODATA_END: .word _rodata_end

.global BSS_START
BSS_START: .word _bss_start

.global BSS_END
BSS_END: .word _bss_end
```

In `mem.s`, we declare multiple variables, each representing a Symbol previously defined in the Linker Script, so that we can access these memory addresses in the C program:

```cpp
extern uint32_t TEXT_START;
extern uint32_t TEXT_END;
extern uint32_t DATA_START;
extern uint32_t DATA_END;
extern uint32_t RODATA_START;
extern uint32_t RODATA_END;
extern uint32_t BSS_START;
extern uint32_t BSS_END;
extern uint32_t HEAP_START;
extern uint32_t HEAP_SIZE;
```

### How to manage memory blocks

In fact, in mainstream operating systems, the Heap structure is very complex. There are multiple lists to manage unallocated memory blocks and allocated memory blocks of different sizes.

```cpp
static uint32_t _alloc_start = 0;
static uint32_t _alloc_end = 0;
static uint32_t _num_pages = 0;

#define PAGE_SIZE 256
#define PAGE_ORDER 8
```

In mini-riscv-os, our unified block size is 25b Bits, that is to say, when we call `malloc(sizeof(int))`, it will also allocate 256 Bits of space to this request in one go.

```cpp
void page_init()
{
  _num_pages = (HEAP_SIZE / PAGE_SIZE) - 2048;
  lib_printf("HEAP_START = %x, HEAP_SIZE = %x, num of pages = %d\n", HEAP_START, HEAP_SIZE, _num_pages);

  struct Page *page = (struct Page *)HEAP_START;
  for (int i = 0; i < _num_pages; i++)
  {
    _clear(page);
    page++;
  }

  _alloc_start = _align_page(HEAP_START + 2048 * PAGE_SIZE);
  _alloc_end = _alloc_start + (PAGE_SIZE * _num_pages);

  lib_printf("TEXT:   0x%x -> 0x%x\n", TEXT_START, TEXT_END);
  lib_printf("RODATA: 0x%x -> 0x%x\n", RODATA_START, RODATA_END);
  lib_printf("DATA:   0x%x -> 0x%x\n", DATA_START, DATA_END);
  lib_printf("BSS:    0x%x -> 0x%x\n", BSS_START, BSS_END);
  lib_printf("HEAP:   0x%x -> 0x%x\n", _alloc_start, _alloc_end);
}
```

As you can see in `page_init()`, assuming that there are N memory blocks of 256 Bits available for allocation, we must implement a data structure to manage the status of the memory blocks:

```cpp
struct Page
{
  uint8_t flags;
};
```

Therefore, the Heap memory will be used to store: N Page Structs and N memory blocks of 256 Bits, showing a one-to-one relationship.
As for how to tell whether the A-th memory block is allocated, it depends on what the flag in the corresponding Page Struct records:

- 00: This means this page hasn't been allocated
- 01: This means this page was allocated
- 11: This means this page was allocated and is the last page of the memory block allocated

The status of `00` and `01` is very easy to understand. As for the situation in which `11` will be used? Let’s continue to look down:

```cpp
void *malloc(size_t size)
{
  int npages = pageNum(size);
  int found = 0;
  struct Page *page_i = (struct Page *)HEAP_START;
  for (int i = 0; i < (_num_pages - npages); i++)
  {
    if (_is_free(page_i))
    {
      found = 1;

      /*
			 * meet a free page, continue to check if following
			 * (npages - 1) pages are also unallocated.
			 */

      struct Page *page_j = page_i;
      for (int j = i; j < (i + npages); j++)
      {
        if (!_is_free(page_j))
        {
          found = 0;
          break;
        }
        page_j++;
      }
      /*
			 * get a memory block which is good enough for us,
			 * take housekeeping, then return the actual start
			 * address of the first page of this memory block
			 */
      if (found)
      {
        struct Page *page_k = page_i;
        for (int k = i; k < (i + npages); k++)
        {
          _set_flag(page_k, PAGE_TAKEN);
          page_k++;
        }
        page_k--;
        _set_flag(page_k, PAGE_LAST);
        return (void *)(_alloc_start + i * PAGE_SIZE);
      }
    }
    page_i++;
  }
  return NULL;
}
```
By reading the source code of `malloc()`, we can know that when the user uses it to try to obtain a memory space larger than 256 Bits, he will first calculate how many blocks are needed to satisfy the requested memory size. After the calculation is completed, it will search for connected and unallocated memory blocks in consecutive memory blocks to assign to the request:

```
malloc(513);
Cause 513 Bits > The size of the 2 blocks,
thus, malloc will allocates 3 blocks for the request.

Before Allocation:

+----+    +----+    +----+    +----+    +----+
| 00 | -> | 00 | -> | 00 | -> | 00 | -> | 00 |
+----+    +----+    +----+    +----+    +----+

After Allocation:

+----+    +----+    +----+    +----+    +----+
| 01 | -> | 01 | -> | 11 | -> | 00 | -> | 00 |
+----+    +----+    +----+    +----+    +----+

```

After the allocation is completed, we can find that the Flag of the last allocated memory block is `11`. In this way, when the user calls `free()` to release this memory, the system can confirm it through the Flag. The block marked with `11` is the last block that needs to be freed.


#include <mmu.h>
#include <memlayout.h>

#define REALLOC(x) (x - KERNBASE)

.text
.globl kern_entry
kern_entry:
    # REALLOC是因为内核在构建时被设置在了高位(kernel.ld中设置了内核起始虚地址0xC0100000,使得虚地址整体增加了KERNBASE)
    # 因此需要REALLOC来对内核全局变量进行重定位，在开启分页模式前保证程序访问的物理地址的正确性
    # load pa of boot pgdir

    # 此时还没有开启页机制，__boot_pgdir(entry.S中的符号)需要通过REALLOC转换成正确的物理地址
    movl $REALLOC(__boot_pgdir), %eax
    # 设置eax的值到页表基址寄存器cr3中
    movl %eax, %cr3

    # enable paging 开启页模式
    movl %cr0, %eax
    # 通过or运算，修改cr0中的值
    orl $(CR0_PE | CR0_PG | CR0_AM | CR0_WP | CR0_NE | CR0_TS | CR0_EM | CR0_MP), %eax
    andl $~(CR0_TS | CR0_EM), %eax

    # 将cr0修改完成后的值，重新送至cr0中(此时第0位PE位已经为1，页机制已经开启，当前页表地址为刚刚构造的__boot_pgdir)
    movl %eax, %cr0

    # update eip
    # now, eip = 0x1..... next是处于高位地址空间
    leal next, %eax
    # set eip = KERNBASE + 0x1.....
    # 通过jmp至next处，使得内核的指令指针指向了高位。但由于巧妙的设计了高位映射的内核页表，使得依然能准确访问之前低位虚空间下的所有内容
    jmp *%eax
next:

    # unmap va 0 ~ 4M, it's temporary mapping
    xorl %eax, %eax
    # 将__boot_pgdir的第一个页目录项清零，取消0~4M虚地址的映射
    movl %eax, __boot_pgdir

    # 设置C的内核栈
    # set ebp, esp
    movl $0x0, %ebp
    # the kernel stack region is from bootstack -- bootstacktop,
    # the kernel stack size is KSTACKSIZE (8KB)defined in memlayout.h
    movl $bootstacktop, %esp
    # now kernel stack is ready , call the first C function
    
    # 调用init.c中的kern_init总控函数
    call kern_init

# should never get here
# 自旋死循环(如果内核实现正确，kern_init函数将永远不会返回并执行至此。因为操作系统内核本身就是通过自旋循环常驻内存的)
spin:
    jmp spin

.data
.align PGSIZE
    .globl bootstack
bootstack:
    .space KSTACKSIZE
    .globl bootstacktop
bootstacktop:

# kernel builtin pgdir
# an initial page directory (Page Directory Table, PDT)
# These page directory table and page table can be reused!
.section .data.pgdir
.align PGSIZE
__boot_pgdir:
.globl __boot_pgdir
    # map va 0 ~ 4M to pa 0 ~ 4M (temporary)
    # 80386的每一个一级页表项能够映射4MB连续的虚拟内存至物理内存的关系
    # 第一个有效页表项，当访问0~4M虚拟内存时，虚拟地址的高10位为0，即找到该一级页表项(页目录项)，进而可以找到二级页表__boot_pt1
    # 进而可以进行虚拟地址的0~4M -> 物理地址 0~4M的等价映射
    
    .long REALLOC(__boot_pt1) + (PTE_P | PTE_U | PTE_W)
    
    # space用于将指定范围大小内的空间全部设置为0(等价于P位为0，即不存在的、无效的页表项)
    # KERNBASE/一个物理页的大小(PGSHIFT 4KB即偏移12位)/一个二级页表内的页表项(2^10个) * 4(一个页表项32位，即4byte)
    # 偏移的距离 - (. - __boot_pgdir) 是为了对齐

    .space (KERNBASE >> PGSHIFT >> 10 << 2) - (. - __boot_pgdir) # pad to PDE of KERNBASE
    
    # map va KERNBASE + (0 ~ 4M) to pa 0 ~ 4M
    # 第二个有效页表项，前面通过.space偏移跳过特定的距离，当虚拟地址为KERNBASE~KERNBASE+4M时，能够查找到该项
    # 其对应的二级页表同样是__boot_pt1，而其中映射的物理地址为按照下标顺序排列的0~4M，
    # 因此其最终的效果便能将KERNBASE~KERNBASE+4M的虚拟内存空间映射至物理内存空间的0~4M
    
    .long REALLOC(__boot_pt1) + (PTE_P | PTE_U | PTE_W)
    .space PGSIZE - (. - __boot_pgdir) # pad to PGSIZE

.set i, 0
# __boot_pt1是一个存在1024个32位long数据的数组，当将其作为页表时其中每一项都代表着一个物理地址映射项
# i为下标，每个页表项的内容为i*1024作为映射的物理页面基址并加上一些低位的属性位(PTE_P代表存在，PTE_W代表可写)

__boot_pt1:
.rept 1024
    .long i * PGSIZE + (PTE_P | PTE_W)
    .set i, i + 1
.endr


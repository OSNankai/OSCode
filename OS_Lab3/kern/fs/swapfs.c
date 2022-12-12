#include <swap.h>
#include <swapfs.h>
#include <mmu.h>
#include <fs.h>
#include <ide.h>
#include <pmm.h>
#include <assert.h>

void
swapfs_init(void) {
    static_assert((PGSIZE % SECTSIZE) == 0);
    if (!ide_device_valid(SWAP_DEV_NO)) {
        panic("swap fs isn't available.\n");
    }
    max_swap_offset = ide_device_size(SWAP_DEV_NO) / (PGSIZE / SECTSIZE);
}

int
swapfs_read(swap_entry_t entry, struct Page *page) {
    // swap_offset宏右移8位，截取前24位 = swap_entry_t的offset属性
	// swap_entry_t的offset * PAGE_NSECT(物理页与磁盘扇区大小比值) = 要读取的起始扇区号

	// 从设备号指定的磁盘中，读取自某一扇区起始的N个连续扇区，并将其写入指定起始地址的内存空间中
	// SWAP_DEV_NO参数指定设备号，swap_offset(entry) * PAGE_NSECT指定起始扇区号
	// page2kva(page)指定所要写入的目的页面虚地址起始空间，PAGE_NSECT指定了需要顺序连续读取的扇区数量
    return ide_read_secs(SWAP_DEV_NO, swap_offset(entry) * PAGE_NSECT, page2kva(page), PAGE_NSECT);
}

int
swapfs_write(swap_entry_t entry, struct Page *page) {
    // swap_offset宏右移8位，截取前24位 = swap_entry_t的offset属性
    // swap_entry_t的offset * PAGE_NSECT(物理页与磁盘扇区大小比值) = 要写入的起始扇区号

    // 从设备号指定的磁盘中，从指定起始地址的内存空间开始，将数据写入自某一扇区起始的N个连续扇区内
    // SWAP_DEV_NO参数指定设备号，swap_offset(entry) * PAGE_NSECT指定起始扇区号
    // page2kva(page)指定所要读入的源数据页面虚地址起始空间，PAGE_NSECT指定了需要顺序连续写入的扇区数量
    
    return ide_write_secs(SWAP_DEV_NO, swap_offset(entry) * PAGE_NSECT, page2kva(page), PAGE_NSECT);
}


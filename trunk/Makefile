
SRC_DIR=vfs-full
VFS_IMAGE=vfs-full.gz
KERNEL_RELEASE=2.6.32.8-liveusb
KERNEL_SOURCE_DIR=linux-2.6.32.8-liveusb
FLASH_DISK=LABEL=Lenny-netac

vfs_make: kernel_make
	mkdir -p boot
	cp -af /boot/*-$(KERNEL_RELEASE) boot/
	mkdir -p __d
	dd if=/dev/zero of=__t bs=1M count=64
	echo y | mkfs.ext2 -I128 -L vfs-full __t
	mount __t __d -o loop
	cp -af $(SRC_DIR)/* __d/
	cp -af /lib/modules/$(KERNEL_RELEASE) __d/lib/modules/
	umount __d
	rmdir __d
	gzip -c __t > $(VFS_IMAGE)
	rm -f __t

install: vfs_make
	mkdir -p __u
	mount $(FLASH_DISK) __u
	cp -af /boot/*-$(KERNEL_RELEASE) $(VFS_IMAGE) __u/boot/
	umount __u
	rmdir __u

kernel_make:
	make -C $(KERNEL_SOURCE_DIR)
	make install -C $(KERNEL_SOURCE_DIR)
	depmod $(KERNEL_RELEASE)


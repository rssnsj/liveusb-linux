#!/bin/sh -e

VFS_SOURCE=vfs-full
VFS_IMAGE=vfs-full.gz
KERNEL_VERSION=2.6.32.8-liveusb
KERNEL_SOURCE=linux-2.6.32.8-liveusb

do_kernel_make()
{
	make -C $KERNEL_SOURCE
	make install -C $KERNEL_SOURCE
	depmod $KERNEL_VERSION
}

do_vfs_make()
{
	local __vfs_mp="__d"
	local __vfs_lo="__t"
	
	do_kernel_make
	
	mkdir -p boot
	cp -af /boot/*-$KERNEL_VERSION boot/
	mkdir -p $__vfs_mp
	dd if=/dev/zero of=$__vfs_lo bs=1M count=64
	echo y | mkfs.ext2 -I128 -L vfs-full $__vfs_lo
	mount $__vfs_lo $__vfs_mp -o loop
	cp -af $VFS_SOURCE/* $__vfs_mp/
	cp -af /lib/modules/$KERNEL_VERSION $__vfs_mp/lib/modules/
	umount $__vfs_mp
	rmdir $__vfs_mp
	gzip -c $__vfs_lo > $VFS_IMAGE
	rm -f $__vfs_lo
}

do_install()
{
	[ -z "$1" ] && { echo "*** No flash disk partition specified."; exit 1; }

	local __flash_dev="$1"
	local __flash_mp="__u"
	
	do_vfs_make
	
	mkdir -p $__flash_mp
	mount $__flash_dev $__flash_mp
	[ ! -e $__flash_mp/boot ] && mkdir $__flash_mp/boot
	cp -af /boot/*-$KERNEL_VERSION $VFS_IMAGE $__flash_mp/boot/
	umount $__flash_mp
	rmdir $__flash_mp
}

do_clean()
{
	rm -rf boot
	rm -f $VFS_IMAGE
}

case "$1" in
	"create")
		do_vfs_make
		;;
	"clean")
		do_clean
		;;
	"install")
		do_install $2
		;;
	*)
		echo "Build images for a LiveUSB linux."
		echo "Usage:"
		echo "  $0 create             -- create kernel and filesystem images"
		echo "  $0 clean              -- clean temporary and target files"
		echo "  $0 install /dev/sdxn  -- synchronize to your flash disk (<label> for mount)"
		echo "  $0                    -- show this help"
		;;
esac

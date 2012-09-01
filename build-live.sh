#!/bin/sh -e

PWD=`pwd`

KERNEL_VERSION=2.6.32.8
KERNEL_DOWNLOAD_URL="http://rssn.tk/Repository/sources/linux-2.6.32.8.tar.bz2"

VFS_SOURCE=$PWD/vfs-full
VFS_IMAGE=$PWD/vfs-full.gz
KERNEL_SOURCE=$PWD/linux-$KERNEL_VERSION
KERNEL_RELEASE=$KERNEL_VERSION-liveusb


do_kernel_make()
{
	# Check if kernel source exists, if not download it
	if [ ! -e $KERNEL_SOURCE ]; then
		local __kernel_tar=`basename "$KERNEL_DOWNLOAD_URL"`
		[ ! -e "$__kernel_tar" ] && wget $KERNEL_DOWNLOAD_URL -O $__kernel_tar
		case "$__kernel_tar" in
			*.tar.bz2)
				tar -jxvf $__kernel_tar
				;;
			*.tar.gz)
				tar -zxvf $__kernel_tar
				;;
			*)
				echo "*** Invalid tarball format '$__kernel_tar'."
				exit 1
				;;
		esac
	fi
	
	cp -vf config-$KERNEL_RELEASE $KERNEL_SOURCE/.config
	make -C $KERNEL_SOURCE
	cp -vf $KERNEL_SOURCE/.config config-$KERNEL_RELEASE
	make install -C $KERNEL_SOURCE
	make modules_install -C $KERNEL_SOURCE
	depmod $KERNEL_RELEASE

}

do_vfs_make()
{
	local __vfs_mnt=$PWD/__d
	local __vfs_loop=$PWD/__t
	
	do_kernel_make
	
	mkdir -p boot
	cp -af /boot/*-$KERNEL_RELEASE boot/
	mkdir -p $__vfs_mnt
	dd if=/dev/zero of=$__vfs_loop bs=1M count=64
	echo y | mkfs.ext2 -I128 -L vfs-full $__vfs_loop
	mount $__vfs_loop $__vfs_mnt -o loop
	(
		cd $VFS_SOURCE
		tar -c --exclude=.svn * | tar -xv -C $__vfs_mnt
		
		# Build /dev directory
		mkdir -p $__vfs_mnt/dev
		cd $__vfs_mnt/dev
		mknod ram0 b 1 0
		mknod ram1 b 1 1
		mknod ram2 b 1 2
		ln -s ram0 ramdisk
		ln -s ram1 ram
		mknod console c 5 1
		mknod tty c 5 0
		mknod tty0 c 4 0
		mknod tty1 c 4 1
		mknod tty2 c 4 2
		mknod tty3 c 4 3
		mknod tty4 c 4 4
		mknod tty5 c 4 5
		mknod null c 1 3
		mknod ptmx c 5 2
		mknod urandom c 1 9
		mknod zero c 1 5
		mkdir -p pts shm
		
		# Fix /etc/ssh permissions
		cd $__vfs_mnt/etc/ssh
		chmod 600 *_key
	)
	cp -auvf /lib/modules/$KERNEL_RELEASE $__vfs_mnt/lib/modules/
	umount $__vfs_mnt
	rmdir $__vfs_mnt
	gzip -c $__vfs_loop > $VFS_IMAGE
	rm -f $__vfs_loop
}

do_install()
{
	[ -z "$1" ] && { echo "*** No flash disk partition specified."; exit 1; }
	
	local __flash_dev="$1"
	local __flash_mnt=$PWD/__u
	
	do_vfs_make
	
	mkdir -p $__flash_mnt
	mount $__flash_dev $__flash_mnt
	[ ! -e $__flash_mnt/boot ] && mkdir $__flash_mnt/boot
	cp -af /boot/*-$KERNEL_RELEASE $VFS_IMAGE $__flash_mnt/boot/
	umount $__flash_mnt
	rmdir $__flash_mnt

	echo
	echo -ne "\033[32m"
	echo -n ">>> You may probably need to add this option to '/boot/grub/menu.lst' of your flash disk, and run 'grub-install' to it:"
	echo -e "\033[0m"
	echo
	echo "title       Linux - $KERNEL_RELEASE (ramdisk)"
	echo "root        (hd0,0)"
	echo "kernel      /boot/vmlinuz-$KERNEL_RELEASE root=/dev/ram0 rw"
	echo "initrd      /boot/vfs-full.gz"
	echo 

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
		echo "  $0 install /dev/sdxn  -- synchronize to your flash disk"
		echo "  $0                    -- show this help"
		;;
esac


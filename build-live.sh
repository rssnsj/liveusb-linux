#!/bin/sh -e

cd `dirname $0`

KERNEL_VERSION=2.6.32.8
KERNEL_RELEASE=$KERNEL_VERSION-liveusb
KERNEL_DOWNLOAD_URL="http://www.kernel.org/pub/linux/kernel/v2.6/linux-2.6.32.8.tar.bz2"

SRC_ROOT=`pwd`
VFS_SOURCE=$SRC_ROOT/vfs-full
TMP_BOOT_DIR=$SRC_ROOT/boot
VFS_IMAGE=$TMP_BOOT_DIR/vfs-full.gz
KERNEL_SOURCE=$SRC_ROOT/linux-$KERNEL_VERSION

do_kernel_make()
{
	# "ARCH=xxx" attached to "make" while compiling kernel or module
	local __k_make_opts=""

	# If building on a 64-bit system, specify the target arch
	#case "`uname -m`" in
	#	i?86)
	#		__k_make_opts=""
	#		;;
	#	x86_64)
	#		__k_make_opts="ARCH=i386"
	#		;;
	#	*)
	#		echo "*** Unrecognized arch type of current OS '`uname -m`'."
	#		exit 1
	#		;;
	#esac
	
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

	# Check symlink: config -> config-x.x.x-xxx
	if ! [ -L config ]; then
		echo "*** Please create symbolic link 'config' to either of the config files."
		exit 1
	fi

	# If the repository config file is newer, just use it
	cat config > $KERNEL_SOURCE/.config

	local i
	for i in 5 4 3 2 1; do
		echo "Waiting ${i}s to build ..."
		sleep 1
	done

	# Compile the kernel and selected drivers using 8 threads
	make -j4 -C $KERNEL_SOURCE $__k_make_opts
	# .config may change during compiling, update the repository one
	### cat $KERNEL_SOURCE/.config > config

	# Install kernel image to "./boot" directory
	mkdir -p boot
	make install -C $KERNEL_SOURCE $__k_make_opts INSTALL_PATH=$TMP_BOOT_DIR
	rm -vf $TMP_BOOT_DIR/{*.old,config-$KERNEL_RELEASE,System.map-$KERNEL_RELEASE}

	# Install modules to "/lib/modules" of current system
	make modules_install -C $KERNEL_SOURCE $__k_make_opts INSTALL_MOD_PATH=$VFS_SOURCE

	# Replace Intel NIC drivers with the newly compiled
	local __driver_dir=""
	for __driver_dir in e1000-* e1000e-* igb-* ixgbe-*; do
		[ -d "$__driver_dir" ] || continue
		(
			local __d_name=`echo "$__driver_dir" | awk -F- '{print $1}'`
			local __d_dir=$VFS_SOURCE/lib/modules/$KERNEL_RELEASE/kernel/drivers/net/$__d_name
			cd $__driver_dir/src
			make KSRC=$KERNEL_SOURCE $__k_make_opts
			[ ! -e "$__d_dir" ] && mkdir $__d_dir
			cp -vf $__d_name.ko $__d_dir/
		)
	done
	# Regenerate module dependencies after updated drivers
	chroot $VFS_SOURCE depmod -av $KERNEL_RELEASE
}

do_vfs_make()
{
	local __vfs_mnt=$SRC_ROOT/__d
	local __vfs_loop=$SRC_ROOT/__t
	
	do_kernel_make
	
	#cp -af /boot/*-$KERNEL_RELEASE boot/
	mkdir -p $__vfs_mnt
	dd if=/dev/zero of=$__vfs_loop bs=1M count=64
	echo y | mkfs.ext2 -I128 -L vfs-full $__vfs_loop
	mount $__vfs_loop $__vfs_mnt -o loop
	(
		cd $VFS_SOURCE
		tar -c --exclude=.svn * | tar -xv -C $__vfs_mnt

		# Rebuild the empty directories
		cd $__vfs_mnt
		mkdir -p dev sys proc tmp var/run media

		# Build /dev sub-directories
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

	#cp -auvf /lib/modules/$KERNEL_RELEASE $__vfs_mnt/lib/modules/
	umount $__vfs_mnt
	rmdir $__vfs_mnt
	gzip -c $__vfs_loop > $VFS_IMAGE
	rm -f $__vfs_loop
}

do_install()
{
	[ -z "$1" ] && { echo "*** No flash disk partition specified."; exit 1; }

	local __flash_dev="$1"
	local __flash_mnt=$SRC_ROOT/__disk__

	do_vfs_make

	local i
	for i in 5 4 3 2 1; do
		echo "Waiting ${i}s to install to $__flash_dev ..."
		sleep 1
	done

	mkdir -p $__flash_mnt
	mount $__flash_dev $__flash_mnt
	[ ! -e $__flash_mnt/boot ] && mkdir $__flash_mnt/boot
	cp -af boot/vmlinuz-$KERNEL_RELEASE $VFS_IMAGE $__flash_mnt/boot/
	umount $__flash_mnt
	rmdir $__flash_mnt

	echo
	echo -ne "\033[32m"
	echo -n ">>> You may have to add these options to '/boot/grub/menu.lst' of your flash disk, and run 'grub-install' to it:"
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

	cd $VFS_SOURCE
	rm -rf lib/firmware
	rm -rf lib/modules
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


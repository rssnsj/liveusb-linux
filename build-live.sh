#!/bin/bash -e

cd `dirname $0`

KERNEL_VERSION=4.1.18
KERNEL_RELEASE=$KERNEL_VERSION-liveusb
KERNEL_DOWNLOAD_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.1.18.tar.gz"

SRC_ROOT=`pwd`
VFS_SOURCE=$SRC_ROOT/vfs-full
BOOT_BUILD_DIR=$SRC_ROOT/boot
KERNEL_SOURCE=$SRC_ROOT/linux-$KERNEL_VERSION

chroot_real()
{
	local dir="$1"
	shift 1
	(
		cd $dir || exit 1
		if [ ! -d proc/net ]; then
			mkdir -p dev sys proc tmp
			mount --bind /proc proc
			mount --bind /dev dev
			#mount devpts2 dev/pts -t devpts
			#mount tmpfs2 dev/shm -t tmpfs
			mount --bind /sys sys
		fi
		exec chroot . "$@"
	)
}

clean_chroot()
{
	local dir="$1"
	(
		cd $dir || exit 1
		umount dev/pts dev/shm 2>/dev/null || :
		umount sys dev proc || :
	)
}

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
	mkdir -p $BOOT_BUILD_DIR
	make install -C $KERNEL_SOURCE $__k_make_opts INSTALL_PATH=$BOOT_BUILD_DIR
	rm -vf $BOOT_BUILD_DIR/{*.old,config-$KERNEL_RELEASE,System.map-$KERNEL_RELEASE}

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
			cp $__d_name.ko $__d_dir/
		)
	done

	# Regenerate module dependencies after updated drivers
	chroot_real $VFS_SOURCE depmod -a $KERNEL_RELEASE
	sleep 1
	clean_chroot $VFS_SOURCE
}

do_vfs_make()
{
	local __vfs_img=$SRC_ROOT/__vfs_img__
	local __vfs_mnt=$SRC_ROOT/__vfs_mnt__
	
	do_kernel_make
	
	#cp /boot/*-$KERNEL_RELEASE boot/
	dd if=/dev/zero of=$__vfs_img bs=1M count=64
	echo y | mkfs.ext2 -I128 $__vfs_img
	mkdir -p $__vfs_mnt
	mount $__vfs_img $__vfs_mnt -o loop
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

	#cp -a /lib/modules/$KERNEL_RELEASE $__vfs_mnt/lib/modules/
	umount $__vfs_mnt
	rmdir $__vfs_mnt
	gzip -c $__vfs_img > $BOOT_BUILD_DIR/vfs-full.gz
	rm -f $__vfs_img
}

do_install()
{
	[ -z "$1" ] && { echo "*** No target disk partition."; exit 1; }

	local disk_dev="$1"
	local disk_mnt_rel=__disk__
	local disk_mnt=$VFS_SOURCE/$disk_mnt_rel

	do_vfs_make

	local i
	for i in 5 4 3 2 1; do
		echo "Waiting ${i}s to install to $disk_dev ..."
		sleep 1
	done

	mkdir -p $disk_mnt
	mount $disk_dev $disk_mnt
	mkdir -p $disk_mnt/boot
	cp -v $BOOT_BUILD_DIR/vmlinuz-$KERNEL_RELEASE $BOOT_BUILD_DIR/vfs-full.gz $disk_mnt/boot/

	# Install GRUB
	#chroot_real $VFS_SOURCE grub-install `echo $disk_dev | sed 's/[0-9]\+$//'` --root-directory=/$disk_mnt_rel
	#sleep 1
	#clean_chroot $VFS_SOURCE

	umount $disk_mnt
	rmdir $disk_mnt

	echo
	echo -ne "\033[32m"
	echo -n ">>> You may have to add these options to '/boot/grub/menu.lst' of your flash disk, and run 'grub-install' to it:"
	echo -e "\033[0m"
	cat <<EOF

default 0
timeout 2

#color  cyan/blue white/blue

title   Linux - $KERNEL_RELEASE (ramdisk)
root    (hd0,0)
kernel  /boot/vmlinuz-$KERNEL_RELEASE root=/dev/ram0 rw
initrd  /boot/vfs-full.gz

EOF
}

do_clean()
{
	rm -rf $BOOT_BUILD_DIR
	rm -f $BOOT_BUILD_DIR/vfs-full.gz

	( cd $VFS_SOURCE; rm -rf lib/firmware lib/modules )

	if [ -d $KERNEL_SOURCE ]; then
		echo -n "Delete kernel source directory '$KERNEL_SOURCE' [y/N]? "
		local cf
		read cf
		if [ "$cf" = y -o "$cf" = Y ]; then
			echo "Deleting $KERNEL_SOURCE ..."
			rm -rf $KERNEL_SOURCE
			echo "Done."
		else
			echo "Given up."
		fi
	fi
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
		echo "Bootable LiveUSB Linux creator."
		echo "Usage:"
		echo "  $0 create                build kernel image and rootfs ramdisk"
		echo "  $0 install /dev/sdxn     write to your flash disk"
		echo "  $0 clean                 clean up workspace"
		echo "  $0                       show help"
		;;
esac


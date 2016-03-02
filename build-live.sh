#!/bin/bash -e

KERNEL_VERSION=4.1.18
KERNEL_RELEASE=$KERNEL_VERSION-liveusb
KERNEL_DOWNLOAD_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.1.18.tar.gz"

VFS_SOURCE_DIR=vfs-full
BOOT_BUILD_DIR=boot
KERNEL_BUILD_DIR=linux-$KERNEL_VERSION

print_green()
{
	local stdin=`readlink /proc/self/fd/0`
	case "$stdin" in
		/dev/tty*|/dev/pt*) echo -ne "\033[32m"; echo -n "$@"; echo -e "\033[0m";;
		*) echo "$@";;
	esac
}
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

generate_grub_menu()
{
	cat <<EOF
default 0
timeout 5

color  cyan/blue white/blue

title   Linux - $KERNEL_RELEASE (ramdisk)
root    (hd0,0)
kernel  /boot/vmlinuz-$KERNEL_RELEASE root=/dev/ram0 rw
initrd  /boot/vfs-full.gz

EOF

}

build_kernel()
{
	# Check if kernel source exists, if not download it
	if ! [ -d $KERNEL_BUILD_DIR ]; then
		local __kernel_tar=`basename "$KERNEL_DOWNLOAD_URL"`
		if ! [ -f "$__kernel_tar" ]; then
			wget $KERNEL_DOWNLOAD_URL -O $__kernel_tar
		fi

		case "$__kernel_tar" in
			*.tar.bz2)
				tar jxf $__kernel_tar
				;;
			*.tar.gz)
				tar zxf $__kernel_tar
				;;
			*.tar.xz)
				tar Jxf $__kernel_tar
				;;
			*)
				echo "*** Unsupported tarball format '$__kernel_tar'."
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
	cat config > $KERNEL_BUILD_DIR/.config

	local i
	for i in 5 4 3 2 1; do
		echo "Waiting ${i}s to build ..."
		sleep 1
	done

	# Compile the kernel and selected drivers using 8 threads
	make -j4 -C $KERNEL_BUILD_DIR
	# .config may change during compiling, update the one in repository
	### cat $KERNEL_BUILD_DIR/.config > config

	mkdir -p $BOOT_BUILD_DIR
	# Build the kernel and install modules
	make modules_install -C $KERNEL_BUILD_DIR INSTALL_PATH=`pwd`/$BOOT_BUILD_DIR INSTALL_MOD_PATH=`pwd`/$VFS_SOURCE_DIR
	# Install kernel image
	make install -C $KERNEL_BUILD_DIR INSTALL_PATH=`pwd`/$BOOT_BUILD_DIR INSTALL_MOD_PATH=`pwd`/$VFS_SOURCE_DIR
	rm -vf $BOOT_BUILD_DIR/{*.old,config-$KERNEL_RELEASE,System.map-$KERNEL_RELEASE,initrd.img-$KERNEL_RELEASE}

	# Regenerate module dependencies after copying drivers
	chroot_real $VFS_SOURCE_DIR depmod -a $KERNEL_RELEASE
	sleep 1
	clean_chroot $VFS_SOURCE_DIR
}

do_build_all()
{
	local img_file=`pwd`/__vfs_img__
	local img_mnt=`pwd`/__vfs_mnt__
	
	build_kernel
	
	#cp /boot/*-$KERNEL_RELEASE boot/
	dd if=/dev/zero of=$img_file bs=1M count=64
	echo y | mkfs.ext2 -I128 $img_file
	mkdir -p $img_mnt
	mount $img_file $img_mnt -o loop
	(
		cd $VFS_SOURCE_DIR
		tar -c --exclude-vcs * | tar -x -C $img_mnt

		# Rebuild the empty directories
		cd $img_mnt
		mkdir -p dev sys proc tmp var/run media

		# Build /dev sub-directories
		cd $img_mnt/dev
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

		# Fix file permissions
		cd $img_mnt/etc/ssh
		chmod 600 *_key
	)

	#cp -a /lib/modules/$KERNEL_RELEASE $img_mnt/lib/modules/
	umount $img_mnt
	rmdir $img_mnt
	gzip -c $img_file > $BOOT_BUILD_DIR/vfs-full.gz
	rm -f $img_file

	# Write a menu.lst sample
	mkdir -p $BOOT_BUILD_DIR/grub
	( generate_grub_menu ) > $BOOT_BUILD_DIR/grub/menu.lst

	print_green ">>> Built successfully."
}

do_install_disk()
{
	local disk_dev="$1"

	if [ -z "$disk_dev" ]; then
		echo "*** Requiring target disk partition."
		exit 1
	elif ! [ -b "$disk_dev" ]; then
		echo "*** '$disk_dev' is not a valid block device."
		exit 1
	fi

	if ! [ -f $BOOT_BUILD_DIR/vmlinuz-$KERNEL_RELEASE -a -f $BOOT_BUILD_DIR/vfs-full.gz ]; then
		echo "*** Missing kernel or ramdisk images. Perform the 'create' operation before 'install'."
		exit 1
	fi

	local i
	for i in 5 4 3 2 1; do
		echo "Waiting ${i}s to install to $disk_dev ..."
		sleep 1
	done

	mkdir -p $VFS_SOURCE_DIR/__disk__
	mount $disk_dev $VFS_SOURCE_DIR/__disk__
	echo "Mounted '$disk_dev' to '$VFS_SOURCE_DIR/__disk__'."
	mkdir -p $VFS_SOURCE_DIR/__disk__/boot
	cp -v $BOOT_BUILD_DIR/vmlinuz-$KERNEL_RELEASE $BOOT_BUILD_DIR/vfs-full.gz $VFS_SOURCE_DIR/__disk__/boot/

	# Install GRUB
	#chroot_real $VFS_SOURCE_DIR grub-install `echo $disk_dev | sed 's/[0-9]\+$//'` --root-directory=/__disk__
	#sleep 1
	#clean_chroot $VFS_SOURCE_DIR

	if ! [ -f $VFS_SOURCE_DIR/__disk__/boot/grub/menu.lst ]; then
		mkdir -p $VFS_SOURCE_DIR/__disk__/boot/grub
		( generate_grub_menu ) > $VFS_SOURCE_DIR/__disk__/boot/grub/menu.lst
	fi

	umount $VFS_SOURCE_DIR/__disk__
	rmdir $VFS_SOURCE_DIR/__disk__
	echo "Unmounted '$disk_dev' from '$VFS_SOURCE_DIR/__disk__'."

	echo
	print_green ">>> You may have to add these options to '/boot/grub/menu.lst' of your flash disk:"
	echo
	generate_grub_menu
	echo
	print_green ">>> Then run:"

	cat <<EOF

mkdir -p $VFS_SOURCE_DIR/media
mount $disk_dev $VFS_SOURCE_DIR/media
$0 chroot
grub-install `echo $disk_dev | sed 's/[0-9]\+$//'` --root-directory=/media
exit
umount $VFS_SOURCE_DIR/media

EOF

}

do_enter_chroot()
{
	chroot_real $VFS_SOURCE_DIR bash || :
	sleep 0.2
	clean_chroot $VFS_SOURCE_DIR
}

do_cleanup()
{
	rm -rf $BOOT_BUILD_DIR

	( cd $VFS_SOURCE_DIR; rm -rf lib/firmware lib/modules )

	if [ -d $KERNEL_BUILD_DIR ]; then
		local cf
		read -p "Delete kernel source directory '$KERNEL_BUILD_DIR' [y/N]? " cf
		case "$cf" in
			y*|Y*)
				echo "Deleting $KERNEL_BUILD_DIR ..."
				rm -rf $KERNEL_BUILD_DIR
				echo "Done."
				;;
		esac
	fi
}

case "$1" in
	"create")
		do_build_all
		;;
	"clean")
		do_cleanup
		;;
	"install")
		do_install_disk $2
		;;
	"chroot")
		do_enter_chroot
		;;
	*)
		echo "Bootable LiveUSB Linux creator."
		echo "Usage:"
		echo "  $0 create                build kernel image and rootfs ramdisk"
		echo "  $0 install /dev/sdxn     write to your flash disk"
		echo "  $0 chroot                chroot to the target filesystem"
		echo "  $0 clean                 cleanup workspace"
		echo "  $0                       show help"
		;;
esac


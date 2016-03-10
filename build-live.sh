#!/bin/bash -e

KERNEL_VERSION=4.1.18
KERNEL_RELEASE=$KERNEL_VERSION-liveusb
KERNEL_DOWNLOAD_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.1.18.tar.gz"

VFS_SOURCE_DIR=vfs-full
BOOT_INSTALL_DIR=boot
KERNEL_BUILD_DIR=linux-$KERNEL_VERSION
VMLINUZ_FILE=vmlinuz-$KERNEL_RELEASE
RAMDISK_FILE=ramdisk.img-$KERNEL_RELEASE

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
kernel  /boot/$VMLINUZ_FILE root=/dev/ram0 rw
initrd  /boot/$RAMDISK_FILE

EOF

}

__prepare_kernel_dir()
{
	# Check if kernel source exists, if not download it
	if ! [ -d $KERNEL_BUILD_DIR ]; then
		local kernel_tar=`basename "$KERNEL_DOWNLOAD_URL"`
		if ! [ -f "$kernel_tar" ]; then
			wget $KERNEL_DOWNLOAD_URL -O $kernel_tar
		fi

		local tar_opts=
		case "$kernel_tar" in
			*.tar.bz2)
				tar_opts=jxf
				;;
			*.tar.gz)
				tar_opts=zxf
				;;
			*.tar.xz)
				tar_opts=Jxf
				;;
			*)
				echo "*** Unsupported tarball format '$kernel_tar'."
				exit 1
				;;
		esac

		print_green "Extracting the kernel ..."
		tar $tar_opts $kernel_tar
		print_green "Done."
	fi

	# Check symlink: config -> config-x.x.x-xxx
	if ! [ -L config ]; then
		echo "*** Please create symbolic link 'config' to one of the config files."
		exit 1
	fi
}

do_menuconfig()
{
	__prepare_kernel_dir

	# Backup old config
	( cd $KERNEL_BUILD_DIR; [ -f .config ] && cp .config .config.bak || : )
	# Use new config
	cat config > $KERNEL_BUILD_DIR/.config
	# Show menuconfig window
	( cd $KERNEL_BUILD_DIR; exec make menuconfig ) || exit 1
	# Copy back
	cat $KERNEL_BUILD_DIR/.config > config
}

__build_kernel()
{
	__prepare_kernel_dir

	# Use the config file
	cat config > $KERNEL_BUILD_DIR/.config

	local i
	for i in 5 4 3 2 1; do
		echo "Waiting ${i}s to build ..."
		sleep 1
	done

	# Compile the kernel and selected drivers using 8 threads
	local nr_threads=`grep '^processor' /proc/cpuinfo | wc -l`
	[ -n "$nr_threads" ] || nr_threads=2
	make -j$nr_threads -C $KERNEL_BUILD_DIR
	# .config may change during compiling, update the one in source
	### cat $KERNEL_BUILD_DIR/.config > config

	mkdir -p $BOOT_INSTALL_DIR
	# Compile
	make -C $KERNEL_BUILD_DIR
	# Install kernel image
	cp $KERNEL_BUILD_DIR/arch/x86/boot/bzImage $BOOT_INSTALL_DIR/$VMLINUZ_FILE
	# Install modules
	make modules_install -C $KERNEL_BUILD_DIR INSTALL_MOD_PATH=`pwd`/$VFS_SOURCE_DIR INSTALL_MOD_STRIP=1

	# Regenerate module dependencies after copying drivers
	chroot_real $VFS_SOURCE_DIR depmod -a $KERNEL_RELEASE
	sleep 1
	clean_chroot $VFS_SOURCE_DIR
}

do_build_all()
{
	local rd_file=`pwd`/__ramdisk.img__
	local rd_mnt=`pwd`/__ramdisk.mnt__
	
	__build_kernel
	
	dd if=/dev/zero of=$rd_file bs=1M count=64
	mkfs.ext2 -F -m 0 $rd_file
	mkdir -p $rd_mnt
	mount $rd_file $rd_mnt -o loop

	(
		cd $VFS_SOURCE_DIR
		tar -c --exclude-vcs * | tar -x -C $rd_mnt

		cd $rd_mnt

		# Recreate missing directories
		mkdir -p dev sys proc var tmp media
		mkdir -p var/run var/empty/sshd

		# Create basic device files
		(
			cd $rd_mnt/dev
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
		)

		# Fix file permissions
		chmod 600 etc/ssh/*_key
		chmod 755 var/empty/sshd

		# Reset file owners as root
		chown root:root . -R
	)

	umount $rd_mnt
	rmdir $rd_mnt
	gzip -c $rd_file > $BOOT_INSTALL_DIR/$RAMDISK_FILE
	rm -f $rd_file

	# Write a menu.lst sample
	mkdir -p $BOOT_INSTALL_DIR/grub
	( generate_grub_menu ) > $BOOT_INSTALL_DIR/grub/menu.lst

	print_green "Built successfully."
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

	if ! [ -f $BOOT_INSTALL_DIR/$VMLINUZ_FILE -a -f $BOOT_INSTALL_DIR/$RAMDISK_FILE ]; then
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
	print_green "Mounted '$disk_dev' to '$VFS_SOURCE_DIR/__disk__'."
	mkdir -p $VFS_SOURCE_DIR/__disk__/boot
	cp -v $BOOT_INSTALL_DIR/$VMLINUZ_FILE $BOOT_INSTALL_DIR/$RAMDISK_FILE $VFS_SOURCE_DIR/__disk__/boot/

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
	print_green "Unmounted '$disk_dev' from '$VFS_SOURCE_DIR/__disk__'."

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
	rm -rf $BOOT_INSTALL_DIR

	( cd $VFS_SOURCE_DIR; rm -rf lib/firmware lib/modules )

	if [ -d $KERNEL_BUILD_DIR ]; then
		local cf
		read -p "Delete kernel source directory '$KERNEL_BUILD_DIR' [yes/No]? " cf
		case "$cf" in
			yes|YES)
				echo "Deleting $KERNEL_BUILD_DIR ..."
				rm -rf $KERNEL_BUILD_DIR
				echo "Done."
				;;
		esac
	fi
}

case "$1" in
	create)
		do_build_all
		;;
	menuconfig)
		do_menuconfig
		;;
	clean)
		do_cleanup
		;;
	install)
		do_install_disk $2
		;;
	chroot)
		do_enter_chroot
		;;
	*)
		echo "Bootable LiveUSB Linux creator."
		echo "Usage:"
		echo "  $0 create                build kernel image and rootfs ramdisk"
		echo "  $0 menuconfig            show menuconfig for updating kernel configuration"
		echo "  $0 install /dev/sdxn     write to your flash disk"
		echo "  $0 chroot                chroot to the target filesystem"
		echo "  $0 clean                 cleanup workspace"
		echo "  $0                       show help"
		;;
esac


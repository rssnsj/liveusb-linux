#!/bin/bash -e

KERNEL_VERSION=4.1.18
KERNEL_RELEASE=$KERNEL_VERSION-liveusb
KERNEL_DOWNLOAD_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.1.18.tar.xz"

VFS_SOURCE_DIR=vfs-full
BOOT_INSTALL_DIR=boot
KERNEL_BUILD_DIR=`basename "$KERNEL_DOWNLOAD_URL" | sed 's/\.tar\>.*$//'`
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
		if ! [ -f dl/$kernel_tar ]; then
			mkdir -p dl
			wget $KERNEL_DOWNLOAD_URL -O dl/$kernel_tar
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
		tar $tar_opts dl/$kernel_tar
		print_green "Done."
	fi

	# Check symlink: config -> config-x.x.x-xxx
	if ! [ -L config ]; then
		echo "*** Please create symbolic link 'config' to one of the config files."
		exit 1
	fi

	# Set 'ARCH=um' when compiling as UMLinux
	if grep '\<CONFIG_UML=y\>' config >/dev/null; then
		export ARCH=um
	else
		unset ARCH
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
	for i in 3 2 1; do
		echo "Waiting ${i}s to compile kernel ..."
		sleep 1
	done

	# Inherits jobserver parameters from parent Makefile
	make -C $KERNEL_BUILD_DIR
	# .config may change during compiling, update the one in source
	### cat $KERNEL_BUILD_DIR/.config > config

	# Install kernel image
	if [ "$ARCH" != um ]; then
		cp $KERNEL_BUILD_DIR/arch/x86/boot/bzImage $BOOT_INSTALL_DIR/$VMLINUZ_FILE
	else
		cp $KERNEL_BUILD_DIR/linux $BOOT_INSTALL_DIR/$VMLINUZ_FILE
	fi

	# Install modules
	rm -rf ./$VFS_SOURCE_DIR/lib/modules/$KERNEL_RELEASE
	make modules_install -C $KERNEL_BUILD_DIR INSTALL_MOD_PATH=`pwd`/$VFS_SOURCE_DIR INSTALL_MOD_STRIP=1
}

__build_ramdisk()
{
	rm -rf rootdir
	mkdir -p rootdir

	( cd $VFS_SOURCE_DIR && tar -c --exclude-vcs * ) | tar -x -C rootdir

	(
		cd rootdir

		# Recreate missing directories
		mkdir -p dev sys proc var tmp media
		mkdir -p var/run var/empty/sshd
		mkdir -p dev/pts dev/shm
		ln -s ram0 dev/ramdisk
		ln -s ram1 dev/ram

		# Fix file permissions
		chmod 600 etc/ssh/*_key
		chmod 755 var/empty/sshd

		if [ "$ARCH" != um ]; then
			# Remove console tty0 for regular system
			sed -i '/^0:.*\<tty0/d' etc/inittab
		else
			# Remove tty1-6, ttyS0 for UMLinux
			sed -i '/^[1-6]:.*\<tty[1-6]/d; /^S0:.*ttyS0/d' etc/inittab
		fi
	)

	cat > devicetable <<EOF
# name       type mode uid gid major minor start inc count
/dev/ram      b   644  0    0    1    0    0    1    3
/dev/console  c   644  0    0    5    1    0    0    -
/dev/tty      c   666  0    0    5    0    0    0    -
/dev/tty      c   666  0    0    4    0    0    1    6
/dev/null     c   666  0    0    1    3    0    0    -
/dev/ptmx     c   644  0    0    5    2    0    0    -
/dev/urandom  c   666  0    0    1    9    0    0    -
/dev/zero     c   666  0    0    1    5    0    0    -
EOF

	genext2fs -b 45056 -d rootdir -i 4096 -m 0 -U -D devicetable imgfile
	gzip -c imgfile > $BOOT_INSTALL_DIR/$RAMDISK_FILE

	rm -f imgfile devicetable
	rm -rf rootdir
}

do_build_all()
{
	mkdir -p $BOOT_INSTALL_DIR

	print_green "Building Linux kernel ..."
	__build_kernel

	print_green "Building the ramdisk ..."
	__build_ramdisk

	if [ "$ARCH" != um ]; then
		# Write a menu.lst sample
		mkdir -p $BOOT_INSTALL_DIR/grub
		( generate_grub_menu ) > $BOOT_INSTALL_DIR/grub/menu.lst
	fi

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
	for i in 4 3 2 1; do
		echo "Waiting ${i}s to install to $disk_dev ..."
		sleep 1
	done

	mkdir -p $VFS_SOURCE_DIR/__disk__
	mount $disk_dev $VFS_SOURCE_DIR/__disk__
	print_green "Mounted '$disk_dev' to '$VFS_SOURCE_DIR/__disk__'."
	mkdir -p $VFS_SOURCE_DIR/__disk__/boot
	cp -v $BOOT_INSTALL_DIR/$VMLINUZ_FILE $BOOT_INSTALL_DIR/$RAMDISK_FILE $VFS_SOURCE_DIR/__disk__/boot/

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

do_cleanup()
{
	rm -rf $BOOT_INSTALL_DIR

	( cd $VFS_SOURCE_DIR; rm -rf lib/firmware lib/modules )

	if [ -d $KERNEL_BUILD_DIR ]; then
		# YES by default
		local cf
		read -p "Delete kernel source directory '$KERNEL_BUILD_DIR' [Y/n]? " cf
		case "$cf" in
			n*|N*)
				;;
			*)
				echo "Deleting $KERNEL_BUILD_DIR ..."
				rm -rf $KERNEL_BUILD_DIR
				echo "Done."
				;;
		esac
	fi
}

case "$1" in
	__build_ramdisk)
		__build_ramdisk
		;;
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
	*)
		echo "Bootable LiveUSB Linux creator."
		echo "Usage:"
		echo "  $0 create                build kernel image and rootfs ramdisk"
		echo "  $0 menuconfig            show menuconfig for updating kernel configuration"
		echo "  $0 install /dev/sdxn     write to your flash disk"
		echo "  $0 clean                 cleanup workspace"
		echo "  $0                       show help"
		;;
esac


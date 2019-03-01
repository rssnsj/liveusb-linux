#!/bin/bash -e

KERNEL_VERSION=4.1.18
KERNEL_RELEASE=$KERNEL_VERSION-liveusb
KERNEL_DOWNLOAD_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.1.18.tar.xz"

VFS_SOURCE_DIR=vfs-full
BOOT_INSTALL_DIR=bin/boot
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
	mkdir -p $BOOT_INSTALL_DIR/grub
	cat > $BOOT_INSTALL_DIR/grub/grub.cfg <<EOF
set default=0
set timeout=5
# set root='(hd0,1)'

menuentry "Linux - $KERNEL_RELEASE (ramdisk)" {
	linux /boot/$VMLINUZ_FILE root=/dev/ram0 rw
	initrd /boot/$RAMDISK_FILE
}

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

	print_green "Building Linux kernel ..."

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
	rm -rf ./$VFS_SOURCE_DIR/lib/modules ./$VFS_SOURCE_DIR/lib/firmware
	make modules_install -C $KERNEL_BUILD_DIR INSTALL_MOD_PATH=`pwd`/$VFS_SOURCE_DIR INSTALL_MOD_STRIP=1
}

__build_ramdisk()
{
	print_green "Building the ramdisk ..."

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

	__build_kernel

	__build_ramdisk

	if [ "$ARCH" != um ]; then
		# Write a grub.cfg sample
		generate_grub_menu
	fi

	print_green "Done."
}

do_cleanup()
{
	rm -rf $BOOT_INSTALL_DIR/boot/grub/grub.cfg \
		$BOOT_INSTALL_DIR/boot/vmlinuz-* \
		$BOOT_INSTALL_DIR/boot/ramdisk.img-* 

	( cd $VFS_SOURCE_DIR && rm -rf lib/firmware lib/modules )

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
	build_all)
		do_build_all
		;;
	menuconfig)
		do_menuconfig
		;;
	clean)
		do_cleanup
		;;
	build_ramdisk)
		__build_ramdisk
		;;
	build_kernel)
		__build_kernel
		;;
	*)
		echo "Bootable LiveUSB Linux creator."
		echo "Usage:"
		echo "  $0 build                 build kernel image and rootfs ramdisk"
		echo "  $0 menuconfig            show menuconfig for updating kernel configuration"
		echo "  $0 clean                 cleanup workspace"
		echo "  $0                       show help"
		;;
esac


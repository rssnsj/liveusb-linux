#!/bin/bash -e

KERNEL_VERSION=4.1.18
KERNEL_RELEASE=$KERNEL_VERSION-liveusb
KERNEL_DOWNLOAD_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.1.18.tar.xz"

VFS_SOURCE_DIR=rootfs
BOOT_INSTALL_DIR=boot
KERNEL_BUILD_DIR=`basename "$KERNEL_DOWNLOAD_URL" | sed 's/\.tar\>.*$//'`
VMLINUZ_FILE=vmlinuz-$KERNEL_RELEASE
RAMDISK_FILE=ramdisk.img-$KERNEL_RELEASE

is_tty()
{
	if [ -z "$_is_tty" ]; then
		case "`readlink /proc/$$/fd/1`" in
			/dev/pts/*|/dev/tty*|/dev/pty*) _is_tty=Y;;
			*) _is_tty=N;;
		esac
	fi
	[ "$_is_tty" = Y ]
}
echo_g() { is_tty && echo -e "\033[32m$@\033[0m" || echo "$@"; }
echo_r() { is_tty && echo -e "\033[31m$@\033[0m" || echo "$@"; }

generate_grub_menu()
{
	mkdir -p $BOOT_INSTALL_DIR

	if [ "$ARCH" != um ]; then
		cp -a boot-files/boot/grub $BOOT_INSTALL_DIR/
		# Write a grub.cfg example
		cat > $BOOT_INSTALL_DIR/grub/grub.cfg <<EOF
set default=0
set timeout=5
# set root='(hd0,1)'

menuentry "Linux - $KERNEL_RELEASE (ramdisk)" {
	linux /boot/$VMLINUZ_FILE root=/dev/ram0 rw
	initrd /boot/$RAMDISK_FILE
}

EOF
	else
		# Write a boot script example
		cat > $BOOT_INSTALL_DIR/boot-initrd.sh <<EOF
#!/bin/sh -x
exec ./$VMLINUZ_FILE mem=192m initrd=$RAMDISK_FILE root=/dev/ram0 eth0=tuntap,tap0,00:ab:ab:ab:ab:ba
EOF
		# Host setup script example
		cat > $BOOT_INSTALL_DIR/host-setting.sh <<EOF
#!/bin/sh -x

ip tuntap del tap0 mode tap

ip tuntap add tap0 mode tap user root
ifconfig tap0 up
brctl addif lan1 tap0
if ! grep '\/dev\/shm' /proc/mounts >/dev/null; then
	mount shm /dev/shm -t tmpfs
fi
EOF
		chmod +x $BOOT_INSTALL_DIR/{boot-initrd.sh,host-setting.sh}
	fi
}

__prepare_kernel_dir()
{
	# Check symlink: config -> config-x.x.x-xxx
	if ! [ -L config -a -L rootfs ]; then
		echo_r "*** Create the following symbolic links to go:"
		echo_r "*** 1. config -> kernel configuration to use (e.g., config-4.1.18-x86_64)"
		echo_r "*** 2. rootfs -> filesystem tree to use (e.g., rootfs-x86_64)"
		echo
		exit 1
	fi

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

		echo_g "Extracting the kernel ..."
		tar $tar_opts dl/$kernel_tar
		echo_g "Done."
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

	echo_g "Building Linux kernel ..."

	# Inherits jobserver parameters from parent Makefile
	make -C $KERNEL_BUILD_DIR
	# .config may change during compiling, update the one in source
	### cat $KERNEL_BUILD_DIR/.config > config

	# Install kernel image
	mkdir -p $BOOT_INSTALL_DIR
	if [ "$ARCH" != um ]; then
		cp $KERNEL_BUILD_DIR/arch/x86/boot/bzImage $BOOT_INSTALL_DIR/$VMLINUZ_FILE
	else
		cp $KERNEL_BUILD_DIR/linux $BOOT_INSTALL_DIR/$VMLINUZ_FILE
	fi

	# Install modules
	rm -rf ./$VFS_SOURCE_DIR/lib/{firmware,modules}
	make modules_install -C $KERNEL_BUILD_DIR INSTALL_MOD_PATH=`pwd`/$VFS_SOURCE_DIR INSTALL_MOD_STRIP=1
}

__build_ramdisk()
{
	echo_g "Building the ramdisk ..."

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
	__build_kernel

	__build_ramdisk

	# Write a grub.cfg sample
	generate_grub_menu

	echo_g "Done."
}

do_cleanup()
{
	rm -rf $BOOT_INSTALL_DIR/grub/grub.cfg \
		$BOOT_INSTALL_DIR/{vmlinuz-*,ramdisk.img-*} \
		$BOOT_INSTALL_DIR/{boot-initrd.sh,host-setting.sh}

	rm -rf rootfs-*/lib/{firmware,modules}

	if [ -d $KERNEL_BUILD_DIR ]; then
		# YES by default
		local cf
		read -p "Delete kernel source directory '$KERNEL_BUILD_DIR' [Y/n]? " cf
		case "$cf" in
			y*|Y*|'')
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


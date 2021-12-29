#!/bin/bash -e

KERNEL_VERSION=4.1.18
KERNEL_RELEASE=$KERNEL_VERSION-liveusb
KERNEL_DOWNLOAD_URL="https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.1.18.tar.xz"

VFS_SOURCE_DIR=rootfs
INSTALL_DIR=bin
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

__prepare_kernel_dir()
{
	# Check symlink: config -> config-x.x.x-xxx
	if ! [ -d rootfs ]; then
		echo_r "*** Directory 'rootfs' does not exist."
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

build_kernel()
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
	if [ "$ARCH" = um ]; then
		cp $KERNEL_BUILD_DIR/linux $VMLINUZ_FILE
	else
		cp $KERNEL_BUILD_DIR/arch/x86/boot/bzImage $VMLINUZ_FILE
	fi

	# Install modules
	rm -rf ./$VFS_SOURCE_DIR/lib/{firmware,modules}
	make modules_install -C $KERNEL_BUILD_DIR INSTALL_MOD_PATH=`pwd`/$VFS_SOURCE_DIR INSTALL_MOD_STRIP=1
}

build_ramdisk()
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

		if [ "$ARCH" = um ]; then
			# Remove tty1-6, ttyS0 for UMLinux
			sed -i '/^[1-6]:.*\<tty[1-6]/d; /^S0:.*ttyS0/d' etc/inittab
		else
			# Remove console tty0 for regular system
			sed -i '/^0:.*\<tty0/d' etc/inittab
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
	gzip -c < imgfile > $RAMDISK_FILE

	rm -f imgfile devicetable
	rm -rf rootdir
}

# Create the target file tree
install_targets()
{
	echo_g "Installing files to $INSTALL_DIR/ ..."

	mkdir -p $INSTALL_DIR

	if [ "$ARCH" = um ]; then
		mv $VMLINUZ_FILE $RAMDISK_FILE $INSTALL_DIR/
		# Write a boot script example
		cat > $INSTALL_DIR/boot-initrd.sh <<EOF
#!/bin/sh -x
exec ./$VMLINUZ_FILE mem=192m initrd=$RAMDISK_FILE root=/dev/ram0 eth0=tuntap,tap0,00:ab:ab:ab:ab:ba
EOF
		# Host setup script example
		cat > $INSTALL_DIR/host-setting.sh <<EOF
#!/bin/sh -x

ip tuntap del tap0 mode tap

ip tuntap add tap0 mode tap user root
ifconfig tap0 up
brctl addif lan1 tap0
if ! grep '\/dev\/shm' /proc/mounts >/dev/null; then
	mount shm /dev/shm -t tmpfs
fi
EOF
		chmod +x $INSTALL_DIR/{boot-initrd.sh,host-setting.sh}
	else
		cp -a ../src/boot-files/{boot,EFI} $INSTALL_DIR/
		mv $VMLINUZ_FILE $RAMDISK_FILE $INSTALL_DIR/boot/
		# Write a grub.cfg example
		cat > $INSTALL_DIR/boot/grub/grub.cfg <<EOF
set default=0
set timeout=5
# set root='(hd0,1)'

menuentry "Linux - $KERNEL_RELEASE (ramdisk)" {
	linux /boot/$VMLINUZ_FILE root=/dev/ram0 rw
	initrd /boot/$RAMDISK_FILE
}

EOF
		tar -C $INSTALL_DIR/boot --owner=root --group=root -zcf $INSTALL_DIR/grub.tar.gz grub
	fi
}

do_build_all()
{
	build_kernel

	build_ramdisk

	install_targets

	echo_g "Done."
}

do_cleanup()
{
	rm -f $VMLINUZ_FILE $RAMDISK_FILE
	rm -rf $INSTALL_DIR
	rm -rf rootfs/lib/{firmware,modules}

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
	build_ramdisk|build_kernel|install_targets)
		"$@"
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


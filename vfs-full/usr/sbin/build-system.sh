#!/bin/sh

LOG_FILE="/tmp/disk-build-0.log"
ROOT_MOUNT_POINT="/tmp/__root_fs_dir"
VERBOSE_MODE="n"
ENABLE_FDISK="n"
ENABLE_LIVEUSB="n"

ROOT_FS_DEV=""
ROOT_FS_TYPE=""
ROOT_FS_LABEL=""

SWAP_FS_DEV=""
SWAP_FS_LABEL=""

PART3_FS_DEV=""
PART3_FS_TYPE=""
PART3_FS_LABEL=""
PART3_FS_MOUNT_POINT=""

ROOT_HOSTNAME=""

RAND_SUFFIX=`date +%s 2>/dev/null`; RAND_SUFFIX=`expr $RAND_SUFFIX % 100`

# Check `echo -e` behavior
[ "`echo -ne a`" = "a" ] && ECHO_E="echo -e" || ECHO_E="echo"

log_step_msg()
{
	[ -z "$step_i" ] && step_i=1
	$ECHO_E -n "\033[32m"
	$ECHO_E -n ">>> STEP $step_i: $1"
	$ECHO_E -n "\033[0m"
	step_i=`expr $step_i + 1`
	return 0
}

log_step_msg_bh()
{
	$ECHO_E -n "\033[32m"
	$ECHO_E -n "$1"
	$ECHO_E "\033[0m"
	return 0
}

log_error_msg()
{
	echo "*** ERROR: $1" >&2
	return 0
}

log_warning_msg()
{
	echo "*** WARNING: $1" >&2
	return 0
}

confirm_short()
{
	local m=""
	echo -n "$1 "
	[ ! -z "$2" ] && echo -n "[$2]? "
	while true; do
		read m
		[ -z "$m" ] && m="$2"
		if [ "$m" = "y" -o "$m" = "Y" -o "$m" = "yes" ]; then
			return 0
		elif [ "$m" = "n" -o "$m" = "N" -o "$m" = "no" ]; then
			return 1
		else
			echo -n "Please say 'Y' or 'N': "
		fi
	done
}

##############################################################
# fdisk_and_mkswap_only():
#  Used glocal variables:
#   $DISK_DEV: Device file for disk (e.g., /dev/sda)
#   $ROOT_OPTION: Options for root filesystem (e.g., "20G,ext2,system")
#   $SWAP_OPTION: Options for swap partition (e.g., "2G,swapa")
#   $PART3_OPTION: Options for 3rd partition (e.g., ",ext3,admdata,/adm")
#  return values: 0 for success, non-zero for failure
#    Note that ROOT_FS_DEV, ROOT_FS_TYPE, ROOT_FS_LABEL, SWAP_FS_DEV, SWAP_FS_LABEL are set.
##############################################################
fdisk_and_mkswap_only()
{
	local root_sz_mb=""
	local swap_sz_mb=""
	local part3_sz_mb=""
	local mkfs_cmd=""
	local __dev_minor_i=1
	
	# Check root options
	if [ ! -z "$ROOT_OPTION" ]; then
		local __root_sz=`echo $ROOT_OPTION |awk -F, 'NR==1 {print $1}'`
		ROOT_FS_TYPE=`echo $ROOT_OPTION |awk -F, 'NR==1 {print $2}'`
		ROOT_FS_LABEL=`echo $ROOT_OPTION |awk -F, 'NR==1 {print $3}'`
		# Check the size
		if [ -z "$__root_sz" -o "$__root_sz" = "-" ]; then
			root_sz_mb=""
		else
			root_sz_mb=`echo $__root_sz |awk -F'[MmGg]' '/[0-9.]*[gG]/{print int(1024*$1);} /[0-9]*[Mm]/{print int($1);}'`
			[ -z "$root_sz_mb" ] && { log_error_msg "Invalid size '$__root_sz' for root partition. "; return 1; }
		fi
		# Check FS type, default as 'ext3'
		[ -z "$ROOT_FS_TYPE" ] && ROOT_FS_TYPE="ext3"
		# Check label name, or assign a random one if no label is set
		[ -z "$ROOT_FS_LABEL" ] && ROOT_FS_LABEL="vfs-$RAND_SUFFIX"
		###
		ROOT_FS_DEV=${DISK_DEV}${__dev_minor_i}; __dev_minor_i=`expr $__dev_minor_i + 1`
	else
		log_error_msg "No options specified for root partition. "
		return 1
	fi
	
	# Check swap options
	if [ ! -z "$SWAP_OPTION" ]; then
		[ -z "$root_sz_mb" ] && { log_error_msg "Cannot create swap area if you use the entire disk as root. "; return 1; }
		###
		local __swap_sz=`echo $SWAP_OPTION |awk -F, 'NR==1 {print $1}'`
		SWAP_FS_LABEL=`echo $SWAP_OPTION |awk -F, 'NR==1 {print $2}'`
		[ ! -z "$__swap_sz" ] && swap_sz_mb=`echo $__swap_sz |awk -F'[MmGg]' '/[0-9.]*[gG]/{print int(1024*$1);} /[0-9]*[Mm]/{print int($1);}'`
		[ -z "$swap_sz_mb" ] && { log_error_msg "Invalid size for swap area. "; return 1; }
		# Check the label name, or assign a random one if no label is set
		[ -z "$SWAP_FS_LABEL" ] && SWAP_FS_LABEL="swap-$RAND_SUFFIX"
		###
		SWAP_FS_DEV=${DISK_DEV}${__dev_minor_i}; __dev_minor_i=`expr $__dev_minor_i + 1`
	fi
	
	# Check the 3rd partition options if needs created
	if [ ! -z "$PART3_OPTION" ]; then
		# Check root size
		[ -z "$root_sz_mb" ] && { log_error_msg "Cannot create 3rd partition if you use the entire disk as root. "; return 1; }
		### Check if swap area exists, force to create it when 3rd partition specified
		### [ -z "$swap_sz_mb" ] && { log_error_msg "Swap area is required when 3rd partition created. "; return 1; }
		###
		local __part3_sz=`echo $PART3_OPTION |awk -F, 'NR==1 {print $1}'`
		PART3_FS_TYPE=`echo $PART3_OPTION |awk -F, 'NR==1 {print $2}'`
		PART3_FS_LABEL=`echo $PART3_OPTION |awk -F, 'NR==1 {print $3}'`
		PART3_FS_MOUNT_POINT=`echo $PART3_OPTION |awk -F, 'NR==1 {print $4}'`
		[ ! -z "$__part3_sz" ] && part3_sz_mb=`echo $__part3_sz |awk -F'[MmGg]' '/[0-9.]*[gG]/{print int(1024*$1);} /[0-9]*[Mm]/{print int($1);}'`
		# Check FS type, default as 'ext3'
		[ -z "$PART3_FS_TYPE" ] && PART3_FS_TYPE="ext3"
		###
		PART3_FS_DEV=${DISK_DEV}${__dev_minor_i}; __dev_minor_i=`expr $__dev_minor_i + 1`
	fi
	
	echo

	# Create partitions
	(
		# Partition 1: /
		if [ ! -z "$root_sz_mb" ]; then
			echo "0,$root_sz_mb,L,*"
		else
			echo "0,,L,*"
		fi
		# Partition 2: swap
		if [ ! -z "$SWAP_OPTION" ]; then
			echo ",$swap_sz_mb,S"
		fi
		# Partition 3: 3rd F.S.
		if [ ! -z "$PART3_OPTION" ]; then
			[ ! -z "$part3_sz_mb" ] && echo ",$part3_sz_mb,L" || echo ",,L"
		fi
		# Partition else: empty
		while [ $__dev_minor_i -le 4 ]; do
			echo "0,0"
			__dev_minor_i=`expr $__dev_minor_i + 1`
		done
	) | sfdisk -uM "$DISK_DEV" || { echo; log_error_msg "Partitioning error. "; return 1; }
	
	echo -n "Waiting for the partitions to be ready ... "
	[ ! -z "$ROOT_FS_DEV" ] && while [ ! -e "$ROOT_FS_DEV" ]; do sleep 0.2; done
	[ ! -z "$SWAP_FS_DEV" ] && while [ ! -e "$SWAP_FS_DEV" ]; do sleep 0.2; done
	echo "OK!"
	
	# Make swap area if defined
	if [ ! -z "$SWAP_FS_DEV" ]; then
		echo "Formatting swap area on $SWAP_FS_DEV, size: ${swap_sz_mb}M, label: $SWAP_FS_LABEL ... "
		mkswap -L "$SWAP_FS_LABEL" $SWAP_FS_DEV || \
			{ echo; log_error_msg "Formatting swap area error. "; return 1; }
		echo "done!"
	fi
	
	return 0
}

##############################################################
# check_root_options():
#  Check the options for root filesystem, without partitioning.
#  $1: Device file for disk (e.g., /dev/sda)
#  $2: Options for root filesystem
#  return values: 0 for success, non-zero for failure
#    Note that ROOT_FS_TYPE, ROOT_FS_LABEL are set.
##############################################################
check_root_options()
{
	# Check root options
	if [ ! -z "$ROOT_OPTION" ]; then
		local __root_sz=`echo $ROOT_OPTION |awk -F, 'NR==1 {print $1}'`
		ROOT_FS_TYPE=`echo $ROOT_OPTION |awk -F, 'NR==1 {print $2}'`
		ROOT_FS_LABEL=`echo $ROOT_OPTION |awk -F, 'NR==1 {print $3}'`
		# Check the size
		[ -z "$__root_sz" -o "$__root_sz" = "-" ] || { echo; log_error_msg "Size for root partition is not supported in current mode. "; return 1; }
		# Check the label name, and assign a random one if no label is set
		[ -z "$ROOT_FS_LABEL" ] && ROOT_FS_LABEL="vfs-$RAND_SUFFIX"
		###
	else
		log_error_msg "No options specified for root partition. "
		return 1
	fi

	# Change partition ID
	local root_i=`expr $ROOT_FS_DEV : '\/dev\/[sh]d[a-z]\([0-9]\)'`
	[ -z "$root_i" ] && { echo; log_error_msg "Cannot determine a partition number for root filesystem. "; return 1; }
	sfdisk --change-id $DISK_DEV $root_i 83
}

##############################################################
# format_linux_fs():
#  $1: Device file for the partition (e.g., /dev/sdb1)
#  $2: Filesystem type (e.g., ext2, ext3)
#  $3: Label (optional)
#  return values: 0 for success, non-zero for failure
##############################################################
format_linux_fs()
{
	local __fs_dev=$1
	local __fs_type=$2
	local __fs_label=$3
	local mkfs_cmd=""
	local mkfs_opt=""
	
	# Make linux filesystem
	if [ "$__fs_type" = "ext2" ]; then
		mkfs_cmd="mkfs.ext2"
		mkfs_opt=""
	elif [ "$__fs_type" = "ext3" ]; then
		mkfs_cmd="mkfs.ext3"
		mkfs_opt=""
	elif [ "$__fs_type" = "ext4" ]; then
		mkfs_cmd="mkfs.ext4"
		mkfs_opt=""
	else
		log_error_msg "Unsupported linux filesystem type '$__fs_type'. "
		return 1
	fi
	[ ! -z "$__fs_label" ] && mkfs_opt="$mkfs_opt -L $__fs_label"
	###echo $mkfs_cmd $mkfs_opt $__fs_dev; exit 1
	$mkfs_cmd $mkfs_opt $__fs_dev || { echo; log_error_msg "Formatting linux filesystem error. "; return 1; }
	
	return 0
}

##############################################################
# mount_root_and_part3():
#  $1: Device root partition (e.g., /dev/sdb1)
#  $2: Mount point directory
#  return values: 0 for success, non-zero for failure
##############################################################
mount_root_and_part3()
{
	local __root_dev="$1"
	local __root_dir="$2"
	
	mkdir -p $__root_dir
	mount $__root_dev $__root_dir || \
		{ log_error_msg "Mounting '$__root_dev' to '$__root_dir' error. "; rmdir $__root_dir; return 1; }
	
	#  If 3rd partition exists, mount corresponding location
	if [ ! -z "$PART3_FS_DEV" -a ! -z "$PART3_FS_MOUNT_POINT" ]; then
		mkdir -p "${__root_dir}${PART3_FS_MOUNT_POINT}"
		mount $PART3_FS_DEV "${__root_dir}${PART3_FS_MOUNT_POINT}" || \
			{ log_error_msg "Mounting '$PART3_FS_DEV' to '${__root_dir}${PART3_FS_MOUNT_POINT}' error."; return 1; }
	fi
	return 0
}

##############################################################
# build_root_fs():
#   Extract a tarball archive to build root filesystem, 
#    and fix some files.
#  $1: Tarball file (xxx.tar.gz | xxx.tar.bz2 | xxx.tar)
#  $2: Mount point of root partition
#  return values: 0 for success, non-zero for failure
##############################################################
build_root_fs()
{
	local __tar_file="$1"
	local ROOT_DIR="$2"
	local __tar_opts=""
	local __root_desc=""
	local __swap_desc=""
	local __part3_desc=""
	
	# Determine mount descriptions for ROOT and SWAP, such as '/dev/sda1' or 'LABEL=vfs-xx'
	[ ! -z "$ROOT_FS_LABEL" ] && __root_desc="LABEL=$ROOT_FS_LABEL" || \
		__root_desc=`echo $ROOT_FS_DEV |sed 's#/dev/\([hs]\)d[a-z]#/dev/\1da#g'`
	[ ! -z "$SWAP_FS_LABEL" ] && __swap_desc="LABEL=$SWAP_FS_LABEL" || \
		__swap_desc=`echo $SWAP_FS_DEV |sed 's#/dev/\([hs]\)d[a-z]#/dev/\1da#g'`
	[ ! -z "$PART3_FS_LABEL" ] && __part3_desc="LABEL=$PART3_FS_LABEL" || \
		__part3_desc=`echo $PART3_FS_DEV |sed 's#/dev/\([hs]\)d[a-z]#/dev/\1da#g'`
	
	##[ ! -f "$__tar_file" ] && { log_error_msg "Tarball file '$__tar_file' does not exist. "; return 1; }
	[ ! -d "$ROOT_DIR" ] && { log_error_msg "Mount point '$ROOT_DIR' does not exist. "; return 1; }
	
	##[ "$VERBOSE_MODE" = "y" ] && __tar_opts="$__tar_opts -v"
	
	case "$__tar_file" in
		http://*.tar.gz | ftp://*.tar.gz)
			wget "$__tar_file" -O- |gzip -dc |tar -xp -C "$ROOT_DIR" || return 1
			;;
		http://*.tar.bz2 | ftp://*.tar.bz2)
			wget "$__tar_file" -O- |bzip2 -dc |tar -xp -C "$ROOT_DIR" || return 1
			;;
		http://*.tar | ftp://*.tar)
			wget "$__tar_file" -O- |tar -xp -C "$ROOT_DIR" || return 1
			;;
		*.tar.gz)
			[ ! -f "$__tar_file" ] && { log_error_msg "Tarball file '$__tar_file' does not exist. "; return 1; }
			tar $__tar_opts -zxpf "$__tar_file" -C "$ROOT_DIR" || return 1
			;;
		*.tar.bz2)
			[ ! -f "$__tar_file" ] && { log_error_msg "Tarball file '$__tar_file' does not exist. "; return 1; }
			tar $__tar_opts -jxpf "$__tar_file" -C "$ROOT_DIR" || return 1
			;;
		*.tar)
			[ ! -f "$__tar_file" ] && { log_error_msg "Tarball file '$__tar_file' does not exist. "; return 1; }
			tar $__tar_opts -xpf "$__tar_file" -C "$ROOT_DIR" || return 1
			;;
		*)
			log_error_msg "Unsupported format or protocol of '$__tar_file'. "
			return 1
			;;
	esac

	# Fix root filesystem
	if [ ! -z "$ROOT_DIR" ]; then
		# Remove udev network rules
		rm -f $ROOT_DIR/etc/udev/rules.d/*-persistent-net.rules
		rm -f $ROOT_DIR/etc/udev/rules.d/*-network.rules

		# Remove the 2 files is for SECURITY
		[ -d "$ROOT_DIR/root/.ssh" ] && rm -rf $ROOT_DIR/root/.ssh
		[ -e "$ROOT_DIR/root/.bash_history" ] && echo -n >$ROOT_DIR/root/.bash_history

		# Remove device.map so that grub-install can work
		[ -e "$ROOT_DIR/boot/grub/device.map" ] && rm -f $ROOT_DIR/boot/grub/device.map

		# Update root description for GRUB
		if [ -e "$ROOT_DIR/boot/grub/menu.lst" ]; then
			sed -i "s# root=\(LABEL=\|/dev/[hs]d[a-z]\)[^ \t]*# root=$__root_desc#g" $ROOT_DIR/boot/grub/menu.lst
			local root_i=`expr $ROOT_FS_DEV : '\/dev\/[sh]d[a-z]\([0-9]\)'`
			[ ! -z "$root_i" ] && root_i=`expr $root_i - 1` || root_i=0
			sed -i "/^[ \t]*root/s/(hd[0-9],[0-9])/(hd0,$root_i)/" $ROOT_DIR/boot/grub/menu.lst
		fi

		# Update mount descriptions in '/etc/fstab' 
		if [ -e "$ROOT_DIR/etc/fstab" ]; then
			# Mount options for '/'
			sed -i "s#^[^ \t]\+\([ \t]\+\/[ \t]\+\)[^ \t]\+#$__root_desc\1$ROOT_FS_TYPE#" $ROOT_DIR/etc/fstab
			# Mount options for swap area
			if [ ! -z "$__swap_desc" ]; then
				local __fs_nr=`awk '$3~/^swap$/{print NR}' $ROOT_DIR/etc/fstab`
				[ ! -z "$__fs_nr" ] && sed -i "${__fs_nr}d" $ROOT_DIR/etc/fstab
				echo "$__swap_desc   none            swap    sw              0       0" >> $ROOT_DIR/etc/fstab
			fi
			# Mount options for 3rd partition
			local __fs_nr=`awk -vp=$PART3_FS_MOUNT_POINT '$2==p{print NR}' $ROOT_DIR/etc/fstab`
			[ ! -z "$__fs_nr" ] && sed -i "${__fs_nr}d" $ROOT_DIR/etc/fstab
			if [ ! -z "$__part3_desc" ]; then
				echo "$__part3_desc    $PART3_FS_MOUNT_POINT    $PART3_FS_TYPE    defaults        0       0" >> $ROOT_DIR/etc/fstab
			fi
		fi

		# Update hostname if it is defined
		if [ ! -z "$ROOT_HOSTNAME" ]; then
			# For Debian, Ubuntu...
			[ -f "$ROOT_DIR/etc/hostname" ] && echo "$ROOT_HOSTNAME" >$ROOT_DIR/etc/hostname
			# For Redhat, Fedora, CentOS...
			[ -f "$ROOT_DIR/etc/sysconfig/network" ] && \
				sed -i "s/^HOSTNAME=.*/HOSTNAME=$ROOT_HOSTNAME/g" $ROOT_DIR/etc/sysconfig/network
		fi

		# Do modifications for liveusb system
		if [ "$ENABLE_LIVEUSB" = "y" ]; then
			(
				echo "#!/bin/sh -e"
				echo "rm -f /etc/udev/rules.d/*-persistent-net.rules"
				echo "rm -f /etc/udev/rules.d/*-network.rules"
				echo "exit 0"
			) > $ROOT_DIR/etc/rc.local-kill
			chmod 755 $ROOT_DIR/etc/rc.local-kill
			ln -s ../rc.local-kill $ROOT_DIR/etc/rc0.d/K15rc.local-kill
			ln -s ../rc.local-kill $ROOT_DIR/etc/rc6.d/K15rc.local-kill
		fi
	fi
	return 0
}

install_grub_mbr()
{
	local __disk_dev="$1"
	local __root_dir="$2"
	grub-install "$__disk_dev" --root-directory="$__root_dir" || \
		{ echo; log_error_msg "Installing GRUB error. "; return 1; }
	return 0
}

clean_and_exit()
{
	#  If 3rd partition exists, umount it
	if [ ! -z "$PART3_FS_MOUNT_POINT" ]; then
		umount "${ROOT_MOUNT_POINT}${PART3_FS_MOUNT_POINT}" >/dev/null 2>&1
	fi
	umount $ROOT_MOUNT_POINT >/dev/null 2>&1
	rmdir $ROOT_MOUNT_POINT >/dev/null 2>&1
	rm -f $LOG_FILE
	exit $1
}

show_help()
{
	arg0=`basename $0`
	echo "Build Linux system on hard drive or a partition using a tarball archive."
	echo "Usage:"
	echo "  $arg0 <archive_file> <target_disk | target_partition> [OPTIONS]"
	echo
	echo "Examples:"
	echo "  $arg0 lenny.tar.gz /dev/sdb --root=\"12G,ext3,Lenny\" --swap=\"512M,SWAP-x\" --fdisk"
	echo "                -- Build system on /dev/sdb, with 12G root filesystem and 512M swap area."
	echo "  $arg0 http://rssn.tk/lenny.tar.gz /dev/sdb --root=\",ext3,\" --fdisk"
	echo "                -- Build system on the entire disk of /dev/sdb, using an archive file from HTTP server, this '--root' option is recommended when you build Linux on a Flash disk."
	echo "  $arg0 lenny.tar.gz /dev/sdb1 --root=\",ext3,Lenny\" "
	echo "                -- Build system on a existing partition, note that '--swap' option is not supported now."
	echo "  $arg0 lenny.tar.gz /dev/sdb1 --root=\"30G,ext3,\" --swap=\"4G,\" --part3=\",ext3,admdata,/adm\" --fdisk "
	echo "                -- Build system with an extra partition mounted on '/adm', labeled 'admdata'."
	echo
	echo "Required arguments:"
	echo "  <archive_file>             -- Archive file location, starts with 'http://', 'ftp://' or else (local filesystem), ends with 'tar', 'tar.gz' or 'tar.bz2'."
	echo "  <target_disk | partition>  -- Target disk or partition (e.g., /dev/sdb, /dev/sdb2)."
	echo
	echo "Options: "
	echo "  --root=\"size,type,label\"   -- Size, type and label for root filesystem"
	echo "  --swap=\"size,label\"        -- Size and label for swap area"
	echo "  --part3=\"size,type,label,mount_point\" "
	echo "                             -- Size, type, label and mount point for the 3rd partition"
	echo "  --fdisk                    -- This is a safety option, to make sure you really want to do re-partitioning"
	echo "  --liveusb                  -- Use this when you are creating a LiveUSB system"
	echo "  -v, --verbose              -- Verbosely show information"
	echo "  -h, --help                 -- Show this help"
	echo
	return 0
}

#############################################################

for arg; do
	case "$arg" in
		--root=*)
			ROOT_OPTION=`expr "X$arg" : '[^=]*=\(.*\)'`
			;;
		--swap=*)
			SWAP_OPTION=`expr "X$arg" : '[^=]*=\(.*\)'`
			;;
		--part3=*)
			PART3_OPTION=`expr "X$arg" : '[^=]*=\(.*\)'`
			;;
		--hostname=*)
			ROOT_HOSTNAME=`expr "X$arg" : '[^=]*=\(.*\)'`
			;;
		--help | -h)
			show_help
			exit 0
			;;
		/dev/*)
			DISK_DEV=`expr $arg : '\(\/dev\/[sh]d[a-z]\)[0-9]'`
			[ -z "$DISK_DEV" ] && DISK_DEV=$arg || ROOT_FS_DEV=$arg
			;;
		*.tar.gz | *.tar.bz2 | *.tar)
			TAR_FILE=$arg
			;;
		--fdisk)
			ENABLE_FDISK="y"
			;;
		--liveusb)
			ENABLE_LIVEUSB="y"
			;;
		--verbose | -v)
			VERBOSE_MODE="y"
			;;
		*)
			log_warning_msg "Unrecognized argument '$arg', to be ignored."
			confirm_short "Is that what you want?" "Y" || exit 0
			;;
	esac
done


# Check the arguments
[ -z "$TAR_FILE" ] && { log_error_msg "No source tarball file, use '--help' for help. "; exit 1; }
[ -z "$DISK_DEV" ] && { log_error_msg "No target disk specified, use '--help' for help. "; exit 1; }
# Check root option, and assign a default value if not set
if [ -z "$ROOT_OPTION" ]; then
	ROOT_OPTION=",ext3,vfs-$RAND_SUFFIX"
	log_warning_msg "No option for root filesystem, assuming a default value '$ROOT_OPTION'."
	confirm_short "Is that what you want? [Y/N]?" || exit 0
fi

## ---------------------------------------------------------------------
if [ -z "$ROOT_FS_DEV" ]; then
	[ "$ENABLE_FDISK" = "y" ] || { log_error_msg "Please use '--fdisk' option if you want to re-partition the disk."; exit 1; }
	# Show information about target disk to let user confirm it
	which blkid >/dev/null 2>&1 && { echo ">>> These are the information about '$DISK_DEV': "; blkid $DISK_DEV*; }
	confirm_short "NOTICE: This may cause data loss on '$DISK_DEV', are you sure to continue? [Y/N]?" || exit 0
	
	log_step_msg "Partitioning disk $DISK_DEV ... "
	if [ "$VERBOSE_MODE" = "y" ]; then
		fdisk_and_mkswap_only || clean_and_exit 1
	else
		fdisk_and_mkswap_only >>$LOG_FILE 2>&1 || { cat $LOG_FILE; clean_and_exit 2; }
		rm -f $LOG_FILE
	fi
	log_step_msg_bh "done!"
else
	which blkid >/dev/null 2>&1 && { echo ">>> These are the information about '$ROOT_FS_DEV': "; blkid $ROOT_FS_DEV; }
	confirm_short "NOTICE: This may cause data loss on '$ROOT_FS_DEV', are you sure to continue? [Y/N]?" || exit 0

	log_step_msg "Checking root option for '$ROOT_FS_DEV' ... "
	if [ "$VERBOSE_MODE" = "y" ]; then
		check_root_options || clean_and_exit 1
	else
		check_root_options >>$LOG_FILE 2>&1 || { cat $LOG_FILE; clean_and_exit 1; }
		rm -f $LOG_FILE
	fi
	log_step_msg_bh "done!"
fi
## ---------------------------------------------------------------------
log_step_msg "Formatting '$ROOT_FS_DEV' as '$ROOT_FS_TYPE', labeled '$ROOT_FS_LABEL' ... "
if [ "$VERBOSE_MODE" = "y" ]; then
	format_linux_fs $ROOT_FS_DEV $ROOT_FS_TYPE $ROOT_FS_LABEL || clean_and_exit 3
else
	format_linux_fs $ROOT_FS_DEV $ROOT_FS_TYPE $ROOT_FS_LABEL >>$LOG_FILE 2>&1 || { cat $LOG_FILE; clean_and_exit 3; }
	rm -f $LOG_FILE
fi
log_step_msg_bh "done!"
## ---------------------------------------------------------------------
if [ ! -z "$PART3_OPTION" ]; then
	log_step_msg "Formatting '$PART3_FS_DEV' as '$PART3_FS_TYPE', labeled '$PART3_FS_LABEL' ... "
	if [ "$VERBOSE_MODE" = "y" ]; then
		format_linux_fs $PART3_FS_DEV $PART3_FS_TYPE $PART3_FS_LABEL || clean_and_exit 3
	else
		format_linux_fs $PART3_FS_DEV $PART3_FS_TYPE $PART3_FS_LABEL >>$LOG_FILE 2>&1 || { cat $LOG_FILE; clean_and_exit 3; }
		rm -f $LOG_FILE
	fi
	log_step_msg_bh "done!"
fi
## ---------------------------------------------------------------------
mount_root_and_part3 $ROOT_FS_DEV $ROOT_MOUNT_POINT || clean_and_exit 4
## ---------------------------------------------------------------------
log_step_msg "'$ROOT_FS_DEV' mounted on '$ROOT_MOUNT_POINT', extracting '$TAR_FILE' to it ... "
if [ "$VERBOSE_MODE" = "y" ]; then
	build_root_fs $TAR_FILE $ROOT_MOUNT_POINT || clean_and_exit 5
else
	build_root_fs $TAR_FILE $ROOT_MOUNT_POINT || clean_and_exit 5
	#### >>$LOG_FILE 2>&1 || { cat $LOG_FILE; clean_and_exit 5; }
	rm -f $LOG_FILE
fi
log_step_msg_bh "done!"
## ---------------------------------------------------------------------
log_step_msg "Installing GRUB on $DISK_DEV (MBR) ... "
if [ "$VERBOSE_MODE" = "y" ]; then
	install_grub_mbr $DISK_DEV $ROOT_MOUNT_POINT || clean_and_exit 6
else
	install_grub_mbr $DISK_DEV $ROOT_MOUNT_POINT >>$LOG_FILE 2>&1 || { cat $LOG_FILE; clean_and_exit 6; }
	rm -f $LOG_FILE
fi
log_step_msg_bh "done!"
## ---------------------------------------------------------------------

clean_and_exit 0


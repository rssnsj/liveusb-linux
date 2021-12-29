#!/bin/sh -e

show_help()
{
	cat >&2 <<EOF
Usage:
  $0 target core_image
Arguments:
  target                target hard drive or image file
  core_image            the proper 'core.img.xxx' image
EOF
}

target=$1
core_img=$2

# Check target
if [ -f "$target" ]; then
	# a regular file
	:
elif [ -b "$target" ] && expr "$target" : '\/dev\/.*[a-z]$' >/dev/null; then
	# /dev/sda, /dev/vda
	:
else
	echo "*** Expecting hard drive or an image file." >&2
	show_help
	exit 1
fi

# Check core image file
if [ ! -f "$core_img" ]; then
	echo "*** Not a valid 'core.img.xxx' image '$core_img'." >&2
	show_help
	exit 1
fi


# MBR
head -c446 boot.img > a

# Partition table
dd if=$target bs=512 count=1 of=b || exit 1
tail -c66 b > c

# Combine for the final image
cat a c $core_img > d

# Ensure the size is <= 26K
img_sz=`cat d | wc -c`
if ! [ $img_sz -le 26624 ]; then
	echo "*** Image size ($img_sz) exceeds 26K." >&2
	exit 1
fi

# Write to target device or file
dd if=d of=$target bs=1k count=26 conv=notrunc || exit 1

rm -f a b c d

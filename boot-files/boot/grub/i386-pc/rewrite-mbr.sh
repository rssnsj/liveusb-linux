#!/bin/sh -e

target=$1
core_img=$2

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

set -x

# MBR
head -c446 boot.img > a
# Partition table
dd if=$target bs=512 count=1 of=b
tail -c66 b > c
# Combine for the final image
cat a c $core_img > d
dd if=d of=$target bs=32k count=1 conv=notrunc

rm -f a b c d

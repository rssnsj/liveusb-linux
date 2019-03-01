#!/bin/sh -e

disk="$1"

# Ensure a valid disk device rather than a partition
if [ ! -b "$disk" ]; then
	echo "*** Not a valid hard disk device '$disk'." >&2
	exit 1
elif expr "$disk" : '\/dev\/.*[a-z]$' >/dev/null; then
	# /dev/sda
	:
elif expr "$disk" : '\/dev\/mmcblk[0-9]*$' >/dev/null; then
	# /dev/mmcblk0
	:
else
	echo "*** Not a valid hard disk device '$disk'." >&2
	exit 1
fi

set -x

# Boot record
head -c446 boot.img > a
dd if=$disk bs=512 count=1 of=b
# Partition table
tail -c66 b > c
# Final image to write
cat a c core.img > d
dd if=d of=$disk bs=32k
# Cleanups
rm -f a b c d

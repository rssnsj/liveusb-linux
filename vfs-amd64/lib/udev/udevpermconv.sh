#!/bin/bash
#
# convert old udev permissions.d file to the new rules.d format.
# revision 2
#
# Written by Michael Buesch <mbuesch@freenet.de>
# This is released into the Public Domain.
#


perm_file="$1"

function processLine
{
	local line="$1"
	if [ -z "$line" ]; then
		echo
		return 1
	fi
	if [ "`echo $line | cut -b1`" = "#" ]; then
		# comment
		echo "$line"
		return 2
	fi

	local i=
	local kern_name=
	local owner=
	local group=
	local mode=
	for ((i = 1; i <= 4; i++)); do
		local tmp="`echo $line | cut -d: -f $i`"
		if [ $i -eq 1 ]; then
			kern_name="$tmp"
		elif [ $i -eq 2 ]; then
			owner="$tmp"
		elif [ $i -eq 3 ]; then
			group="$tmp"
		elif [ $i -eq 4 ]; then
			mode="$tmp"
		fi
	done
	if [ -z "$kern_name" ]; then
		echo "Malformed line:  \"$line\"" >&2
		return 3
	fi
	local need_rule="no"
	local out="KERNEL==\"$kern_name\""
	local kern_name_len="`echo $kern_name | wc -c`"
	kern_name_len="`expr $kern_name_len + 9`"
	local num_tabs="`expr 32 - $kern_name_len`"
	num_tabs="`expr $num_tabs / 8`"
	while [ $num_tabs -gt 0 ]; do
		out="${out}\t"
		num_tabs="`expr $num_tabs - 1`"
	done
	if [ -n "$owner" ] && [ "$owner" != "root" ]; then
		out="${out}, OWNER=\"$owner\""
		need_rule="yes"
	fi
	if [ -n "$group" ] && [ "$group" != "root" ]; then
		out="${out}, GROUP=\"$group\""
		need_rule="yes"
	fi
	if [ -n "$mode" ] && [ "$mode" != "0600" ] && [ "$mode" != "600" ]; then
		out="${out}, MODE=\"$mode\""
		need_rule="yes"
	fi
	if [ "$need_rule" = "no" ]; then
		echo "Do not need a rule for:  \"$line\"  (It's udev default permissions)" >&2
		return 4
	fi
	echo -e "$out"
	return 0
}

function processInput
{
	echo "Converting udev permissions file. This can take a while..." >&2
	cat $perm_file | \
	while read line; do
		processLine "$line"
	done
	echo "done." >&2
}

if ! [ -r "$perm_file" ]; then
	echo "Could not read input file" >&2
	echo "Usage: $0 old_permission_file > new_rules_file" >&2
	exit 1
fi

processInput
exit 0

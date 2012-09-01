#!/bin/sh

BUILD_SYSTEM_EXEC=""

check_build_system_exec()
{
	local __path
	for __path in . /usr/sbin /usr/bin /sbin /bin; do
		if [ -x $__path/build-system.sh ]; then
			BUILD_SYSTEM_EXEC="$__path/build-system.sh"
			break
		fi
	done
	if [ -z "$BUILD_SYSTEM_EXEC" ]; then
		"*** No 'build-system.sh' found."
		exit 1
	fi
	return 0
}

check_build_system_exec

# --------------------- Modify or add your arguments here ---------------------
exec $BUILD_SYSTEM_EXEC --root="30G,ext3," --swap="4G," --part3=",ext3,admdata,/adm" --fdisk "$@"


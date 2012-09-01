#!/bin/sh

BUILD_SYSTEM_EXEC=""

for __path in . /usr/sbin /usr/bin /sbin /bin; do
	if [ -x $__path/build-system.sh ]; then
		BUILD_SYSTEM_EXEC="$__path/build-system.sh"
		break
	fi
done
if [ -z "$BUILD_SYSTEM_EXEC" ]; then
	echo "*** No 'build-system.sh' found."
	exit 1
fi

# --------------------- Modify or add your arguments here ---------------------
exec $BUILD_SYSTEM_EXEC --root="30G,ext3,root-idcadm" --swap="4G," --part3=",ext3,admdata,/adm" --fdisk "$@"


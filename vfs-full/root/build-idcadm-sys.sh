#!/bin/sh

BUILD_SYSTEM_EXEC="/usr/sbin/build-system.sh"

[ -e "$BUILD_SYSTEM_EXEC" ] || BUILD_SYSTEM_EXEC=./build-system.sh

# --------------------- Modify or add your arguments here ---------------------
exec $BUILD_SYSTEM_EXEC --root="30G,ext3,idcadm-root" --swap="4G," --part3=",ext3,admdata,/adm" --fdisk "$@"


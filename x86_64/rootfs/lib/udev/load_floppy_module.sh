#!/bin/sh
########################################################################
#
# Description : load_floppy_module
#
# Authors     : Based on Open Suse Udev Rules
#               kay.sievers at suse.de
#
# Notes       : Loads the floppy module based upon contents of the NVRAM
# 
########################################################################

PROC=/proc/driver/nvram

# wait for /proc file to appear
loop=10
while ! test -e $PROC; do
    sleep 0.1;
    test "$loop" -gt 0 || break
    loop=$(($loop - 1))
done

if [ ! -r /proc/driver/nvram ]; then
    exit 0;
fi

floppy_devices=$(cat $PROC | sed -n '/Floppy.*\..*/p')

if [ -n "$floppy_devices" ]; then
    /sbin/modprobe block-major-2-
else
    /bin/true
fi

exit $?

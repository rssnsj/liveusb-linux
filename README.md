# liveusb-linux
Ramdisk-based Linux Operating System for System Repair and Rescue Uses

### Boot the guest system

    # Boot in ramdisk mode
    ./vmlinuz-4.1.18-liveusb mem=256m initrd=ramdisk.img-4.1.18-liveusb root=/dev/ram0 eth0=tuntap,tap0

    # Boot with a pre-created disk image
    ./vmlinuz-4.1.18-liveusb mem=256m ubda=virtual-disk.img root=/dev/ubda1 eth0=tuntap,tap0

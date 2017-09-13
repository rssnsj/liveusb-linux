# liveusb-linux
Ramdisk-based Linux Operating System for System Repair and Rescue Uses

### UMLinux configuration and boot

Host settings for virtual networking

    # Install Ubuntu packages for tunctl, brctl
    sudo apt-get install uml-utilities bridge-utils
    
    # Create host-side TAP interface
    sudo tunctl -t tap0 -u rssnsj  # grant access to a regular user
    sudo ifconfig tap0 up
    sudo brctl addif br-wan tap0   # attach to a bridge if necessary

Boot guest system

    # Boot in ramdisk mode
    ./vmlinuz-4.1.18-liveusb mem=256m initrd=ramdisk.img-4.1.18-liveusb root=/dev/ram0 eth0=tuntap,tap0
    
    # Boot in ramdisk mode with an empty 1G virtual disk
    truncate virtual-disk.img -s 1G
    ./vmlinuz-4.1.18-liveusb mem=256m initrd=ramdisk.img-4.1.18-liveusb root=/dev/ram0 ubda=virtual-disk.img eth0=tuntap,tap0

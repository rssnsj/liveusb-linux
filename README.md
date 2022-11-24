# liveusb-linux
Ramdisk mode Linux operating system for system repair and rescue use

### How to build

Install prerequisites for compiling

    # Ubuntu:
    sudo apt-get install libncurses-dev bison flex libelf-dev elfutils
    
    # CentOS
    sudo yum install ncurses-devel bison flex elfutils-libelf-devel elfutils-devel

Compile and build

    make -j`nproc`


#!/bin/bash

build_bios() {
    # geniso only renames this kernel to ipxe.krn. Build it directly so this
    # component needs neither Syslinux nor a privileged ISO mount.
    make -j8 bin/ipxe.lkrn BIOS_MODE=BIOS || exit 1
    cp bin/ipxe.lkrn ../../../INSTALL/ventoy/ipxe.krn || exit 1

    echo -e "\n===============SUCCESS===============\n"
}


build_bios



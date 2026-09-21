# Couti USB package

This is a locally rebuilt **1.1.17 development package** for you to test. The
boot components are signed with a new **Couti Secure Boot** identity. Firmware
and operating-system boot tests have not been run, as requested.

## Create the USB on Windows

1. Extract the entire ZIP into a folder on your computer.
2. Run **Couti2Disk.exe** as administrator. Select the intended USB device.
3. Keep **Option → Secure Boot Support** enabled. For Windows VHD/VHDX use,
   select **NTFS** in the partition configuration before installing. The default
   MBR layout supports both legacy BIOS and UEFI.
4. Click **Install**. A fresh installation erases the selected USB device.
5. Copy the **contents** of `USB-FILES` into the large **Couti** partition.
   This creates the compatibility folder containing the VHD boot helper.
6. Copy your Windows and Linux ISO files, and your Windows 11 VHD/VHDX file,
   into the large partition. Subfolders such as `ISO` and `VHD` are fine.
7. Boot the USB using the computer's boot-device menu. Choose its **UEFI**
   entry when using Secure Boot.

## Folders and keyboard controls

The opening screen browses folders and supported boot images on the largest
readable data partition of the drive that started Couti. The boot partition
is excluded. The current installer creates the large data partition as
partition 1 and the small boot partition as partition 2; the browser detects
the actual boot partition instead of assuming either number. It does not
repartition existing drives.

Choose **[ .. ] Choose a different partition**, or press **F2**, to see the
available partitions and browse another drive. Inside a folder, use its first
entry or **Esc** to go back. An empty data partition still opens in Folders.
If no usable data partition can be selected on the boot drive, the opening
screen shows the partition chooser instead.

The bottom icon row uses these keyboard shortcuts, with text below each icon:

| Key | Menu |
| --- | --- |
| F1 | Help |
| F2 | Folders |
| F3 | Tools |
| F4 | LocalBoot |
| F5 | Power Menu |

Power provides Reboot, Shutdown and, on UEFI, firmware setup. **F6**, **F7**
and the **L** language shortcuts do nothing in the menu. Folders opens without
an automatic timeout.

The supplied `sample_slack` theme provides the transparent menu, artwork and
icons. Menu entries use **DejaVu Sans**, with the font bundled in GRUB format.
There is no separate title over the background and no website footer. See
`THEME-GUIDE.md` in the package for replacing icons and editing the layout.

Keep the package's `boot` and `ventoy` folders beside the installer. Copying
these folders onto an ordinary formatted USB is not an installation; the
installer creates the boot sectors and separate boot partition.

## Update an existing Couti USB

This package includes the Folders opening screen, DejaVu Sans menu font,
five-icon F1–F5 dock and Couti names throughout the boot partition's files
and folders. The boot volume is now labeled **COUTIEFI**. The version remains
**1.1.17**.

On Windows, extract this updated package, run its **Couti2Disk.exe**, select
your existing USB, and click **Update**. Updating replaces the boot components
and preserves files on the large data partition. Use the newly extracted
package even when the installed and package version numbers match.

Use **Update** for the rename migration: the BIOS core, EFI loaders, boot
scripts and helper archives must be replaced together. Renaming the old
files in Explorer, or copying only the new folder onto an old installation,
leaves the old loaders pointing at missing files. Back up any custom theme
edits on the small boot partition before updating.

On Linux, run `sudo sh Couti2Disk.sh -u -s /dev/sdX` from the updated package,
using the intended whole USB device. The signing identity is unchanged, so
an already enrolled Couti certificate does not need to be enrolled again.

## Enroll the Couti key for Secure Boot

Leave firmware Secure Boot enabled. Some machines also require the firmware
option **Microsoft third-party UEFI CA** to be enabled.

On the first boot, the signed third-party shim may show a verification failure
and open MOK Manager. Choose **Enroll key from disk**, select the small
**COUTIEFI** partition, and select **ENROLL_THIS_KEY_IN_MOKMANAGER.cer**. Confirm
that the identity is **Couti Secure Boot**, enroll it, and reboot. This is
normally needed once on each computer. The public certificate is also supplied
as `Couti-Secure-Boot.cer` beside this document.

Certificate SHA-256 fingerprint:

```text
99:2A:85:6D:75:EE:99:C5:22:F7:B7:69:DC:FF:D9:B4:1F:09:3C:91:B8:02:03:21:B7:E8:CF:A6:DA:BC:FF:63
```

The Microsoft-signed shim and MOK Manager are retained unchanged. Couti's
second-stage loader, GRUB, filesystem drivers, EFI helpers and WIM boot helpers
are signed with the Couti key. **The private signing key is not in this package.**

Secure Boot support here targets **x86-64 UEFI PCs**. IA32 uses the inherited
third-party chain and is untested; ARM64 and MIPS builds are not claimed to have
Secure Boot support. Firmware trust settings and revocation lists can still
reject a loader; this package is not a guarantee for every firmware version.

## Operating systems and Secure Boot policy

The rebuilt boot engine retains the Windows 7/8/8.1/10/11 ISO paths and Linux
hooks, including Debian, Ubuntu, Kali Linux, Manjaro and elementary OS. Their
compatibility is inherited from upstream and **has not been verified in this
build**. You supply the operating-system images.

The inherited default compatibility policy allows unsigned payloads after
starting the signed Couti chain. It permits booting a broader range of older
Windows and Linux images while Secure Boot remains enabled in firmware. It
**does not enforce signature verification for every booted payload**. Windows
7 does not gain native Secure Boot support; it also needs hardware and drivers
compatible with Windows 7, and some machines require legacy BIOS/CSM for it.

For strict payload signature checking, edit the provided
`USB-FILES/ventoy/ventoy.json` before copying it to the USB, changing
`VTOY_SECURE_BOOT_POLICY` from `0` to `1`. That restricts which images and boot
modes can run; unsigned Linux images and legacy Windows images may be rejected.

## Windows 11 from VHD/VHDX

The package includes the upstream **Win10Based v3.0** VHD helper under
`USB-FILES/ventoy/ventoy_vhdboot.img`. Keep that compatibility filename and copy
it to the USB as described above. It is a loader template, **not a Windows
installation**. The source release and its checksum are recorded in
`BUILD-INFO.json`.

Use an existing Windows installation prepared for native boot, preferably a
**VHDX** on the NTFS data partition, following Microsoft's
[native boot guidance](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/deploy-windows-on-a-vhd--native-boot?view=windows-11).
Copy the VHD/VHDX onto the USB and select it
from Couti's menu. UEFI VHD boot supports 64-bit Windows. A virtual-machine disk
is not automatically a portable native-boot installation; storage drivers and
the Windows configuration still matter.

The upstream helper contains Microsoft boot files. Use it with your licensed
Windows installation; no Windows ISO or installed Windows disk is included.

## Create the USB on Linux

Extract the Linux archive, change into its directory, and run:

```sh
sudo sh Couti2Disk.sh -i -s /dev/sdX
```

Replace `/dev/sdX` with the intended **whole USB device**, not a partition. A new
installation erases that device. The CLI initially creates an exFAT data
partition. For NTFS VHD storage, reformat only the large data partition as NTFS
before copying your files; preserve the small COUTIEFI partition. Copy the
contents of `USB-FILES` and your images onto the large partition afterward.

## Notes for testing

The small FAT boot partition uses `/couti/couti.cpio`, `couti_*.efi`,
`coutijump*.exe`, `coutiutil_*.efi` and Couti filenames for the theme's file-type
icons. The helper script is `/tool/create_couti_iso_part_dm.sh`. The existing
32 MB FAT16 filesystem and partition layout are preserved.

Internal identifiers inside binaries and initramfs archives, compatibility
files on the large data partition, host-side installer support filenames,
device names and legal attributions retain upstream names.
Couti's own boot menus and display messages have been rebranded.
An operating system, custom theme, filename, or diagnostic that displays raw
paths can still expose an internal name.

Upstream references: [supported systems](https://github.com/ventoy/Ventoy),
[Secure Boot](https://www.ventoy.net/en/doc_secure.html), and
[VHD boot](https://www.ventoy.net/en/plugin_vhdboot.html).

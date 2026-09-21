# Couti Installer

Extract the entire ZIP to your computer and run `Couti2Disk.exe` as administrator.
The application is x86 and is intended to run on Windows 10/11 with .NET Framework
4.x and the Windows Storage module. Keep the `boot` and `boot-files` folders beside it.

Select the intended physical drive. The installer displays its partitions and
whether Couti is present. The interface is English only; it has Install and Remove.

## Install without formatting (default)

Leave **Format drive** unchecked. Existing data partitions, files, and labels are
preserved. Couti uses a suitable unallocated extent first. Otherwise, it considers
the largest eligible NTFS partition, followed by other eligible partitions with
the most free space, all on the selected physical drive. Windows must be able to
shrink the selected partition's end sufficiently; files are not moved between drives.

The installer creates one **100 MiB FAT32** boot partition labeled **COUTI**.
Partition 2 is used when its slot is available after partition 1. Existing partitions
are not renumbered or moved to force that layout. Boot loaders locate the COUTI
partition in its actual slot. The boot menu opens the largest supported data
partition on the same drive. Use the back entry or F2: Folders to choose another.

Windows cannot shrink exFAT or FAT32 using this method. Encrypted volumes,
extended/dynamic MBR layouts, nonstandard GPT tables, and 4Kn logical sectors are
not supported by this installer. If suitable space cannot be obtained, installation
stops; it never switches to formatting automatically.

## Install with formatting

Tick **Format drive**, type **FORMAT**, then confirm the final prompt after clicking
Install. This erases all partitions and files on the selected physical drive.
The new layout is:

1. **Gabulhi**, NTFS, using the remaining usable space.
2. **COUTI**, FAT32, 100 MiB, containing the EFI and Couti boot files.

The original GPT/MBR style is retained where supported. Drives larger than 2 TiB
use GPT. There is a small alignment/boot-loader reserve outside the partitions.
100 MiB means 104,857,600 bytes, shown as 100 MB by many disk utilities.

### Correction for "The disk has already been initialized"

The corrected installer refreshes the disk state after clearing, retains an empty
MBR/GPT table of the required type, and calls Initialize-Disk only for a RAW disk.
It also accepts an already-empty drive left by the earlier failed formatting attempt.
An empty drive now shows "No partitions" and requires the explicit Format drive workflow.

Close the old installer and extract the corrected ZIP into a new folder. To create
a fresh blank installation on the affected USB, select that drive, tick Format drive,
type FORMAT, and click Install. This creates new filesystems; it is not file recovery.
If old files need to be recovered, do not format the drive again.

Errors now include the installation stage and the operation-log folder. The original
Windows error details are saved as `storage-error.txt`/`operation-error.txt`. A failed
format operation does not automatically restore the former partition layout.

## Existing installations and Remove

If Couti is present, Remove is available. Remove deletes only the identified boot
partition and restores the preceding BIOS bootstrap when this installer saved it.
For older installations without a backup, it clears the matching Couti bootstrap.
Data partitions and labels remain. The removed partition becomes unallocated space;
data partitions are not automatically expanded.

To replace a previous 32 MB installation without formatting, Remove it, then Install.
The old 32 MB space alone is insufficient for the new 100 MB partition. Additional
unallocated space or a shrinkable NTFS partition is required. An existing exFAT
drive without enough unallocated space cannot be migrated through this method.

Each operation saves device information, a first-MiB boot backup, and logs under
`%ProgramData%\Couti Installer\Sessions`. These are boot metadata backups, not file backups.

## Boot files and Secure Boot

Copy ISO/VHD files to the data partition. Windows and Linux boot paths, the supplied
theme, DejaVu Sans fonts, and the Windows VHD helper are included. Menu shortcuts:
F1 Help, F2 Folders, F3 Tools, F4 LocalBoot, F5 Power Menu. F6 and F7 are disabled.

The x64 UEFI boot chain includes signed Couti loaders and the existing Microsoft-signed
shim. Some computers require enrollment of `Couti-Secure-Boot.cer` through MOK Manager.
The compatibility payload policy is retained for the requested operating systems.
Firmware trust/revocation settings and the selected OS image still determine what
can boot; not every Windows/Linux image supports every firmware or Secure Boot mode.
Windows 7 support does not imply native Windows 7 Secure Boot support.

`couti-boot-files-100mb.zip` contains the files for an existing COUTI FAT32 boot
partition. Copying these files alone does not partition a drive or install its BIOS
bootstrap. Use the installer for a complete installation.

**No application, disk, OS boot, or Secure Boot tests were run for this build, as
requested. Compilation and packaging only.**

The new x86 installer is packaged separately from earlier Linux/legacy installer
archives, whose disk-layout behavior has not been changed by this release.

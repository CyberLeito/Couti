# Couti build, branding and signing

## Current deliverables

The latest Windows application is `artifacts/couti-installer-x86.zip`, with
`artifacts/couti-boot-files-100mb.zip` for its matching boot filesystem. Read
[Couti Installer usage](CoutiInstaller.md). It creates one 100 MiB FAT32 COUTI
partition, defaults to preserving data, and requires typed FORMAT before its
destructive Gabulhi/NTFS plus COUTI layout. Its English x86 frontend uses the
supplied `ICON/Couti_icon.ico`. Compilation and packaging were completed;
application, disk and boot tests were not run.

The packages below are earlier releases using the legacy installer/layout.

`artifacts/couti-1.1.17-windows.zip` and `artifacts/couti-1.1.17-linux.tar.gz`
contain USB installation packages with the rebuilt Couti installer, Windows
VHD helper, public Couti certificate and setup instructions.

Read [USB setup and Secure Boot enrollment](USB-START-HERE.md) before use. These
are development builds: **firmware and OS boot tests were not run**. The user
requested to perform testing personally. Source audits and nine unit checks
were run before that instruction; later signing and packaging did not run
tests. The optional branding workflow requires manual dispatch.

## Rebuilt components

- GRUB: BIOS, IA32, x86-64, ARM64 and MIPS64EL.
- EDK2 applications: IA32, x86-64 and ARM64; x86-64 shim adapter.
- iPXE BIOS helper and VtoyTool for all four architectures.
- Windows 32-bit/64-bit boot helpers and Windows installer.
- Linux initramfs and BSD payload archives. Linux WebUI servers were also
  compiled; unrelated desktop GUI programs are omitted from the CLI package.

The historical BSD modules were not rebuilt against every old kernel ABI.
Only reviewed, fixed-length diagnostic strings in ELF read-only sections were
localized. The DragonFly image received the same diagnostic changes. Code,
relocations and filesystem offsets were preserved. The manifest
`tools/build/legacy-bsd-branding.json` records offsets and before/after hashes;
`tools/build/brand-legacy-bsd.py` documents the transformation. Native BSD
rebuilds and native OS testing remain separate work.

## Build environment

Windows helper builds use Visual Studio desktop C++ tools and a Windows SDK.
Run `tools/build/build-windows.ps1` to compile the native helpers into
`.build/windows` and the new .NET Framework x86 frontend into `INSTALL/Couti2Disk.exe`.
`tools/build/build-installer.ps1` builds only the frontend, embedding its storage
service, administrator manifest and the supplied ICO file.

Package the new installer using `tools/build/package-windows-installer.py` with
the signed stage (including `bootfs`, `boot/boot.img` and `boot/core.img.xz`) and
the existing VHD helper. `make-image.sh STAGE 100` assembles its intermediate
100 MiB FAT32 image; it accepts only file-backed images in the build container.
The legacy `package-installers.py` requires the legacy native executable from
`.build/windows/installer/Ventoy2Disk.exe`; do not give it the new frontend.

Linux builds use `couti-builder:centos7`, built from `tools/build/Dockerfile`.
Historical GCC versions match the upstream patches. Downloads are cached in
`couti-downloads`, compilers in `couti-toolchains`, and disposable build output
in `couti-build-work`. Container `couti-build` mounts this checkout read-only at
`/source` and builds under `/build/Couti`. Containers are stopped after packaging;
start the relevant container again for a later build.

A fresh build sequence using `tools/build` is:

1. Run `prepare.sh` in the build container. Normalize its CRLF first when read
   directly from a Windows checkout; it normalizes the disposable source copy.
2. Run `compile-grub.sh x86_64-efi i386-efi arm64-efi mips64el-efi i386-pc`.
   Save the resulting `GRUB2/INSTALL` as `/build/grub-bios-tools` for packaging.
3. Run `compile-edk.sh x64 ia32 aa64 shim`, `IPXE/buildipxe.sh`,
   `DOC/installdietlibc.sh` and `VtoyTool/build.sh` from their working directories,
   with the downloaded compiler directories on PATH.
4. Run `IMG/mkcpio.sh`, `IMG/mkloopex.sh` and `Unix/pack_unix.sh` from their
   directories. Copy the newly compiled Windows helpers into INSTALL.
   Run `tools/build/make-menu-fonts.sh` to build the DejaVu Sans PF2 fonts
   and copy their embedded license into the release inputs.
5. Run `stage-release.py --secure-boot /build/couti-stage-NEW`.
6. Run `sign-release.py /build/couti-stage-NEW` in container `couti-sign`.
7. Run `make-image.sh /build/couti-stage-NEW` in dedicated privileged container
   `couti-package`. It allocates its own file-backed loop device. Never pass a
   physical disk. This makes installer payloads; its small intermediate image
   is not a full-size USB data disk for storing Windows images.
8. Run `package-installers.py` with the staged payloads, Windows executable,
   and downloaded Win10Based VHD helper. Its `--help` lists the path arguments.

The original reference remains [BuildVentoyFromSource.txt](BuildVentoyFromSource.txt).

## Secure Boot identity

The unmodified Microsoft-signed first-stage shim and MOK Manager have no Ventoy
 display branding. The x86-64 adapter retains the exact function offsets for
that bundled shim. Do not replace the shim independently without updating its
adapter. The adapter SBAT identity is Couti.

The signer replaces old helper signatures with the **Couti Secure Boot**
identity. It signs GRUB first, embeds that exact signed GRUB hash in the rebuilt
shim adapter, then signs the adapter. Enrollment uses the new Couti DER file.

The private key lives in Docker volume `couti-signing`, with an ignored backup
under `.build/signing`. Retain it for future updates to preserve the enrolled
identity. Never add the private key to Git or a release archive. Only the public
certificate is shipped. Source-tree EFI files are unsigned build outputs; the
packaged partition contains signed release copies.

The default compatibility policy permits older and unsigned payloads with
firmware Secure Boot enabled. It bypasses payload signature enforcement after
the signed Couti chain starts. Strict policy is optional and restricts supported
images. This does not make Windows 7 natively Secure Boot-validated or guarantee
acceptance on every firmware. See the USB instructions for limitations.

## Branding scope and optional checks

Couti supplies its own theme, menu headers, translations, help, diagnostics,
initramfs messages, EFI messages, Windows installer icon and volume labels.
Copyright notices and third-party licenses remain.

The default theme in `INSTALL/grub/themes/couti` adapts the supplied
`sample_slack.zip`: background, transparent menu, terminal frame, scrollbar,
selection artwork and icons. Its `title-text` is empty so GRUB does not overlay
a second Couti title on the artwork. Unused file-manager dock entries and
upstream brand icons are not imported.

The default menu uses DejaVu Sans at 18 pixels, with 16-pixel labels below the
five shortcut icons and a 14-pixel status footer. The font converter uses the
builder's `dejavu-sans-fonts` package and retains the embedded font license.
The icons are ordinary PNG files referenced by the theme; they are not baked
into the EFI binaries. See [theme customization](CoutiTheme.md).

`vt_browser_home` builds the main menu from the largest usable partition on
the boot drive, excluding the boot partition resolved from GRUB's prefix.
Partition names come from GRUB's partition map, including GPT and MBR. Folders
are browsed directly, including on the usual image partition; the former
shortcut to the prebuilt image tree is removed. A root entry opens the
partition chooser, and nested menus retain their Back/Esc entries. The image
index remains available to the existing boot helpers.

The shortcuts are F1 Help, F2 Folders, F3 Tools, F4 LocalBoot and F5 Power Menu.
Power remains available even inside the F2 browser. F6, F7 and language
shortcuts are disabled. Shortcut labels and help reflect the new actions.
All five GRUB targets and signed USB packages were
rebuilt for these menu changes; no tests were run.

The graphical footer is generated in GRUB's `ventoy_fill_data`, separately
from the theme file. It now displays only the version and firmware mode.
The internal GUID formerly appended to that label is still used by the
compatibility protocol, but is no longer rendered as a website address.
All five GRUB targets and the signed USB packages were rebuilt for this fix;
no tests were run.

Internal paths such as `/ventoy/ventoy.json`, device mapper names, EFI variables
and `VENTOY COMPATIBLE` magic remain OS/plugin interfaces. A booted OS, custom
configuration, filename or diagnostic printing a raw path can expose these
names. User-supplied operating systems have not been modified.

The physical FAT boot filesystem uses a separate Couti namespace:
`/couti/couti.cpio`, `/couti/couti_<arch>.efi`, `coutijump*.exe`,
`coutiutil_*.efi`, Couti theme icon names, and
`/tool/create_couti_iso_part_dm.sh`. Its volume label is `COUTIEFI`.
`tools/build/couti-boot-layout.py` converts source build output filenames at
staging time; GRUB, EDK2, WinPE and the Linux hook that opens the boot partition
use the corresponding paths. Internal archive member paths remain compatible
with the injected OS hooks. Installer detection accepts both the old and new
partition names, while new installations use `COUTIEFI`.

For an existing USB, use the rebuilt installer's Update operation. It replaces
the BIOS core and the complete boot partition together, preserving the large
data partition. The Secure Boot signing identity is unchanged.

Checks are available **when the user requests testing**:

```sh
python3 tools/check_boot_branding.py
python3 -m unittest discover -s tools/tests
python3 tools/check_boot_branding.py --artifacts /path/to/assembled/bootfs
```

The audit covers known strings, nested XZ/gzip/newc payloads and certificate
identities; it does not prove the absence of every possible screen message.
`smoke-boot.py` is an optional QEMU capture helper and was not run. No final-image
boot verification is claimed.

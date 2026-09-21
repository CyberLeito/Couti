# Couti

Couti is a multiboot USB tool for ISO, WIM, IMG, VHD(x), and EFI images. Copy
images to the data partition and select them from the Couti boot menu.

The source includes BIOS and IA32/x86_64/ARM64/MIPS64EL UEFI boot support.

## Building this fork

The redesigned Windows x86 application is **Couti Installer**, in
`artifacts/couti-installer-x86.zip`. See [Couti Installer usage](DOC/CoutiInstaller.md)
for the single 100 MiB FAT32 COUTI boot partition, default installation without
formatting, and the explicit FORMAT workflow for Gabulhi (NTFS) plus COUTI.
Its matching boot-file archive is `artifacts/couti-boot-files-100mb.zip`.
Earlier Windows/Linux archives use the preceding installer and layout.

The boot components and Windows installer have been rebuilt for Couti. Local
Windows and Linux USB installation packages are in `artifacts/`; see
[USB setup and Secure Boot enrollment](DOC/USB-START-HERE.md).
They include the Windows VHD helper and a public Couti enrollment certificate.
Firmware and OS boot tests have not been run, at the user's request.

Read [build status, signing and compatibility notes](DOC/CoutiBranding.md)
before distributing an image. The source-tree EFI files are unsigned build
outputs; the packaged boot partition contains their signed release copies.

Optional checks (run only when requested):

```sh
python3 tools/check_boot_branding.py
python3 -m unittest discover -s tools/tests
```

The original toolchain setup is documented in
[the build instructions](DOC/BuildVentoyFromSource.txt).

## Compatibility and credits

Couti is a fork of [Ventoy](https://github.com/ventoy/Ventoy). Original copyright
notices, license files, and internal compatibility interfaces are retained.
Existing plugin configuration paths and installer filenames remain supported;
they are documented in the [branding notes](DOC/CoutiBranding.md).

See [COPYING](COPYING) and [License](License) for the applicable licenses.

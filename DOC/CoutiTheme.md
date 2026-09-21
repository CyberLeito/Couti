# Couti theme customization

The source theme is `INSTALL/grub/themes/couti/theme.txt`. On an installed USB,
it is `/grub/themes/couti/theme.txt` on the small boot partition. The background,
menu decorations and shortcut icons live beside this file. Editing these
assets does not require rebuilding or signing the boot loaders. Reboot to load
the changes, or rebuild the installer package to distribute them.

## Bottom shortcut icons

Each shortcut uses a separate `image` component and a centered `label` below
it. The PNG files are relative to the theme directory:

| Label | PNG file | Source in the supplied sample_slack archive |
| --- | --- | --- |
| F1: Help | `shortcuts/help.png` | `icons/info.png` |
| F2: Folders | `shortcuts/folders.png` | `icons/dir.png` |
| F3: Tools | `shortcuts/tools.png` | `icons/settings.png` |
| F4: LocalBoot | `shortcuts/localboot.png` | `icons/hdd.png` |
| F5: Power Menu | `shortcuts/power.png` | `icons/halt.png` |

Replace a PNG with the same filename to change an icon. PNGs with transparent
backgrounds work well. GRUB scales them to the 48-by-48-pixel image bounds in
`theme.txt`; edit those bounds to change the displayed size. Change `file` to
use a different filename, and edit the adjacent label's `text`, `font`, `color`
and `align` properties to restyle its caption. Keep each label beneath its
corresponding image when moving the components.

These are keyboard shortcut indicators. Changing an icon or caption does not
change its key binding. The actions are configured in `grub.cfg` and GRUB's
menu handler. F6, F7 and the language shortcut are disabled.

File and folder entries use separate icons in `icons/`. In the installed boot
theme these are `coutidir.png`, `coutidisk.png`, `coutiefi.png`, `coutiimg.png`,
`coutiiso.png`, `coutiret.png`, `coutivhd.png`, `couticouti.png` and
`coutiwim.png`. The packer maps source icon names to these Couti filenames.

## DejaVu Sans

The package loads `dejavusans-14.pf2`, `dejavusans-16.pf2` and
`dejavusans-18.pf2` from `/grub/fonts` before loading the theme. The menu uses
`DejaVu Sans Regular 18`, and dock captions use `DejaVu Sans Regular 16`.
The boot loader's generated version/mode footer uses the 14-pixel font.
The original Unicode font remains loaded for fallback glyphs.

Menu font properties are `item_font` and `selected_item_font`; labels use
`font`. Set these to a loaded font's full GRUB name. To generate the bundled
fonts again, run `tools/build/make-menu-fonts.sh` in the configured build
container. This uses the installed DejaVu Sans TTF and `grub-mkfont`, and
copies the font's embedded license to `License/DejaVuSans.txt` and the boot
font directory. It does not run tests.

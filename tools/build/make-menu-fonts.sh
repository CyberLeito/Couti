#!/bin/bash
# Convert the builder's DejaVu Sans into GRUB PF2 files; no tests are run.
set -euo pipefail
root=/build/Couti
font=${COUTI_MENU_TTF:-/usr/share/fonts/dejavu/DejaVuSans.ttf}
mkfont=${COUTI_MKFONT:-/build/grub-bios-tools/bin/grub-mkfont}
mkdir -p "$root/INSTALL/grub/fonts" "$root/License"
for size in 14 16 18; do
    "$mkfont" --size="$size" --output="$root/INSTALL/grub/fonts/dejavusans-$size.pf2" "$font"
    echo "Built DejaVu Sans Regular $size"
done

# Preserve the complete license embedded in the source font (name ID 13).
python3 - "$font" "$root" <<'PY'
from pathlib import Path
import struct
import sys

data = Path(sys.argv[1]).read_bytes()
tables = [struct.unpack_from('>4sIII', data, 12 + 16 * i)
          for i in range(struct.unpack_from('>H', data, 4)[0])]
offset = next(table[2] for table in tables if table[0] == b'name')
_, count, strings = struct.unpack_from('>HHH', data, offset)
records = [struct.unpack_from('>HHHHHH', data, offset + 6 + 12 * i)
           for i in range(count)]
record = next(r for r in records if r[0] == 3 and r[2] == 1033 and r[3] == 13)
start = offset + strings + record[5]
license_text = data[start:start + record[4]].decode('utf-16-be') + '\n'
root = Path(sys.argv[2])
for name in ('License/DejaVuSans.txt', 'INSTALL/grub/fonts/LICENSE-DejaVuSans.txt'):
    (root / name).write_text(license_text, encoding='utf-8')
PY

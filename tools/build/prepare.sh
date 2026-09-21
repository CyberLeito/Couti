#!/bin/bash
set -euo pipefail

# /source is read-only; generated code and downloaded toolchains stay in volumes.
mkdir -p /build/Couti /downloads
rsync -a --exclude=.git --exclude=.build --exclude=artifacts /source/ /build/Couti/
cd /build/Couti

# A Windows checkout has CRLF scripts. Normalize only the disposable build copy.
python3 - <<'PY'
from pathlib import Path
suffixes = {'.sh', '.c', '.h', '.S', '.cfg', '.inf', '.dsc', '.dec', '.py', '.txt'}
for path in Path('.').rglob('*'):
    if path.is_file() and (path.suffix in suffixes or path.name.startswith('Makefile')):
        data = path.read_bytes()
        if b'\0' not in data and b'\r\n' in data:
            path.write_bytes(data.replace(b'\r\n', b'\n'))
PY

download() {
    local name=$1 url=$2
    if [ ! -s "/downloads/$name" ]; then
        curl --fail --location --retry 4 --connect-timeout 30 "$url" -o "/downloads/$name.part"
        mv "/downloads/$name.part" "/downloads/$name"
    fi
}

base=https://github.com/ventoy/vtoytoolchain/releases/download/1.0
download grub-2.04.tar.xz "$base/grub-2.04.tar.xz"
download edk2-stable201911.zip https://codeload.github.com/tianocore/edk2/zip/edk2-stable201911
download gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz "$base/gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz"
download mips-loongson-gcc7.3-2019.06-29-linux-gnu.tar.gz "$base/mips-loongson-gcc7.3-2019.06-29-linux-gnu.tar.gz"
download aarch64--uclibc--stable-2020.08-1.tar.bz2 "$base/aarch64--uclibc--stable-2020.08-1.tar.bz2"
download dietlibc-0.34.tar.xz "$base/dietlibc-0.34.tar.xz"
download output.tar.bz2 https://github.com/ventoy/musl-cross-make/releases/download/latest/output.tar.bz2

cp /downloads/grub-2.04.tar.xz GRUB2/
cp /downloads/edk2-stable201911.zip EDK2/edk2-edk2-stable201911.zip
cp /downloads/dietlibc-0.34.tar.xz DOC/
for archive in gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu.tar.xz \
               mips-loongson-gcc7.3-2019.06-29-linux-gnu.tar.gz \
               aarch64--uclibc--stable-2020.08-1.tar.bz2; do
    tar -xf "/downloads/$archive" -C /opt
done
if [ ! -d /opt/mips64el-linux-musl-gcc730 ]; then
    tar -xf /downloads/output.tar.bz2 -C /opt
    mv /opt/output /opt/mips64el-linux-musl-gcc730
fi
sha256sum /downloads/* > /build/downloads.sha256
echo 'Couti build sources and cross compilers are ready.'

# The upstream GRUB/EDK2 patches target GCC 4.8 and CentOS 7.
FROM centos:7
RUN sed -i -e 's/^mirrorlist/#mirrorlist/' -e 's/^#baseurl/baseurl/' \
    -e 's|http://mirror.centos.org|https://vault.centos.org|' /etc/yum.repos.d/*.repo \
    && yum -y install ca-certificates curl wget git gcc gcc-c++ make \
        glibc-devel glibc-devel.i686 glibc-static glibc-static.i686 libstdc++-devel libstdc++-devel.i686 \
       autoconf automake autogen libtool gettext-devel bison flex patch \
       python python3 nasm acpica-tools binutils freetype-devel dejavu-sans-fonts \
       bzip2 xz gzip tar unzip zip dos2unix rsync which file \
       zlib-devel zlib-devel.i686 zlib-static xz-devel \
       cpio dosfstools util-linux e2fsprogs xorriso squashfs-tools \
       gtk3-devel gtk2-devel libglade2-devel openssl openssl-devel \
    && yum clean all
WORKDIR /build/Couti

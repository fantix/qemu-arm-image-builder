#!/bin/sh

SUITE=buster # buster or bullseye or sid
ARCH=amd64 # ppc64el or ppc64 or powerpc or arm64 or armhf or armel or amd64 or i386
IMGFILE=debian-${SUITE}-${ARCH}.img
GIGABYTES=40 # total size in GB
SWAPGB=0 # swap size in GB
ROOTFS=ext4 # btrfs or ext4
MMVARIANT=apt # apt or required, important, or standard
NETWORK=systemd-networkd # systemd-networkd or ifupdown, network-manager, none
YOURHOSTNAME=debian-buster
KERNEL_CMDLINE='net.ifnames=0 consoleblank=0 rw'
MIRROR=
INITUDEVPKG=systemd-sysv,udev # or sysvinit-core,udev
KEYRINGPKG=debian-archive-keyring

apt-get -q -y --no-install-recommends install binfmt-support qemu-user-static qemu-efi-arm qemu-efi-aarch64 mmdebstrap qemu-system-arm ipxe-qemu qemu-system-ppc qemu-system-data qemu-utils parted

MOUNTPT=/tmp/mnt$$
LOOPDEV=`losetup -f`
if [ -z "${LOOPDEV}" -o ! -e "${LOOPDEV}" ]; then
  echo "losetup -f failed to find an unused loop device, exiting ..."
  echo "Consider rmmod -f loop; modprobe loop"
  exit 1
fi

. ./common-part.sh
. ./common-part2.sh

umount -f ${MOUNTPT}
rm -rf ${MOUNTPT}
losetup -d ${LOOPDEV}

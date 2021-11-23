#!/bin/sh

if [ ${ROOTFS} = btrfs ]; then
  if [ $ARCH = ppc64 -o $ARCH = ppc64el ]; then
    echo "Due to the different page size 65536 of 64-bit PowerPC, ROOTFS is changed to ext4"
    unset ROOTFS
    ROOTFS=ext4
  fi
fi

umount -qf ${LOOPDEV}p1
losetup -d ${LOOPDEV}
rm -f ${IMGFILE}
#dd if=/dev/zero of=${IMGFILE} count=1 seek=`expr ${GIGABYTES} \* 1024 \* 2048`
qemu-img create -f raw -o preallocation=off -o nocow=off ${IMGFILE} ${GIGABYTES}G
losetup -P ${LOOPDEV} ${IMGFILE}
if [ "$SWAPGB" -gt 0 ]; then
  parted -- ${LOOPDEV} mklabel gpt mkpart ROOT ${ROOTFS} '0%' -${SWAPGB}GiB
else 
  parted -- ${LOOPDEV} mklabel gpt mkpart ROOT ${ROOTFS} '0%' '100%'
fi

if [ ${SWAPGB} -gt 0 ]; then
    parted -- ${LOOPDEV} mkpart SWAP linux-swap -${SWAPGB}GiB 100%
fi

while [ ! -b ${LOOPDEV}p1 ]; do
    partprobe ${LOOPDEV}
    sleep 1
done

eval mkfs.${ROOTFS} -L ROOT ${LOOPDEV}p1
if [ ${SWAPGB} -gt 0 ]; then
    mkswap -L SWAP ${LOOPDEV}p2
fi

mkdir -p ${MOUNTPT}
if [ ${ROOTFS} = btrfs ]; then
    mount -t ${ROOTFS} -o  ssd,async,lazytime,discard,noatime,autodefrag,nobarrier,commit=3600,compress-force=lzo ${LOOPDEV}p1 ${MOUNTPT}
elif [ ${ROOTFS} = ext4 ]; then
    mount -t ${ROOTFS} -o async,lazytime,discard,noatime,nobarrier,commit=3600,delalloc,noauto_da_alloc,data=writeback ${LOOPDEV}p1 ${MOUNTPT}
else
    echo "Unsupported filesystem type ${ROOTFS}"
    exit 1
fi

if [ "${ARCH}" = arm64 ]; then
    KERNELPKG=linux-image-arm64
elif [ "${ARCH}" = armhf -o  "${ARCH}" = armel ]; then
    KERNELPKG=linux-image-armmp-lpae:armhf
elif [ "${ARCH}" = amd64 ]; then
    KERNELPKG=linux-image-amd64
elif [ "${ARCH}" = i386 ]; then
    KERNELPKG=linux-image-686-pae
elif [ "${ARCH}" = ppc64el ]; then
    KERNELPKG=linux-image-powerpc64le
elif [ "${ARCH}" = ppc64 ]; then
    KERNELPKG=linux-image-powerpc64
    apt-get -q -y install debian-ports-archive-keyring
    KEYRINGPKG=debian-ports-archive-keyring,$KEYRINGPKG
    MIRROR=-
    MMCOMPONENTS=main
elif [ "${ARCH}" = powerpc ]; then
    KERNELPKG=linux-image-powerpc-smp
    apt-get -q -y install debian-ports-archive-keyring
    KEYRINGPKG=debian-ports-archive-keyring,$KEYRINGPKG
    MIRROR=-
    MMCOMPONENTS=main
#elif [ "${ARCH}" = sparc64 ]; then
#    KERNELPKG=linux-image-sparc64
else
  echo "Unknown supported architecture ${ARCH} !"
  exit 1
fi

if [ -z "$MMCOMPONENTS" ]; then
  MMCOMPONENTS="main contrib non-free"
fi

if [ ${ARCH} = armel ]; then
    MMARCH=armel,armhf
else
    MMARCH=${ARCH}
fi

if [ $NETWORK = ifupdown ]; then
    NETPKG=ifupdown,isc-dhcp-client
elif [ $NETWORK = network-manager ]; then
    NETPKG=network-manager
elif [ $NETWORK = systemd-networkd ]; then
    NETPKG=systemd
else
    NETPKG=iproute2
fi

set -x
if [ $ARCH != ppc64 -a $ARCH != powerpc ]; then
  mmdebstrap --architectures=$MMARCH --variant=$MMVARIANT --components="$MMCOMPONENTS" --include=${KEYRINGPKG},${INITUDEVPKG},${KERNELPKG},${NETPKG},initramfs-tools,kmod,e2fsprogs,btrfs-progs,locales,tzdata,apt-utils,whiptail,debconf-i18n,keyboard-configuration,console-setup,net-tools ${SUITE} ${MOUNTPT} ${MIRROR}
else
  mmdebstrap --architectures=$MMARCH --variant=$MMVARIANT --components="$MMCOMPONENTS" --include=${KEYRINGPKG},${INITUDEVPKG},${KERNELPKG},${NETPKG},initramfs-tools,kmod,e2fsprogs,btrfs-progs,locales,tzdata,apt-utils,whiptail,debconf-i18n,keyboard-configuration,console-setup ${SUITE} ${MOUNTPT} ${MIRROR} <<EOF
deb http://deb.debian.org/debian-ports sid main
deb http://deb.debian.org/debian-ports unreleased main
EOF
fi

chroot ${MOUNTPT} dpkg-reconfigure locales
chroot ${MOUNTPT} dpkg-reconfigure tzdata
chroot ${MOUNTPT} dpkg-reconfigure keyboard-configuration
chroot ${MOUNTPT} passwd root
#chroot ${MOUNTPT} pam-auth-update
set +x

#touch ${MOUNTPT}${LOOPDEV}
#mount --bind ${LOOPDEV} ${MOUNTPT}${LOOPDEV}
mount --bind /dev ${MOUNTPT}/dev
mount --bind /dev/pts ${MOUNTPT}/dev/pts
mount --bind /sys ${MOUNTPT}/sys
mount --bind /proc ${MOUNTPT}/proc

chroot ${MOUNTPT} apt-get -qq update
chroot ${MOUNTPT} apt-get -qq -y --autoremove --no-show-progress purge os-prober
# --force-extra-removable is necessary below!

umount -f ${MOUNTPT}/dev/pts
umount -f ${MOUNTPT}/dev
#umount -f ${MOUNTPT}${LOOPDEV}
#rm -f ${MOUNTPT}${LOOPDEV}
umount -f ${MOUNTPT}/sys
umount -f ${MOUNTPT}/proc

echo ${YOURHOSTNAME} >${MOUNTPT}/etc/hostname
echo "127.0.1.1\t${YOURHOSTNAME}" >> ${MOUNTPT}/etc/hosts
if [ ${ROOTFS} = btrfs ]; then
   cat >${MOUNTPT}/etc/fstab <<EOF
LABEL=ROOT / ${ROOTFS} rw,ssd,async,lazytime,discard=async,strictatime,autodefrag,nobarrier,commit=3600,compress-force=lzo 0 1
EOF
elif [ ${ROOTFS} = ext4 ]; then
   cat >${MOUNTPT}/etc/fstab <<EOF
LABEL=ROOT / ${ROOTFS} rw,async,lazytime,discard,strictatime,nobarrier,commit=3600 0 1
EOF
else
    echo "Unsupported filesystem $ROOTFS"
    exit 0
fi

if [ "$SWAPGB" -gt 0 ]; then
  echo 'LABEL=SWAP none swap sw,discard 0 0' >>${MOUNTPT}/etc/fstab
fi

if [ $NETWORK != none ]; then 
  echo "IPv4 DHCP is assumed."
  NETIF=enp0s1

  if [ $NETWORK = ifupdown ]; then
    NETCONFIG="Network configurations can be changed by /etc/network/interfaces"
    cat >>${MOUNTPT}/etc/network/interfaces <<EOF
auto $NETIF
iface $NETIF inet dhcp
EOF
    echo "/etc/network/interfaces is"
    cat ${MOUNTPT}/etc/network/interfaces
  elif [ $NETWORK = network-manager ]; then
    NETCONFIG="Network configurations can be changed by nmtui"
  elif [ $NETWORK = systemd-networkd ]; then
    NETCONFIG="Network configurations can be changed by /etc/systemd/network/${NETIF}.network"
    cat >${MOUNTPT}/etc/systemd/network/${NETIF}.network <<EOF
[Match]
Name=${NETIF}

[Network]
DHCP=yes
EOF
    chroot ${MOUNTPT} systemctl enable systemd-networkd
  fi
fi

set -x
if [ "$SUITE" != buster -a "$SUITE" != beowulf ]; then
  chroot ${MOUNTPT} apt-get -qq -y --purge --autoremove purge python2.7-minimal
fi
if [ $NETWORK = network-manager -o $NETWORK = systemd-networkd ]; then
  chroot ${MOUNTPT} apt-get -qq -y --purge --autoremove purge ifupdown
  rm -f ${MOUNTPT}/etc/network/interfaces
fi  
set +x

if echo "$INITUDEVPKG" | grep -q sysvinit-core; then
  egrep -v 'ttyS0|hvc0|ttyAMA0|powerfail|ctrlaltdel' ${MOUNTPT}/etc/inittab >${MOUNTPT}/etc/inittab.new
  cat >>${MOUNTPT}/etc/inittab.new <<EOF
S0:2345:respawn:/sbin/agetty -8 --noclear --noissue ttyS0 115200 vt100
AMA0:2345:respawn:/sbin/agetty -8 --noclear --noissue ttyAMA0 115200 vt100
hvc0:2345:respawn:/sbin/agetty -8 --noclear --noissue hvc0 115200 vt100
ca:12345:ctrlaltdel:/sbin/shutdown -r now
pf::powerwait:/sbin/shutdown -h -P +1 "Power supply lost!! Waiting the power for 1 minute."
pn::powerfailnow:/sbin/shutdown -h -P now "Power supply lost!!"
po::powerokwait:/sbin/shutdown -c "Power supply recovered."
EOF
  mv ${MOUNTPT}/etc/inittab.new ${MOUNTPT}/etc/inittab
fi

#!/bin/bash -e
#
# Copyright (c) 2009-2011 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

#Notes: need to check for: parted, fdisk, wget, mkfs.*, mkimage, md5sum

unset MMC
unset FIRMWARE
unset SERIAL_MODE
unset BETA_BOOT
unset BETA_KERNEL
unset EXPERIMENTAL_KERNEL
unset USB_ROOTFS
unset PRINTK
unset HASMLO
unset ABI_VER
unset SMSC95XX_MOREMEM
unset DO_UBOOT_DD
unset KERNEL_DEB

SCRIPT_VERSION="1.11"
IN_VALID_UBOOT=1

MIRROR="http://rcn-ee.net/deb/"

#Defaults
RFS=ext4
DIST=f13

BOOT_LABEL=boot
RFS_LABEL=rootfs
PARTITION_PREFIX=""

FEDORA_MIRROR="http://scotland.proximity.on.ca/fedora-arm/rootfs/"

F13_IMAGE="rootfs-f13-beta3-2011-05-10.tar.bz2"
F13_MD5SUM="d4f68c5fcdfa47079a7baf099daa3ba3"

DIR=$PWD
TEMPDIR=$(mktemp -d)

#Software Qwerks
#fdisk 2.18.x/2.19.x, dos no longer default
unset FDISK_DOS

if test $(sudo fdisk -v | grep -o -E '2\.[0-9]+' | cut -d'.' -f2) -ge 18 ; then
 FDISK_DOS="-c=dos -u=cylinders"
fi

#Check for gnu-fdisk
#FIXME: GNU Fdisk seems to halt at "Using /dev/xx" when trying to script it..
if sudo fdisk -v | grep "GNU Fdisk" >/dev/null ; then
 echo "Sorry, this script currently doesn't work with GNU Fdisk"
 exit
fi

unset PARTED_ALIGN
if sudo parted -v | grep parted | grep 2.[1-3] >/dev/null ; then
 PARTED_ALIGN="--align cylinder"
fi

function detect_software {

echo "This script needs:"
echo "Ubuntu/Debian: sudo apt-get install uboot-mkimage wget dosfstools parted"
echo "Fedora: as root: yum install uboot-tools wget dosfstools parted dpkg patch"
echo "Gentoo: emerge u-boot-tools wget dosfstools parted dpkg"
echo ""

unset NEEDS_PACKAGE

if [ ! $(which mkimage) ];then
 echo "Missing uboot-mkimage"
 NEEDS_PACKAGE=1
fi

if [ ! $(which wget) ];then
 echo "Missing wget"
 NEEDS_PACKAGE=1
fi

if [ ! $(sudo which mkfs.vfat) ];then
 echo "Missing mkfs.vfat"
 NEEDS_PACKAGE=1
fi

if [ ! $(sudo which parted) ];then
 echo "Missing parted"
 NEEDS_PACKAGE=1
fi

if [ ! $(which dpkg) ];then
 echo "Missing dpkg"
 NEEDS_PACKAGE=1
fi

if [ ! $(which patch) ];then
 echo "Missing patch"
 NEEDS_PACKAGE=1
fi

if [ "${NEEDS_PACKAGE}" ];then
 echo ""
 echo "Your System is Missing some dependencies"
 echo ""
 exit
fi

}

function boot_files_template {

mkdir -p ${TEMPDIR}/

cat > ${TEMPDIR}/boot.cmd <<boot_cmd
setenv dvimode VIDEO_TIMING
setenv vram 12MB
setenv bootcmd 'fatload mmc 0:1 UIMAGE_ADDR uImage; bootm UIMAGE_ADDR'
setenv bootargs console=SERIAL_CONSOLE VIDEO_CONSOLE root=/dev/mmcblk0p2 rootwait ro VIDEO_RAM VIDEO_DEVICE:VIDEO_MODE fixrtc buddy=\${buddy} mpurate=\${mpurate}
boot
boot_cmd

cat > ${TEMPDIR}/uEnv.cmd <<uenv_boot_cmd
bootenv=boot.scr
loaduimage=fatload mmc \${mmcdev} \${loadaddr} \${bootenv}
mmcboot=echo Running boot.scr script from mmc ...; source \${loadaddr}
uenv_boot_cmd

}

function set_defaults {

 #Set uImage boot address
 sed -i -e 's:UIMAGE_ADDR:'$UIMAGE_ADDR':g' ${TEMPDIR}/boot.cmd

 #Set uInitrd boot address
 sed -i -e 's:UINITRD_ADDR:'$UINITRD_ADDR':g' ${TEMPDIR}/boot.cmd

 #Set the Serial Console
 sed -i -e 's:SERIAL_CONSOLE:'$SERIAL_CONSOLE':g' ${TEMPDIR}/boot.cmd

if [ "$SERIAL_MODE" ];then
 sed -i -e 's:VIDEO_CONSOLE ::g' ${TEMPDIR}/boot.cmd
 sed -i -e 's:VIDEO_RAM ::g' ${TEMPDIR}/boot.cmd
 sed -i -e "s/VIDEO_DEVICE:VIDEO_MODE //g" ${TEMPDIR}/boot.cmd
else
 #Enable Video Console
 sed -i -e 's:VIDEO_CONSOLE:'$VIDEO_CONSOLE':g' ${TEMPDIR}/boot.cmd
 sed -i -e 's:VIDEO_RAM:'vram=\${vram}':g' ${TEMPDIR}/boot.cmd
 sed -i -e 's:VIDEO_TIMING:'$VIDEO_TIMING':g' ${TEMPDIR}/boot.cmd
 sed -i -e 's:VIDEO_DEVICE:'$VIDEO_DRV':g' ${TEMPDIR}/boot.cmd
 sed -i -e 's:VIDEO_MODE:'\${dvimode}':g' ${TEMPDIR}/boot.cmd
fi

 if [ "$USB_ROOTFS" ];then
  sed -i 's/mmcblk0p5/sda1/g' ${TEMPDIR}/boot.cmd
 fi

 if [ "$PRINTK" ];then
  sed -i 's/bootargs/bootargs earlyprintk/g' ${TEMPDIR}/boot.cmd
 fi

}

function dl_bootloader {

 echo ""
 echo "Downloading Bootloader"
 echo ""

 mkdir -p ${TEMPDIR}/dl/${DIST}
 mkdir -p ${DIR}/dl/${DIST}

 wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}tools/latest/bootloader

 if [ "$BETA_BOOT" ];then
  ABI="ABX"
 else
  ABI="ABI"
 fi

if [ "${HASMLO}" ] ; then
 MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${ABI_VER}:MLO" | awk '{print $2}')
fi

UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${ABI_VER}:UBOOT" | awk '{print $2}')

if [ "${HASMLO}" ] ; then
 wget -c --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MLO}
 MLO=${MLO##*/}
fi

 wget -c --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${UBOOT}
 UBOOT=${UBOOT##*/}
}

function dl_root_image {

echo ""
echo "Downloading Fedora Root Image"
echo ""

case "$DIST" in
    f13)
	ROOTFS_MD5SUM=$F13_MD5SUM
	ROOTFS_IMAGE=$F13_IMAGE
        ;;
esac

if ls ${DIR}/dl/${DIST}/${ROOTFS_IMAGE} >/dev/null 2>&1;then
  MD5SUM=$(md5sum ${DIR}/dl/${DIST}/${ROOTFS_IMAGE} | awk '{print $1}')
  if [ "=$ROOTFS_MD5SUM=" != "=$MD5SUM=" ]; then
    echo "md5sum changed $MD5SUM"
    rm -f ${DIR}/dl/${DIST}/initrd.gz || true
    wget --directory-prefix=${DIR}/dl/${DIST} ${FEDORA_MIRROR}/${ROOTFS_IMAGE}
    NEW_MD5SUM=$(md5sum ${DIR}/dl/${DIST}/${ROOTFS_IMAGE} | awk '{print $1}')
    echo "new md5sum $NEW_MD5SUM"
  fi
else
  wget --directory-prefix=${DIR}/dl/${DIST} ${FEDORA_MIRROR}/${ROOTFS_IMAGE}
fi

}

function dl_kernel_image {

echo ""
echo "Downloading Kernel Image"
echo ""

 wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ http://rcn-ee.net/deb/wheezy/LATEST-${SUBARCH}
# wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ http://rcn-ee.net/deb/${DIST}/LATEST-${SUBARCH}

 if [ "$BETA_KERNEL" ];then
  KERNEL_SEL="TESTING"
 else
  KERNEL_SEL="STABLE"
 fi

 if [ "$EXPERIMENTAL_KERNEL" ];then
  KERNEL_SEL="EXPERIMENTAL"
 fi

if [ ! "${KERNEL_DEB}" ] ; then

 FTP_DIR=$(cat ${TEMPDIR}/dl/LATEST-${SUBARCH} | grep "ABI:1 ${KERNEL_SEL}" | awk '{print $3}')
 FTP_DIR=$(echo ${FTP_DIR} | awk -F'/' '{print $6}')
 KERNEL=$(echo ${FTP_DIR} | sed 's/v//')

# wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ http://rcn-ee.net/deb/${DIST}/${FTP_DIR}/
 wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ http://rcn-ee.net/deb/wheezy/${FTP_DIR}/
 ACTUAL_DEB_FILE=$(cat ${TEMPDIR}/dl/index.html | grep linux-image | awk -F "\"" '{print $2}')

else

 KERNEL=${DEB_FILE}
 #Remove all "\" from file name.
 ACTUAL_DEB_FILE=$(echo ${DEB_FILE} | sed 's!.*/!!' | grep linux-image)

fi

 echo "Using: ${ACTUAL_DEB_FILE}"

if [ ! "${KERNEL_DEB}" ] ; then
 wget -c --directory-prefix=${DIR}/dl/${DIST} ${MIRROR}wheezy/v${KERNEL}/${ACTUAL_DEB_FILE}
# wget -c --directory-prefix=${DIR}/dl/${DIST} ${MIRROR}${DIST}/v${KERNEL}/${ACTUAL_DEB_FILE}
else
 cp -v ${DEB_FILE} ${DIR}/dl/${DIST}/
fi

}

function dl_firmware {

if [ "${FIRMWARE}" ] ; then

 echo ""
 echo "Downloading Firmware"
 echo ""

if ls ${DIR}/dl/linux-firmware/.git/ >/dev/null 2>&1;then
 cd ${DIR}/dl/linux-firmware
 git pull
 cd -
else
 cd ${DIR}/dl/
 git clone git://git.infradead.org/users/dwmw2/linux-firmware.git
 #git clone git://git.kernel.org/pub/scm/linux/kernel/git/dwmw2/linux-firmware.git
 cd -
fi

case "$DIST" in
    f13)
	echo "nothing yet"
        ;;
esac

fi

}


function prepare_initrd {
 mkdir -p ${TEMPDIR}/initrd-tree
 cd ${TEMPDIR}/initrd-tree
 sudo zcat ${DIR}/dl/${DIST}/initrd.gz | sudo cpio -i -d
 sudo dpkg -x ${DIR}/dl/${DIST}/${ACTUAL_DEB_FILE} ${TEMPDIR}/initrd-tree
 cd ${DIR}/

 sudo mkdir -p ${TEMPDIR}/initrd-tree/lib/firmware/



 sudo touch ${TEMPDIR}/initrd-tree/etc/rcn.conf

 #work around for the kevent smsc95xx issue
 sudo touch ${TEMPDIR}/initrd-tree/etc/sysctl.conf
 if [ "$SMSC95XX_MOREMEM" ];then
  echo "vm.min_free_kbytes = 16384" | sudo tee -a ${TEMPDIR}/initrd-tree/etc/sysctl.conf
 else
  echo "vm.min_free_kbytes = 8192" | sudo tee -a ${TEMPDIR}/initrd-tree/etc/sysctl.conf
 fi

 cd ${TEMPDIR}/initrd-tree/
 find . | cpio -o -H newc | gzip -9 > ${TEMPDIR}/initrd.mod.gz
 cd ${DIR}/
}

function umount_partitions {

 echo ""
 echo "Umounting Partitions"
 echo ""

NUM_MOUNTS=$(mount | grep -v none | grep "$MMC" | wc -l)

 for (( c=1; c<=$NUM_MOUNTS; c++ ))
 do
  DRIVE=$(mount | grep -v none | grep "$MMC" | tail -1 | awk '{print $1}')
  sudo umount ${DRIVE} &> /dev/null || true
 done

}

function omap_uboot_in_fat {

echo ""
echo "Setting up Omap Boot Partition"
echo ""

sudo fdisk ${FDISK_DOS} ${MMC} << END
n
p
1
1
+64M
t
e
p
w
END

sync

sudo parted --script ${MMC} set 1 boot on

}

function imx_dd_uboot {

echo ""
echo "Setting up Imx Boot Partition"
echo ""

sudo dd if=${TEMPDIR}/dl/${UBOOT} of=${MMC} seek=1 bs=1024

#for now, lets default to fat16
sudo parted --script ${PARTED_ALIGN} ${MMC} mkpart primary fat16 10 100

}

function boot_partition {

sudo parted --script ${MMC} mklabel msdos
 
if [ "${DO_UBOOT_DD}" ] ; then
 imx_dd_uboot
else
 omap_uboot_in_fat 
fi

}

function root_partition {

echo ""
echo "Setting up Root Partition"
echo ""

unset END_BOOT
END_BOOT=$(LC_ALL=C sudo parted -s ${MMC} unit mb print free | grep primary | awk '{print $3}' | cut -d "M" -f1)

unset END_DEVICE
END_DEVICE=$(LC_ALL=C sudo parted -s ${MMC} unit mb print free | grep Free | tail -n 1 | awk '{print $2}' | cut -d "M" -f1)

sudo parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ${RFS} ${END_BOOT} ${END_DEVICE}
sync

}

function format_partitions {

echo ""
echo "Setting up Root Partition"
echo ""

sudo mkfs.vfat -F 16 ${MMC}${PARTITION_PREFIX}1 -n ${BOOT_LABEL}
sudo mkfs.${RFS} ${MMC}${PARTITION_PREFIX}2 -L ${RFS_LABEL}

}

function copy_boot_files {

mkdir -p ${TEMPDIR}/disk

if sudo mount -t vfat ${MMC}${PARTITION_PREFIX}1 ${TEMPDIR}/disk; then

if [ "${HASMLO}" ] ; then
 if ls ${TEMPDIR}/dl/${MLO} >/dev/null 2>&1;then
  sudo cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/MLO
 fi
fi

if [ ! "${DO_UBOOT_DD}" ] ; then
 if ls ${TEMPDIR}/dl/${UBOOT} >/dev/null 2>&1;then
  if echo ${UBOOT} | grep img > /dev/null 2>&1;then
   sudo cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.img
  else
   sudo cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.bin
  fi
 fi
fi

mkdir -p ${TEMPDIR}/kernel
sudo dpkg -x ${DIR}/dl/${DIST}/${ACTUAL_DEB_FILE} ${TEMPDIR}/kernel
sudo mkimage -A arm -O linux -T kernel -C none -a ${ZRELADD} -e ${ZRELADD} -n ${KERNEL} -d ${TEMPDIR}/kernel/boot/vmlinuz-* ${TEMPDIR}/disk/uImage

echo "boot.cmd"
cat ${TEMPDIR}/boot.cmd
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d ${TEMPDIR}/boot.cmd ${TEMPDIR}/disk/boot.scr
sudo cp -v ${TEMPDIR}/uEnv.cmd ${TEMPDIR}/disk/uEnv.txt
sudo cp -v ${TEMPDIR}/boot.cmd ${TEMPDIR}/disk/boot.cmd

cd ${TEMPDIR}/disk
sync
cd ${DIR}/
sudo umount ${TEMPDIR}/disk || true

 echo ""
 echo "Finished populating Boot Partition"
else
 echo ""
 echo "Unable to mount ${MMC}${PARTITION_PREFIX}1 at ${TEMPDIR}/disk to complete populating Boot Partition"
 echo "Please retry running the script, sometimes rebooting your system helps."
 echo ""
 exit
fi

}

function copy_rootfs_files {

if sudo mount -t ${RFS} ${MMC}${PARTITION_PREFIX}2 ${TEMPDIR}/disk; then

 if ls ${DIR}/dl/${DIST}/${ROOTFS_IMAGE} >/dev/null 2>&1;then
   pv ${DIR}/dl/${DIST}/${ROOTFS_IMAGE} | sudo tar --numeric-owner --preserve-permissions -xjf - -C ${TEMPDIR}/disk/
 fi

 sudo dpkg -x ${DIR}/dl/${DIST}/${ACTUAL_DEB_FILE} ${TEMPDIR}/disk/

 sudo sed -i 's/root/mmcblk2/g' ${TEMPDIR}/disk/etc/fstab
 sudo sed -i 's:nfs:'$RFS':g' ${TEMPDIR}/disk/etc/fstab

if [ "$BTRFS_FSTAB" ] ; then
 sudo sed -i 's/auto   errors=remount-ro/btrfs   defaults/g' ${TEMPDIR}/disk/etc/fstab
fi

 if [ "$CREATE_SWAP" ] ; then

  echo ""
  echo "Extra: Creating SWAP File"
  echo ""
  echo "SWAP BUG creation note:"
  echo "IF this takes a long time(>= 5mins) open another terminal and run dmesg"
  echo "if theres a nasty error, ctrl-c/reboot and try again... its an annoying bug.."
  echo ""

  SPACE_LEFT=$(df ${TEMPDIR}/disk/ | grep ${MMC}${PARTITION_PREFIX}2 | awk '{print $4}')

  let SIZE=$SWAP_SIZE*1024

  if [ $SPACE_LEFT -ge $SIZE ] ; then
   dd if=/dev/zero of=${TEMPDIR}/disk/mnt/SWAP.swap bs=1M count=$SWAP_SIZE
   mkswap ${TEMPDIR}/disk/mnt/SWAP.swap
   echo "/mnt/SWAP.swap  none  swap  sw  0 0" >> ${TEMPDIR}/disk/etc/fstab
   else
   echo "FIXME Recovery after user selects SWAP file bigger then whats left not implemented"
  fi
 fi

 cd ${TEMPDIR}/disk/
 sync
 sync
 cd ${DIR}/
 sudo umount ${TEMPDIR}/disk || true

 echo ""
 echo "Finished populating Boot Partition"
else
 echo ""
 echo "Unable to mount ${MMC}${PARTITION_PREFIX}1 at ${TEMPDIR}/disk to complete populating Boot Partition"
 echo "Please retry running the script, sometimes rebooting your system helps."
 echo ""
 exit
fi

}

function reset_scripts {

 #Setup serial
 sed -i -e 's:'$SERIAL':SERIAL:g' ${DIR}/scripts/serial.conf
 sed -i -e 's:'$SERIAL':SERIAL:g' ${DIR}/scripts/*-tweaks.diff

 if [ "$SMSC95XX_MOREMEM" ];then
  sed -i 's/16384/8192/g' ${DIR}/scripts/*.diff
 fi

}

function check_mmc {
 FDISK=$(sudo LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "sudo fdisk -l:"
  sudo LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  read -p "Are you 100% sure, on selecting [${MMC}] (y/n)? "
  [ "$REPLY" == "y" ] || exit
  echo ""
 else
  echo ""
  echo "Are you sure? I Don't see [${MMC}], here is what I do see..."
  echo ""
  echo "sudo fdisk -l:"
  sudo LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  exit
 fi
}

function is_omap {
 HASMLO=1
 UIMAGE_ADDR="0x80300000"
 UINITRD_ADDR="0x81600000"
 SERIAL_CONSOLE="${SERIAL},115200n8"
 ZRELADD="0x80008000"
 SUBARCH="omap"
 VIDEO_CONSOLE="console=tty0"
 VIDEO_DRV="omapfb.mode=dvi"
 VIDEO_TIMING="1280x720MR-16@60"
}

function is_imx53 {
 UIMAGE_ADDR="0x70800000"
 UINITRD_ADDR="0x72100000"
 SERIAL_CONSOLE="${SERIAL},115200"
 ZRELADD="0x70008000"
 SUBARCH="imx"
 VIDEO_CONSOLE="console=tty0"
 VIDEO_DRV="mxcdi1fb"
 VIDEO_TIMING="RGB24,1280x720M@60"
}

function check_uboot_type {
 unset DO_UBOOT

case "$UBOOT_TYPE" in
    beagle_bx)

 SYSTEM=beagle_bx
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=1
 SERIAL="ttyO2"
 is_omap

        ;;
    beagle)

 SYSTEM=beagle
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=7
 SERIAL="ttyO2"
 is_omap

        ;;
    igepv2)

 SYSTEM=igepv2
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=3
 SERIAL="ttyO2"
 is_omap

        ;;
    panda)

 SYSTEM=panda
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=2
 SMSC95XX_MOREMEM=1
 SERIAL="ttyO2"
 is_omap

        ;;
    touchbook)

 SYSTEM=touchbook
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=5
 SERIAL="ttyO2"
 is_omap

 BETA_KERNEL=1
 SERIAL_MODE=1

        ;;
    crane)

 SYSTEM=crane
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=6
 SERIAL="ttyO2"
 is_omap

 #with the crane, we need the beta kernel and serial-more
 BETA_KERNEL=1
 SERIAL_MODE=1

        ;;
    mx53loco)

 SYSTEM=mx53loco
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 DO_UBOOT_DD=1
 ABI_VER=8
 SERIAL="ttymxc0"
 is_imx53

        ;;
esac

 if [ "$IN_VALID_UBOOT" ] ; then
   usage
 fi
}

function check_distro {
 IN_VALID_DISTRO=1

 if test "-$DISTRO_TYPE-" = "-squeeze-"
 then
 DIST=squeeze
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-maverick-"
 then
 DIST=maverick
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-oneiric-"
 then
 DIST=oneiric
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-natty-"
 then
 DIST=natty
 unset IN_VALID_DISTRO
 fi

# if test "-$DISTRO_TYPE-" = "-sid-"
# then
# DIST=sid
# unset IN_VALID_DISTRO
# fi

 if [ "$IN_VALID_DISTRO" ] ; then
   usage
 fi
}

function check_fs_type {
 IN_VALID_FS=1

case "$FS_TYPE" in
    ext2)

 RFS=ext2
 unset IN_VALID_FS

        ;;
    ext3)

 RFS=ext3
 unset IN_VALID_FS

        ;;
    ext4)

 RFS=ext4
 unset IN_VALID_FS

        ;;
    btrfs)

 RFS=btrfs
 unset IN_VALID_FS
 BTRFS_FSTAB=1

        ;;
esac

 if [ "$IN_VALID_FS" ] ; then
   usage
 fi
}

function usage {
    echo "usage: $(basename $0) --mmc /dev/sdX --uboot <dev board>"
cat <<EOF

Script Version $SCRIPT_VERSION
Bugs email: "bugs at rcn-ee.com"

Required Options:
--mmc </dev/sdX>
    Unformated MMC Card

Additional/Optional options:
-h --help
    this help

--probe-mmc
    List all partitions

--uboot <dev board>
    (omap)
    beagle_bx - <Ax/Bx Models>
    beagle - <Cx, xM A/B/C>
    igepv2 - 
    panda - <dvi or serial>
    touchbook - <serial only>

    (freescale)
    mx53loco

--distro <distro>
    Fedora:
      f13 <default>

--rootfs <fs_type>
    ext3
    ext4 - <set as default>
    btrfs

Optional:
--firmware
    Add distro firmware

--serial-mode
    <dvi is default, this overides>

--usb-rootfs
    <root=/dev/sda1>

Debug:
--earlyprintk
    <enables earlyprintk over serial>

EOF
exit
}

function checkparm {
    if [ "$(echo $1|grep ^'\-')" ];then
        echo "E: Need an argument"
        usage
    fi
}

# parse commandline options
while [ ! -z "$1" ]; do
    case $1 in
        -h|--help)
            usage
            MMC=1
            ;;
        --probe-mmc)
            MMC="/dev/idontknow"
            detect_software
            check_mmc
            ;;
        --mmc)
            checkparm $2
            MMC="$2"
	    if [[ "${MMC}" =~ "mmcblk" ]]
            then
	        PARTITION_PREFIX="p"
            fi
            detect_software
            check_mmc 
            ;;
        --uboot)
            checkparm $2
            UBOOT_TYPE="$2"
            check_uboot_type
            ;;
        --distro)
            checkparm $2
            DISTRO_TYPE="$2"
            check_distro
            ;;
        --firmware)
            FIRMWARE=1
            ;;
        --rootfs)
            checkparm $2
            FS_TYPE="$2"
            check_fs_type 
            ;;
        --serial-mode)
            SERIAL_MODE=1
            ;;
	--deb-file)
            checkparm $2
            DEB_FILE="$2"
            KERNEL_DEB=1
            ;;
        --beta-kernel)
            BETA_KERNEL=1
            ;;
        --experimental-kernel)
            EXPERIMENTAL_KERNEL=1
            ;;
        --beta-boot)
            BETA_BOOT=1
            ;;
	--usb-rootfs)
            USB_ROOTFS=1
            ;;
	--earlyprintk)
            PRINTK=1
            ;;
    esac
    shift
done

if [ ! "${MMC}" ];then
    echo "ERROR: --mmc undefined"
    usage
fi

if [ "$IN_VALID_UBOOT" ] ; then
    echo "ERROR: --uboot undefined"
    usage
fi

 boot_files_template
 set_defaults
 dl_bootloader
 dl_root_image
 dl_kernel_image
 dl_firmware

 umount_partitions
 boot_partition
 root_partition
 umount_partitions
 format_partitions

 copy_boot_files
 copy_rootfs_files

# create_partitions
# reset_scripts


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
unset USE_BETA_BOOTLOADER
unset BETA_KERNEL
unset EXPERIMENTAL_KERNEL
unset USB_ROOTFS
unset PRINTK
unset SPL_BOOT
unset ABI_VER
unset SMSC95XX_MOREMEM
unset DD_UBOOT
unset KERNEL_DEB
unset USE_UENV

unset SVIDEO_NTSC
unset SVIDEO_PAL

SCRIPT_VERSION="1.11"
IN_VALID_UBOOT=1

MIRROR="http://rcn-ee.net/deb/"

#Defaults
RFS=ext4
DIST=f13
ACTUAL_DIST=f13

BOOT_LABEL=boot
RFS_LABEL=rootfs
PARTITION_PREFIX=""

FEDORA_MIRROR="http://scotland.proximity.on.ca/fedora-arm/rootfs/"

F13_IMAGE="rootfs-f13-beta3-2011-05-10.tar.bz2"
F13_MD5SUM="d4f68c5fcdfa47079a7baf099daa3ba3"

F14_IMAGE="f14-rootfs-2011-06-23.tar.bz2"
F14_MD5SUM="d4f68c5fcdfa47079a7baf099daa3ba3"

DIR=$PWD
TEMPDIR=$(mktemp -d)

function check_root {
if [[ $UID -ne 0 ]]; then
 echo "$0 must be run as sudo user or root"
 exit
fi
}

function find_issue {

check_root

#Software Qwerks
#fdisk 2.18.x/2.19.x, dos no longer default
unset FDISK_DOS

if test $(sudo fdisk -v | grep -o -E '2\.[0-9]+' | cut -d'.' -f2) -ge 18 ; then
 FDISK_DOS="-c=dos -u=cylinders"
fi

#Check for gnu-fdisk
#FIXME: GNU Fdisk seems to halt at "Using /dev/xx" when trying to script it..
if fdisk -v | grep "GNU Fdisk" >/dev/null ; then
 echo "Sorry, this script currently doesn't work with GNU Fdisk"
 exit
fi

unset PARTED_ALIGN
if parted -v | grep parted | grep 2.[1-3] >/dev/null ; then
 PARTED_ALIGN="--align cylinder"
fi
}

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

function dl_bootloader {
 echo ""
 echo "Downloading Device's Bootloader"
 echo "-----------------------------"

 mkdir -p ${TEMPDIR}/dl/${DIST}
 mkdir -p ${DIR}/dl/${DIST}

 wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}tools/latest/bootloader

 if [ "$USE_BETA_BOOTLOADER" ];then
  ABI="ABX"
 else
  ABI="ABI"
 fi

 if [ "${SPL_BOOT}" ] ; then
  MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${ABI_VER}:MLO" | awk '{print $2}')
  wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MLO}
  MLO=${MLO##*/}
  echo "SPL Bootloader: ${MLO}"
 fi

 UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${ABI_VER}:UBOOT" | awk '{print $2}')
 wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${UBOOT}
 UBOOT=${UBOOT##*/}
 echo "UBOOT Bootloader: ${UBOOT}"
}

function dl_kernel_image {
 echo ""
 echo "Downloading Device's Kernel Image"
 echo "-----------------------------"

 KERNEL_SEL="STABLE"

 if [ "$BETA_KERNEL" ];then
  KERNEL_SEL="TESTING"
 fi

 if [ "$EXPERIMENTAL_KERNEL" ];then
  KERNEL_SEL="EXPERIMENTAL"
 fi

 #FIXME: use squeeze kernel for now
 DIST=wheezy
 ARCH=armel

 if [ ! "${KERNEL_DEB}" ] ; then
  wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ http://rcn-ee.net/deb/${DIST}-${ARCH}/LATEST-${SUBARCH}
  FTP_DIR=$(cat ${TEMPDIR}/dl/LATEST-${SUBARCH} | grep "ABI:1 ${KERNEL_SEL}" | awk '{print $3}')
  FTP_DIR=$(echo ${FTP_DIR} | awk -F'/' '{print $6}')
  KERNEL=$(echo ${FTP_DIR} | sed 's/v//')

  wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ http://rcn-ee.net/deb/${DIST}-${ARCH}/${FTP_DIR}/
  ACTUAL_DEB_FILE=$(cat ${TEMPDIR}/dl/index.html | grep linux-image | awk -F "\"" '{print $2}')
  wget -c --directory-prefix=${DIR}/dl/${DIST} ${MIRROR}${DIST}-${ARCH}/v${KERNEL}/${ACTUAL_DEB_FILE}
  if [ "${DI_BROKEN_USE_CROSS}" ] ; then
   CROSS_DEB_FILE=$(echo ${ACTUAL_DEB_FILE} | sed 's:'${DIST}':cross:g')
   wget -c --directory-prefix=${DIR}/dl/${DIST} ${MIRROR}cross/v${KERNEL}/${CROSS_DEB_FILE}
  fi
 else
  unset DI_BROKEN_USE_CROSS
  KERNEL=${DEB_FILE}
  #Remove all "\" from file name.
  ACTUAL_DEB_FILE=$(echo ${DEB_FILE} | sed 's!.*/!!' | grep linux-image)
  cp -v ${DEB_FILE} ${DIR}/dl/${DIST}/
 fi

 #FIXME: reset back to fedora
 DIST=${ACTUAL_DIST}

 echo "Using: ${ACTUAL_DEB_FILE}"
}

function dl_root_image {

 echo ""
 echo "Downloading Fedora Root Image"
 echo "-----------------------------"

case "$DIST" in
    f13)
	ROOTFS_MD5SUM=$F13_MD5SUM
	ROOTFS_IMAGE=$F13_IMAGE
        ;;
    f14)
	ROOTFS_MD5SUM=$F14_MD5SUM
	ROOTFS_IMAGE=$F14_IMAGE
        ;;
esac

 if [ -f ${DIR}/dl/${DIST}/${ROOTFS_IMAGE} ]; then
  MD5SUM=$(md5sum ${DIR}/dl/${DIST}/${ROOTFS_IMAGE} | awk '{print $1}')
  if [ "=$ROOTFS_MD5SUM=" != "=$MD5SUM=" ]; then
    echo "Note: md5sum has changed: $MD5SUM"
    echo "-----------------------------"
    rm -f ${DIR}/dl/${DIST}/${ROOTFS_IMAGE} || true
    wget --directory-prefix=${DIR}/dl/${DIST} ${FEDORA_MIRROR}/${ROOTFS_IMAGE}
    NEW_MD5SUM=$(md5sum ${DIR}/dl/${DIST}/${ROOTFS_IMAGE} | awk '{print $1}')
    echo "Note: new md5sum $NEW_MD5SUM"
    echo "-----------------------------"
  fi
 else
  wget --directory-prefix=${DIR}/dl/${DIST} ${FEDORA_MIRROR}/${ROOTFS_IMAGE}
 fi
}

function dl_firmware {
 echo ""
 echo "Downloading Firmware"
 echo "-----------------------------"

 #TODO: We should just use the git tree blobs over distro versions
 if ! ls ${GIT_DIR}/dl/linux-firmware/.git/ >/dev/null 2>&1;then
  cd ${DIR}/dl/
  git clone git://git.kernel.org/pub/scm/linux/kernel/git/dwmw2/linux-firmware.git
  cd ${DIR}/
 else
  cd ${DIR}/dl/linux-firmware
  git pull
  cd ${DIR}/
 fi

case "$DIST" in
    f13)
	#V3.1 needs 1.9.4 for ar9170
	#wget -c --directory-prefix=${DIR}/dl/${DIST} http://www.kernel.org/pub/linux/kernel/people/chr/carl9170/fw/1.9.4/carl9170-1.fw
	wget -c --directory-prefix=${DIR}/dl/${DIST} http://rcn-ee.net/firmware/carl9170/1.9.4/carl9170-1.fw
	AR9170_FW="carl9170-1.fw"
        ;;
esac

}

function boot_files_template {

cat > ${TEMPDIR}/bootscripts/boot.cmd <<boot_cmd
setenv defaultdisplay VIDEO_OMAPFB_MODE
setenv dvimode VIDEO_TIMING
setenv vram 12MB
setenv console SERIAL_CONSOLE
setenv optargs VIDEO_CONSOLE
setenv mmcroot /dev/mmcblk0p2 ro
setenv mmcrootfstype FINAL_FSTYPE rootwait fixrtc
setenv bootcmd 'fatload mmc 0:1 UIMAGE_ADDR uImage; bootm UIMAGE_ADDR'
setenv bootargs console=\${console} \${optargs} root=\${mmcroot} rootfstype=\${mmcrootfstype} VIDEO_RAM omapfb.mode=\${defaultdisplay}:\${dvimode} omapdss.def_disp=\${defaultdisplay}
boot
boot_cmd

}

function boot_scr_to_uenv_txt {

cat > ${TEMPDIR}/bootscripts/uEnv.cmd <<uenv_boot_cmd
bootenv=boot.scr
loaduimage=fatload mmc \${mmcdev} \${loadaddr} \${bootenv}
mmcboot=echo Running boot.scr script from mmc ...; source \${loadaddr}
uenv_boot_cmd

}

function boot_uenv_txt_template {
#(rcn-ee)in a way these are better then boot.scr, but each target is going to have a slightly different entry point..

cat > ${TEMPDIR}/bootscripts/normal.cmd <<uenv_generic_normalboot_cmd
bootfile=uImage
bootinitrd=uInitrd
address_uimage=UIMAGE_ADDR
address_uinitrd=UINITRD_ADDR

console=SERIAL_CONSOLE

defaultdisplay=VIDEO_OMAPFB_MODE
dvimode=VIDEO_TIMING

mmcroot=/dev/mmcblk0p2 ro
mmcrootfstype=FINAL_FSTYPE rootwait fixrtc
uenv_generic_normalboot_cmd

case "$SYSTEM" in
    beagle_bx)

cat >> ${TEMPDIR}/bootscripts/normal.cmd <<uenv_normalboot_cmd
optargs=VIDEO_CONSOLE

mmc_load_uimage=fatload mmc 0:1 \${address_uimage} \${bootfile}
mmc_load_uinitrd=fatload mmc 0:1 \${address_uinitrd} \${bootinitrd}

#dvi->defaultdisplay
mmcargs=setenv bootargs console=\${console} \${optargs} mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2} camera=\${camera} VIDEO_RAM omapfb.mode=\${defaultdisplay}:\${dvimode} omapdss.def_disp=\${defaultdisplay} root=\${mmcroot} rootfstype=\${mmcrootfstype}

loaduimage=run mmc_load_uimage; echo Booting from mmc ...; run mmcargs; bootm \${address_uimage}
uenv_normalboot_cmd
        ;;
    beagle)

cat >> ${TEMPDIR}/bootscripts/normal.cmd <<uenv_normalboot_cmd
optargs=VIDEO_CONSOLE

mmc_load_uimage=fatload mmc 0:1 \${address_uimage} \${bootfile}
mmc_load_uinitrd=fatload mmc 0:1 \${address_uinitrd} \${bootinitrd}

#dvi->defaultdisplay
mmcargs=setenv bootargs console=\${console} \${optargs} mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2} camera=\${camera} VIDEO_RAM omapfb.mode=\${defaultdisplay}:\${dvimode} omapdss.def_disp=\${defaultdisplay} root=\${mmcroot} rootfstype=\${mmcrootfstype}

loaduimage=run mmc_load_uimage; echo Booting from mmc ...; run mmcargs; bootm \${address_uimage}
uenv_normalboot_cmd
        ;;
    bone)

cat >> ${TEMPDIR}/bootscripts/normal.cmd <<uenv_normalboot_cmd
rcn_mmcloaduimage=fatload mmc 0:1 \${address_uimage} \${bootfile}
mmc_load_uinitrd=fatload mmc 0:1 \${address_uinitrd} \${bootinitrd}

mmc_args=run bootargs_defaults;setenv bootargs \${bootargs} root=\${mmcroot} rootfstype=\${mmcrootfstype} ip=\${ip_method}

mmc_load_uimage=run rcn_mmcloaduimage; echo Booting from mmc ...; run mmc_args; bootm \${address_uimage}
uenv_normalboot_cmd
        ;;
esac

}

function tweak_boot_scripts {
# echo "Adding Device Specific info to bootscripts"
# echo "-----------------------------"

 if test "-$ADDON-" = "-pico-"
 then
  VIDEO_TIMING="640x480MR-16@60"
 fi

 if test "-$ADDON-" = "-ulcd-"
 then
  VIDEO_TIMING="800x480MR-16@60"
 fi

 if [ "$SVIDEO_NTSC" ];then
  VIDEO_TIMING="ntsc"
  VIDEO_OMAPFB_MODE=tv
 fi

 if [ "$SVIDEO_PAL" ];then
  VIDEO_TIMING="pal"
  VIDEO_OMAPFB_MODE=tv
 fi

 #Set uImage boot address
 sed -i -e 's:UIMAGE_ADDR:'$UIMAGE_ADDR':g' ${TEMPDIR}/bootscripts/*.cmd

 #Set uInitrd boot address
 sed -i -e 's:UINITRD_ADDR:'$UINITRD_ADDR':g' ${TEMPDIR}/bootscripts/*.cmd

 #Set the Serial Console
 sed -i -e 's:SERIAL_CONSOLE:'$SERIAL_CONSOLE':g' ${TEMPDIR}/bootscripts/*.cmd

 #Set filesystem type
 sed -i -e 's:FINAL_FSTYPE:'$RFS':g' ${TEMPDIR}/bootscripts/*.cmd

if [ "$SERIAL_MODE" ];then
 #console=CONSOLE
 #Set the Serial Console
 sed -i -e 's:SERIAL_CONSOLE:'$SERIAL_CONSOLE':g' ${TEMPDIR}/bootscripts/*.cmd

 #omap3/4 DSS:
 #VIDEO_RAM
 sed -i -e 's:VIDEO_RAM ::g' ${TEMPDIR}/bootscripts/*.cmd
 #omapfb.mode=\${defaultdisplay}:\${dvimode} omapdss.def_disp=\${defaultdisplay}
 sed -i -e 's:'\${defaultdisplay}'::g' ${TEMPDIR}/bootscripts/*.cmd
 sed -i -e 's:'\${dvimode}'::g' ${TEMPDIR}/bootscripts/*.cmd
 #omapfb.mode=: omapdss.def_disp=
 sed -i -e "s/omapfb.mode=: //g" ${TEMPDIR}/bootscripts/*.cmd
 sed -i -e 's:omapdss.def_disp= ::g' ${TEMPDIR}/bootscripts/*.cmd

else
 #Set the Video Console
 sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/*.cmd

 #omap3/4 DSS:
 #VIDEO_RAM
 sed -i -e 's:VIDEO_RAM:'vram=\${vram}':g' ${TEMPDIR}/bootscripts/*.cmd
 #set OMAP video: omapfb.mode=VIDEO_OMAPFB_MODE
 #defaultdisplay=VIDEO_OMAPFB_MODE
 #dvimode=VIDEO_TIMING
 sed -i -e 's:VIDEO_OMAPFB_MODE:'$VIDEO_OMAPFB_MODE':g' ${TEMPDIR}/bootscripts/*.cmd
 sed -i -e 's:VIDEO_TIMING:'$VIDEO_TIMING':g' ${TEMPDIR}/bootscripts/*.cmd

fi

#fixme: broke mx51/53 and reenable VIDEO on final boot..

 if [ "$PRINTK" ];then
  sed -i 's/bootargs/bootargs earlyprintk/g' ${TEMPDIR}/bootscripts/*.cmd
 fi
}

function setup_bootscripts {
 mkdir -p ${TEMPDIR}/bootscripts/

 if [ "$USE_UENV" ];then
  boot_uenv_txt_template
  tweak_boot_scripts
 else
  boot_files_template
  boot_scr_to_uenv_txt
  tweak_boot_scripts
 fi
}

function extract_zimage {
 mkdir -p ${TEMPDIR}/kernel
 echo "Extracting Kernel Boot Image"
 #FIXME
 DIST=wheezy
 if [ ! "${DI_BROKEN_USE_CROSS}" ] ; then
  dpkg -x ${DIR}/dl/${DIST}/${ACTUAL_DEB_FILE} ${TEMPDIR}/kernel
 else
  dpkg -x ${DIR}/dl/${DIST}/${CROSS_DEB_FILE} ${TEMPDIR}/kernel
 fi
 #FIXME
 DIST=${ACTUAL_DIST}
}

function unmount_all_drive_partitions {
 echo ""
 echo "Unmounting Partitions"
 echo "-----------------------------"

 NUM_MOUNTS=$(mount | grep -v none | grep "$MMC" | wc -l)

 for (( c=1; c<=$NUM_MOUNTS; c++ ))
 do
  DRIVE=$(mount | grep -v none | grep "$MMC" | tail -1 | awk '{print $1}')
  umount ${DRIVE} &> /dev/null || true
 done

 parted --script ${MMC} mklabel msdos
}

function uboot_in_boot_partition {
 echo ""
 echo "Using fdisk to create BOOT Partition"
 echo "-----------------------------"

 #With util-linux, 2.18.x/2.19.x, fdisk no longer has dos/cylinders mode on by default
 unset FDISK_DOS

 if test $(fdisk -v | grep -o -E '2\.[0-9]+' | cut -d'.' -f2) -ge 18 ; then
  FDISK_DOS="-c=dos -u=cylinders"
 fi

fdisk ${FDISK_DOS} ${MMC} << END
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

 echo "Setting Boot Partition's Boot Flag"
 echo "-----------------------------"
 parted --script ${MMC} set 1 boot on

if [ "$FDISK_DEBUG" ];then
 echo "Debug: Partition 1 layout:"
 echo "-----------------------------"
 fdisk -l ${MMC}
 echo "-----------------------------"
fi
}

function dd_uboot_before_boot_partition {
 echo ""
 echo "Using dd to place bootloader before BOOT Partition"
 echo "-----------------------------"
 dd if=${TEMPDIR}/dl/${UBOOT} of=${MMC} seek=1 bs=1024

 #For now, lets default to fat16, but this could be ext2/3/4
 echo "Using parted to create BOOT Partition"
 echo "-----------------------------"
 parted --script ${PARTED_ALIGN} ${MMC} mkpart primary fat16 10 100
 #parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ext3 10 100
}

function calculate_rootfs_partition {
 echo "Creating rootfs ${RFS} Partition"
 echo "-----------------------------"

 unset END_BOOT
 END_BOOT=$(LC_ALL=C parted -s ${MMC} unit mb print free | grep primary | awk '{print $3}' | cut -d "M" -f1)

 unset END_DEVICE
 END_DEVICE=$(LC_ALL=C parted -s ${MMC} unit mb print free | grep Free | tail -n 1 | awk '{print $2}' | cut -d "M" -f1)

 parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ${RFS} ${END_BOOT} ${END_DEVICE}
 sync

 if [ "$FDISK_DEBUG" ];then
  echo "Debug: ${RFS} Partition"
  echo "-----------------------------"
  echo "parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ${RFS} ${END_BOOT} ${END_DEVICE}"
  fdisk -l ${MMC}
 fi
}

function format_boot_partition {
 echo "Formating Boot Partition"
 echo "-----------------------------"
 mkfs.vfat -F 16 ${MMC}${PARTITION_PREFIX}1 -n ${BOOT_LABEL}
}

function format_rootfs_partition {
 echo "Formating rootfs Partition as ${RFS}"
 echo "-----------------------------"
 mkfs.${RFS} ${MMC}${PARTITION_PREFIX}2 -L ${RFS_LABEL}
}

function create_partitions {

if [ "${DD_UBOOT}" ] ; then
 dd_uboot_before_boot_partition
else
 uboot_in_boot_partition
fi

 calculate_rootfs_partition
 format_boot_partition
 format_rootfs_partition
}

function populate_boot {
 echo "Populating Boot Partition"
 echo "-----------------------------"

 partprobe ${MMC}
 mkdir -p ${TEMPDIR}/disk

 if mount -t vfat ${MMC}${PARTITION_PREFIX}1 ${TEMPDIR}/disk; then

  if [ "${SPL_BOOT}" ] ; then
   if [ -f ${TEMPDIR}/dl/${MLO} ]; then
    cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/MLO
   fi
  fi

  if [ ! "${DD_UBOOT}" ] ; then
   if [ -f ${TEMPDIR}/dl/${UBOOT} ]; then
    if echo ${UBOOT} | grep img > /dev/null 2>&1;then
     cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.img
    else
     cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.bin
    fi
   fi
  fi

 VMLINUZ="vmlinuz-*"
 UIMAGE="uImage"

 if [ -f ${TEMPDIR}/kernel/boot/${VMLINUZ} ]; then
  LINUX_VER=$(ls ${TEMPDIR}/kernel/boot/${VMLINUZ} | awk -F'vmlinuz-' '{print $2}')
  echo "Using mkimage to create uImage"
  echo "-----------------------------"
  mkimage -A arm -O linux -T kernel -C none -a ${ZRELADD} -e ${ZRELADD} -n ${LINUX_VER} -d ${TEMPDIR}/kernel/boot/${VMLINUZ} ${TEMPDIR}/disk/${UIMAGE}
 fi

if [ "$DO_UBOOT" ];then

if [ "${USE_UENV}" ] ; then
 echo "Copying uEnv.txt based boot scripts to Boot Partition"
 echo "-----------------------------"
 cp -v ${TEMPDIR}/bootscripts/normal.cmd ${TEMPDIR}/disk/uEnv.txt
 cat  ${TEMPDIR}/bootscripts/normal.cmd
 echo "-----------------------------"
else
 echo "Copying boot.scr based boot scripts to Boot Partition"
 echo "-----------------------------"
 cp -v ${TEMPDIR}/bootscripts/uEnv.cmd ${TEMPDIR}/disk/uEnv.txt
 cat ${TEMPDIR}/bootscripts/uEnv.cmd
 echo "-----------------------------"
 mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d ${TEMPDIR}/bootscripts/boot.cmd ${TEMPDIR}/disk/boot.scr
 cp -v ${TEMPDIR}/bootscripts/boot.cmd ${TEMPDIR}/disk/boot.cmd
 cat ${TEMPDIR}/bootscripts/boot.cmd
 echo "-----------------------------"
fi
fi

cat > ${TEMPDIR}/readme.txt <<script_readme

These can be run from anywhere, but just in case change to "cd /boot/uboot"

Tools:

 "./tools/update_boot_files.sh"

Updated with a custom uImage and modules or modified the boot.cmd/user.com files with new boot args? Run "./tools/update_boot_files.sh" to regenerate all boot files...

script_readme

cat > ${TEMPDIR}/update_boot_files.sh <<update_boot_files
#!/bin/sh

cd /boot/uboot
sudo mount -o remount,rw /boot/uboot

if ! ls /boot/initrd.img-\$(uname -r) >/dev/null 2>&1;then
sudo update-initramfs -c -k \$(uname -r)
else
sudo update-initramfs -u -k \$(uname -r)
fi

if ls /boot/initrd.img-\$(uname -r) >/dev/null 2>&1;then
sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-\$(uname -r) /boot/uboot/uInitrd
fi

if ls /boot/uboot/boot.cmd >/dev/null 2>&1;then
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d /boot/uboot/boot.cmd /boot/uboot/boot.scr
fi
if ls /boot/uboot/serial.cmd >/dev/null 2>&1;then
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d /boot/uboot/serial.cmd /boot/uboot/boot.scr
fi
sudo cp /boot/uboot/boot.scr /boot/uboot/boot.ini
if ls /boot/uboot/user.cmd >/dev/null 2>&1;then
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset Nand" -d /boot/uboot/user.cmd /boot/uboot/user.scr
fi

update_boot_files

cd ${TEMPDIR}/disk
sync
cd ${DIR}/
umount ${TEMPDIR}/disk || true

 echo "Finished populating Boot Partition"
 echo "-----------------------------"
else
 echo "-----------------------------"
 echo "Unable to mount ${MMC}${PARTITION_PREFIX}1 at ${TEMPDIR}/disk to complete populating Boot Partition"
 echo "Please retry running the script, sometimes rebooting your system helps."
 echo "-----------------------------"
 exit
fi
}

function populate_rootfs {

 echo "Populating rootfs Partition"
 echo "Please be patient, this may take a few minutes, as its transfering a lot of files.."
 echo "-----------------------------"

 partprobe ${MMC}

 if mount -t ${RFS} ${MMC}${PARTITION_PREFIX}2 ${TEMPDIR}/disk; then

 if ls ${DIR}/dl/${DIST}/${ROOTFS_IMAGE} >/dev/null 2>&1;then
   pv ${DIR}/dl/${DIST}/${ROOTFS_IMAGE} | sudo tar --numeric-owner --preserve-permissions -xjf - -C ${TEMPDIR}/disk/
   echo "Transfer of Base Rootfs Complete, syncing to disk"
   echo "-----------------------------"
 fi

 #FIXME:
 DIST=wheezy
 dpkg -x ${DIR}/dl/${DIST}/${ACTUAL_DEB_FILE} ${TEMPDIR}/disk/
 #FIXME:
 DIST=${ACTUAL_DIST}

 sed -i 's/root/mmcblk2/g' ${TEMPDIR}/disk/etc/fstab
 sed -i 's:nfs:'$RFS':g' ${TEMPDIR}/disk/etc/fstab

if [ "$BTRFS_FSTAB" ] ; then
 sed -i 's/auto   errors=remount-ro/btrfs   defaults/g' ${TEMPDIR}/disk/etc/fstab
fi

cat > ${TEMPDIR}/disk/etc/init/ttyO2.conf <<serial_console
start on stopped rc RUNLEVEL=[2345]
stop on starting runlevel [016]

respawn
exec /sbin/agetty /dev/ttyO2 115200
serial_console

#So most of the default images use ttyO2, but the bone uses ttyO0, need to find a better way..
if test "-$SERIAL-" != "-ttyO2-"
then
 if ls ${TEMPDIR}/disk/etc/init/ttyO2.conf >/dev/null 2>&1;then
  echo "Fedora: Serial Login: fixing /etc/init/ttyO2.conf to use ${SERIAL}"
  echo "-----------------------------"
  mv ${TEMPDIR}/disk/etc/init/ttyO2.conf ${TEMPDIR}/disk/etc/init/${SERIAL}.conf
  sed -i -e 's:ttyO2:'$SERIAL':g' ${TEMPDIR}/disk/etc/init/${SERIAL}.conf
 fi
fi

 if [ "$CREATE_SWAP" ] ; then

  echo "-----------------------------"
  echo "Extra: Creating SWAP File"
  echo "-----------------------------"
  echo "SWAP BUG creation note:"
  echo "IF this takes a long time(>= 5mins) open another terminal and run dmesg"
  echo "if theres a nasty error, ctrl-c/reboot and try again... its an annoying bug.."
  echo "Background: usually occured in days before Ubuntu Lucid.."
  echo "-----------------------------"

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

 umount ${TEMPDIR}/disk || true

 echo "Finished populating rootfs Partition"
 echo "-----------------------------"
else
 echo "-----------------------------"
 echo "Unable to mount ${MMC}${PARTITION_PREFIX}2 at ${TEMPDIR}/disk to complete populating rootfs Partition"
 echo "Please retry running the script, sometimes rebooting your system helps."
 echo "-----------------------------"
 exit
fi
 echo "mk_mmc.sh script complete"
}

function check_mmc {

 FDISK=$(LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "fdisk -l:"
  LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
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
  echo "fdisk -l:"
  LC_ALL=C fdisk -l 2>/dev/null | grep "[Disk] /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  exit
 fi
}

function is_omap {
 SPL_BOOT=1
 UIMAGE_ADDR="0x80300000"
 UINITRD_ADDR="0x81600000"
 SERIAL_CONSOLE="${SERIAL},115200n8"
 ZRELADD="0x80008000"
 SUBARCH="omap"
 VIDEO_CONSOLE="console=tty0"
 VIDEO_DRV="omapfb.mode=dvi"
 VIDEO_OMAPFB_MODE="dvi"
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
 USE_UENV=1
 is_omap

        ;;
    beagle)

 SYSTEM=beagle
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=7
 SERIAL="ttyO2"
 USE_UENV=1
 is_omap

        ;;
    bone)

 SYSTEM=bone
 unset IN_VALID_UBOOT
 DO_UBOOT=1
 ABI_VER=10
 SERIAL="ttyO0"
 USE_UENV=1
 is_omap
# mmc driver fails to load with this setting
# UIMAGE_ADDR="0x80200000"
# UINITRD_ADDR="0x80A00000"
 
 SERIAL_MODE=1
 SUBARCH="omap-psp"
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
 VIDEO_TIMING="1024x600MR-16@60"

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
 DD_UBOOT=1
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
 ARCH=armel
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-maverick-"
 then
 DIST=maverick
 ARCH=armel
 unset DI_BROKEN_USE_CROSS
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-oneiric-"
 then
 DIST=oneiric
 ARCH=armel
 unset DI_BROKEN_USE_CROSS
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-natty-"
 then
 DIST=natty
 ARCH=armel
 unset DI_BROKEN_USE_CROSS
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-f13-"
 then
 DIST=f13
 ARCH=armel
 unset DI_BROKEN_USE_CROSS
 unset IN_VALID_DISTRO
 fi

 if test "-$DISTRO_TYPE-" = "-f14-"
 then
 DIST=f14
 ARCH=armel
 unset DI_BROKEN_USE_CROSS
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

function check_arch {
 IN_VALID_ARCH=1

 if test "-$ARCH_TYPE-" = "-armel-"
 then
 ARCH=armel
 unset IN_VALID_ARCH
 fi

 if test "-$ARCH_TYPE-" = "-armhf-"
 then
 ARCH=armhf
 unset IN_VALID_ARCH
 fi

 if [ "$IN_VALID_ARCH" ] ; then
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
    echo "usage: sudo $(basename $0) --mmc /dev/sdX --uboot <dev board>"
cat <<EOF

Script Version $SCRIPT_VERSION
Bugs email: "bugs at rcn-ee.com"

Required Options:
--mmc </dev/sdX>

--uboot <dev board>
    (omap)
    beagle_bx - <BeagleBoard Ax/Bx>
    beagle - <BeagleBoard Cx, xMA/B/C>
    bone - <BeagleBone Ax>
    igepv2 - <serial mode only>
    panda - <PandaBoard Ax>

    (freescale)
    mx53loco

--addon <device>
    pico
    ulcd <beagle xm>

Optional:
--distro <distro>
    Fedora:
      f13 <default>
      f14

--rootfs <fs_type>
    ext3
    ext4 - <set as default>
    btrfs

--arch
    armel <default>
    armhf <disabled, should be available in Debian Wheezy/Ubuntu Precise>

--addon <device>
    pico
    ulcd <beagle xm>

--firmware
    Add distro firmware

--serial-mode
    <DVI Mode is default, this overrides it for Serial Mode>

--svideo-ntsc
    force ntsc mode for svideo

--svideo-pal
    force pal mode for svideo

Additional Options:
-h --help
    this help

--probe-mmc
    List all partitions: sudo ./mk_mmc.sh --probe-mmc

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

IN_VALID_UBOOT=1

# parse commandline options
while [ ! -z "$1" ]; do
    case $1 in
        -h|--help)
            usage
            MMC=1
            ;;
        --probe-mmc)
            MMC="/dev/idontknow"
            check_root
            check_mmc
            ;;
        --mmc)
            checkparm $2
            MMC="$2"
	    if [[ "${MMC}" =~ "mmcblk" ]]
            then
	        PARTITION_PREFIX="p"
            fi
            find_issue
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
        --arch)
            checkparm $2
            ARCH_TYPE="$2"
            check_arch
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
        --addon)
            checkparm $2
            ADDON_TYPE="$2"
            check_addon_type
            ;;
        --svideo-ntsc)
            SVIDEO_NTSC=1
            ;;
        --svideo-pal)
            SVIDEO_PAL=1
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
        --use-beta-bootloader)
            USE_BETA_BOOTLOADER=1
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

 find_issue
 detect_software
 dl_bootloader
 dl_kernel_image
 dl_root_image

if [ "$DO_UBOOT" ];then
 setup_bootscripts
fi

 extract_zimage
 unmount_all_drive_partitions
 create_partitions
 populate_boot
 populate_rootfs

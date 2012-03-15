#!/bin/bash -e
#
# Copyright (c) 2009-2012 Robert Nelson <robertcnelson@gmail.com>
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

#REQUIREMENTS:
#uEnv.txt bootscript support

unset MMC
unset FIRMWARE
unset SERIAL_MODE
unset USE_BETA_BOOTLOADER
unset BETA_KERNEL
unset EXPERIMENTAL_KERNEL
unset USB_ROOTFS
unset PRINTK
unset SPL_BOOT
unset BOOTLOADER
unset SMSC95XX_MOREMEM
unset DD_UBOOT
unset KERNEL_DEB
unset ADDON

unset SVIDEO_NTSC
unset SVIDEO_PAL

GIT_VERSION=$(git rev-parse --short HEAD)
IN_VALID_UBOOT=1

MIRROR="http://rcn-ee.net/deb"
BACKUP_MIRROR="http://rcn-ee.homeip.net:81/dl/mirrors/deb"
unset RCNEEDOWN

#Defaults
ROOTFS_TYPE=ext4

DIST="f14"
ACTUAL_DIST="f14"
ARCH="armel"
DISTARCH="${DIST}-${ARCH}"

USER="root"
PASS="fedoraarm"

BOOT_LABEL=boot
ROOTFS_LABEL=rootfs
PARTITION_PREFIX=""

FEDORA_MIRROR="http://fedora.roving-it.com/"

F14_IMAGE="rootfs-f14-minimal-RC1.tar.bz2"
F14_MD5SUM="83f80747f76b23aa4464b0afd2f3c6db"

F17_SF_IMAGE="rootfs-f17-sfp-alpha1.tar.bz2"
F17_SF_MD5SUM="f1b61adf54f2f247312da4cefbdc7e3c"

F17_HF_IMAGE="rootfs-f17-hfp-alpha1.tar.bz2"
F17_HF_MD5SUM="a69b90c53c3dd60142c96f7d39df7659"

DIR="$PWD"
TEMPDIR=$(mktemp -d)

function is_element_of {
	testelt=$1
	for validelt in $2 ; do
		[ $testelt = $validelt ] && return 0
	done
	return 1
}

#########################################################################
#
#  Define valid "--rootfs" root filesystem types.
#
#########################################################################

VALID_ROOTFS_TYPES="ext2 ext3 ext4 btrfs"

function is_valid_rootfs_type {
	if is_element_of $1 "${VALID_ROOTFS_TYPES}" ] ; then
		return 0
	else
		return 1
	fi
}

#########################################################################
#
#  Define valid "--addon" values.
#
#########################################################################

VALID_ADDONS="pico ulcd"

function is_valid_addon {
	if is_element_of $1 "${VALID_ADDONS}" ] ; then
		return 0
	else
		return 1
	fi
}

function check_root {
if [[ $UID -ne 0 ]]; then
 echo "$0 must be run as sudo user or root"
 exit
fi
}

function find_issue {

check_root

#Software Qwerks

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

function check_for_command {
	if ! which "$1" > /dev/null ; then
		echo -n "You're missing command $1"
		NEEDS_COMMAND=1
		if [ -n "$2" ] ; then
			echo -n " (consider installing package $2)"
		fi
		echo
	fi
}

function detect_software {
	unset NEEDS_COMMAND

	check_for_command mkimage uboot-mkimage
	check_for_command mkfs.vfat dosfstools
	check_for_command wget wget
	check_for_command parted parted
	check_for_command dpkg dpkg
	check_for_command patch patch

	if [ "${NEEDS_COMMAND}" ] ; then
		echo ""
		echo "Your system is missing some dependencies"
		echo "Ubuntu/Debian: sudo apt-get install uboot-mkimage wget dosfstools parted"
		echo "Fedora: as root: yum install uboot-tools wget dosfstools parted dpkg patch"
		echo "Gentoo: emerge u-boot-tools wget dosfstools parted dpkg"
		echo ""
		exit
	fi
}

function rcn-ee_down_use_mirror {
	echo ""
	echo "rcn-ee.net down, switching to slower backup mirror"
	echo "-----------------------------"
	MIRROR=${BACKUP_MIRROR}
	RCNEEDOWN=1
}

function dl_bootloader {
 echo ""
 echo "Downloading Device's Bootloader"
 echo "-----------------------------"

 mkdir -p ${TEMPDIR}/dl/${DISTARCH}
 mkdir -p "${DIR}/dl/${DISTARCH}"

	echo "Checking rcn-ee.net to see if server is up and responding to pings..."
	ping -c 3 -w 10 www.rcn-ee.net | grep "ttl=" &> /dev/null || rcn-ee_down_use_mirror

 wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/tools/latest/bootloader

	if [ "$RCNEEDOWN" ];then
		sed -i -e "s/rcn-ee.net/rcn-ee.homeip.net:81/g" ${TEMPDIR}/dl/bootloader
		sed -i -e 's:81/deb/:81/dl/mirrors/deb/:g' ${TEMPDIR}/dl/bootloader
	fi

 if [ "$USE_BETA_BOOTLOADER" ];then
  ABI="ABX2"
 else
  ABI="ABI2"
 fi

 if [ "${SPL_BOOT}" ] ; then
  MLO=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:SPL" | awk '{print $2}')
  wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MLO}
  MLO=${MLO##*/}
  echo "SPL Bootloader: ${MLO}"
 fi

	UBOOT=$(cat ${TEMPDIR}/dl/bootloader | grep "${ABI}:${BOOTLOADER}:BOOT" | awk '{print $2}')
	wget --directory-prefix=${TEMPDIR}/dl/ ${UBOOT}
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

	#FIXME: use Wheezy kernel for now
	DISTARCH="wheezy-${ARCH}"

 if [ ! "${KERNEL_DEB}" ] ; then
  wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/${DISTARCH}/LATEST-${SUBARCH}

		if [ "$RCNEEDOWN" ] ; then
			sed -i -e "s/rcn-ee.net/rcn-ee.homeip.net:81/g" ${TEMPDIR}/dl/LATEST-${SUBARCH}
			sed -i -e 's:81/deb/:81/dl/mirrors/deb/:g' ${TEMPDIR}/dl/LATEST-${SUBARCH}
		fi

		FTP_DIR=$(cat ${TEMPDIR}/dl/LATEST-${SUBARCH} | grep "ABI:1 ${KERNEL_SEL}" | awk '{print $3}')
		if [ "$RCNEEDOWN" ] ; then
			#http://rcn-ee.homeip.net:81/dl/mirrors/deb/squeeze-armel/v3.2.6-x4/install-me.sh
			FTP_DIR=$(echo ${FTP_DIR} | awk -F'/' '{print $8}')
		else
			#http://rcn-ee.net/deb/squeeze-armel/v3.2.6-x4/install-me.sh
			FTP_DIR=$(echo ${FTP_DIR} | awk -F'/' '{print $6}')		;;
	mx53loco)
		SYSTEM="mx53loco"
		DO_UBOOT=1
		DD_UBOOT=1
		BOOTLOADER="MX53LOCO"
		SERIAL="ttymxc0"
		is_imx53
		fi
		KERNEL=$(echo ${FTP_DIR} | sed 's/v//')

		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/${DISTARCH}/${FTP_DIR}/
		ACTUAL_DEB_FILE=$(cat ${TEMPDIR}/dl/index.html | grep linux-image)
		ACTUAL_DEB_FILE=$(echo ${ACTUAL_DEB_FILE} | awk -F ".deb" '{print $1}')
		ACTUAL_DEB_FILE=${ACTUAL_DEB_FILE##*linux-image-}
		ACTUAL_DEB_FILE="linux-image-${ACTUAL_DEB_FILE}.deb"

  wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" ${MIRROR}/${DISTARCH}/v${KERNEL}/${ACTUAL_DEB_FILE}
  if [ "${DI_BROKEN_USE_CROSS}" ] ; then
   CROSS_DEB_FILE=$(echo ${ACTUAL_DEB_FILE} | sed 's:'${DIST}':cross:g')
   wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" ${MIRROR}/cross/v${KERNEL}/${CROSS_DEB_FILE}
  fi
 else
  KERNEL=${DEB_FILE}
  #Remove all "\" from file name.
  ACTUAL_DEB_FILE=$(echo ${DEB_FILE} | sed 's!.*/!!' | grep linux-image)
  cp -v ${DEB_FILE} "${DIR}/dl/${DISTARCH}/"
 fi

 #FIXME: reset back to fedora
 DISTARCH="${ACTUAL_DIST}-${ARCH}"

 echo "Using: ${ACTUAL_DEB_FILE}"
}

function dl_root_image {
	echo ""
	echo "Downloading Fedora Root Image"
	echo "-----------------------------"

	case "${DISTARCH}" in
	f14-armel)
		ROOTFS_MD5SUM=$F14_MD5SUM
		ROOTFS_IMAGE=$F14_IMAGE
		;;
	f17-armel)
		ROOTFS_MD5SUM=$F17_SF_MD5SUM
		ROOTFS_IMAGE=$F17_SF_IMAGE
		;;
	f17-armhf)
		ROOTFS_MD5SUM=$F17_HF_MD5SUM
		ROOTFS_IMAGE=$F17_HF_IMAGE
		;;
	esac

	if [ -f "${DIR}/dl/${DISTARCH}/${ROOTFS_IMAGE}" ]; then
		MD5SUM=$(md5sum "${DIR}/dl/${DISTARCH}/${ROOTFS_IMAGE}" | awk '{print $1}')
		if [ "=$ROOTFS_MD5SUM=" != "=$MD5SUM=" ]; then
			echo "Note: md5sum has changed: $MD5SUM"
			echo "-----------------------------"
			rm -f "${DIR}/dl/${DISTARCH}/${ROOTFS_IMAGE}" || true
			wget --directory-prefix="${DIR}/dl/${DISTARCH}" ${FEDORA_MIRROR}/${ROOTFS_IMAGE}
			NEW_MD5SUM=$(md5sum "${DIR}/dl/${DISTARCH}/${ROOTFS_IMAGE}" | awk '{print $1}')
			echo "Note: new md5sum $NEW_MD5SUM"
			echo "-----------------------------"
		fi
	else
		wget --directory-prefix="${DIR}/dl/${DISTARCH}" ${FEDORA_MIRROR}/${ROOTFS_IMAGE}
	fi
}

function dl_firmware {
	echo ""
	echo "Downloading Firmware"
	echo "-----------------------------"

	#TODO: We should just use the git tree blobs over distro versions
	if [ ! -f "${DIR}/dl/linux-firmware/.git/config" ]; then
		cd "${DIR}/dl/"
		git clone git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
		cd "${DIR}/"
	else
		cd "${DIR}/dl/linux-firmware"
		cat "${DIR}/dl/linux-firmware/.git/config" | grep dwmw2 && sed -i -e 's:dwmw2:firmware:g' "${DIR}/dl/linux-firmware/.git/config"
		git pull
		cd "${DIR}/"
	fi

	case "${DISTARCH}" in
	f14-armel)
		#V3.1 needs 1.9.4 for ar9170
		#wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" http://www.kernel.org/pub/linux/kernel/people/chr/carl9170/fw/1.9.4/carl9170-1.fw
		wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" http://rcn-ee.net/firmware/carl9170/1.9.4/carl9170-1.fw
		AR9170_FW="carl9170-1.fw"
		;;
	f17-armel)
		#V3.1 needs 1.9.4 for ar9170
		#wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" http://www.kernel.org/pub/linux/kernel/people/chr/carl9170/fw/1.9.4/carl9170-1.fw
		wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" http://rcn-ee.net/firmware/carl9170/1.9.4/carl9170-1.fw
		AR9170_FW="carl9170-1.fw"
		;;
	f17-armhf)
		#V3.1 needs 1.9.4 for ar9170
		#wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" http://www.kernel.org/pub/linux/kernel/people/chr/carl9170/fw/1.9.4/carl9170-1.fw
		wget -c --directory-prefix="${DIR}/dl/${DISTARCH}" http://rcn-ee.net/firmware/carl9170/1.9.4/carl9170-1.fw
		AR9170_FW="carl9170-1.fw"
		;;
	esac
}

function boot_uenv_txt_template {
	#(rcn-ee)in a way these are better then boot.scr
	#but each target is going to have a slightly different entry point..

	cat > ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
		bootfile=uImage
		bootinitrd=uInitrd
		address_uimage=UIMAGE_ADDR
		address_uinitrd=UINITRD_ADDR

		UENV_VRAM
		UENV_FB
		UENV_TIMING

		console=SERIAL_CONSOLE

		mmcroot=/dev/mmcblk0p2 ro
		mmcrootfstype=FINAL_FSTYPE rootwait fixrtc

		xyz_load_uimage=fatload mmc 0:1 \${address_uimage} \${bootfile}
		xyz_load_uinitrd=fatload mmc 0:1 \${address_uinitrd} \${bootinitrd}

		xyz_mmcboot=run xyz_load_uimage; echo Booting from mmc ...

		mmcargs=setenv bootargs console=\${console} \${optargs} VIDEO_DISPLAY root=\${mmcroot} rootfstype=\${mmcrootfstype} \${device_args}

	__EOF__

	if [ "x${ADDON}" == "xulcd" ] ; then
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			lcd1=i2c mw 40 00 00; i2c mw 40 04 80; i2c mw 40 0d 05
			uenvcmd=i2c dev 1; run lcd1; i2c dev 0

		__EOF__
	fi

	case "${SYSTEM}" in
	beagle_bx|beagle_cx)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			deviceargs=setenv device_args mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2} musb_hdrc.fifo_mode=5
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; bootm \${address_uimage} \${address_uinitrd}

		__EOF__
		;;
	beagle_xm)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			deviceargs=setenv device_args mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2}
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; bootm \${address_uimage} \${address_uinitrd}

		__EOF__
		;;
	igepv2|crane|panda|panda_es|mx53loco)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			deviceargs=setenv device_args
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; bootm \${address_uimage} \${address_uinitrd}

		__EOF__
		;;
	bone)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			deviceargs=setenv device_args ip=\${ip_method}
			mmc_load_uimage=run xyz_mmcboot; run bootargs_defaults; run deviceargs; run mmcargs; bootm \${address_uimage} \${address_uinitrd}

		__EOF__
		;;
	esac
}

function tweak_boot_scripts {
	# debug -|-
	# echo "NetInstall Boot Script: Generic"
	# echo "-----------------------------"
	# cat ${TEMPDIR}/bootscripts/netinstall.cmd

	if [ "x${ADDON}" == "xpico" ] ; then
		VIDEO_TIMING="640x480MR-16@60"
		KMS_VIDEO_RESOLUTION="640x48"
	fi

	if [ "x${ADDON}" == "xulcd" ] ; then
		VIDEO_TIMING="800x480MR-16@60"
		KMS_VIDEO_RESOLUTION="800x480"
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
 sed -i -e 's:FINAL_FSTYPE:'$ROOTFS_TYPE':g' ${TEMPDIR}/bootscripts/*.cmd

 if [ "${IS_OMAP}" ] ; then
  sed -i -e 's/ETH_ADDR //g' ${TEMPDIR}/bootscripts/*.cmd

  #defaultdisplay=VIDEO_OMAPFB_MODE
  #dvimode=VIDEO_TIMING
  #vram=VIDEO_OMAP_RAM
  sed -i -e 's:UENV_VRAM:vram=VIDEO_OMAP_RAM:g' ${TEMPDIR}/bootscripts/*.cmd
  sed -i -e 's:UENV_FB:defaultdisplay=VIDEO_OMAPFB_MODE:g' ${TEMPDIR}/bootscripts/*.cmd
  sed -i -e 's:UENV_TIMING:dvimode=VIDEO_TIMING:g' ${TEMPDIR}/bootscripts/*.cmd

  #vram=\${vram} omapfb.mode=\${defaultdisplay}:\${dvimode} omapdss.def_disp=\${defaultdisplay}
  sed -i -e 's:VIDEO_DISPLAY:TMP_VRAM TMP_OMAPFB TMP_OMAPDSS:g' ${TEMPDIR}/bootscripts/*.cmd
  sed -i -e 's:TMP_VRAM:'vram=\${vram}':g' ${TEMPDIR}/bootscripts/*.cmd
  sed -i -e 's/TMP_OMAPFB/'omapfb.mode=\${defaultdisplay}:\${dvimode}'/g' ${TEMPDIR}/bootscripts/*.cmd
  sed -i -e 's:TMP_OMAPDSS:'omapdss.def_disp=\${defaultdisplay}':g' ${TEMPDIR}/bootscripts/*.cmd

  FILE="*.cmd"
  if [ "$SERIAL_MODE" ];then
   #Set the Serial Console: console=CONSOLE
   sed -i -e 's:SERIAL_CONSOLE:'$SERIAL_CONSOLE':g' ${TEMPDIR}/bootscripts/*.cmd

   #omap3/4: In serial mode, NetInstall needs all traces of VIDEO removed..
   #drop: vram=\${vram}
   sed -i -e 's:'vram=\${vram}' ::g' ${TEMPDIR}/bootscripts/${FILE}

   #omapfb.mode=\${defaultdisplay}:\${dvimode} omapdss.def_disp=\${defaultdisplay}
   sed -i -e 's:'\${defaultdisplay}'::g' ${TEMPDIR}/bootscripts/${FILE}
   sed -i -e 's:'\${dvimode}'::g' ${TEMPDIR}/bootscripts/${FILE}
   #omapfb.mode=: omapdss.def_disp=
   sed -i -e "s/omapfb.mode=: //g" ${TEMPDIR}/bootscripts/${FILE}
   #uenv seems to have an extra space (beagle_xm)
   sed -i -e 's:omapdss.def_disp= ::g' ${TEMPDIR}/bootscripts/${FILE}
   sed -i -e 's:omapdss.def_disp=::g' ${TEMPDIR}/bootscripts/${FILE}
  else
   #Set the Video Console
   sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/*.cmd

   sed -i -e 's:VIDEO_OMAP_RAM:'$VIDEO_OMAP_RAM':g' ${TEMPDIR}/bootscripts/${FILE}
   sed -i -e 's:VIDEO_OMAPFB_MODE:'$VIDEO_OMAPFB_MODE':g' ${TEMPDIR}/bootscripts/${FILE}
   sed -i -e 's:VIDEO_TIMING:'$VIDEO_TIMING':g' ${TEMPDIR}/bootscripts/${FILE}
  fi
 fi

 if [ "${IS_IMX}" ] ; then
  sed -i -e 's/ETH_ADDR //g' ${TEMPDIR}/bootscripts/*.cmd

  #not used:
  sed -i -e 's:UENV_VRAM::g' ${TEMPDIR}/bootscripts/*.cmd

  #framebuffer=VIDEO_FB
  #dvimode=VIDEO_TIMING
  sed -i -e 's:UENV_FB:framebuffer=VIDEO_FB:g' ${TEMPDIR}/bootscripts/*.cmd
  sed -i -e 's:UENV_TIMING:dvimode=VIDEO_TIMING:g' ${TEMPDIR}/bootscripts/*.cmd

  #video=\${framebuffer}:${dvimode}
  sed -i -e 's/VIDEO_DISPLAY/'video=\${framebuffer}:\${dvimode}'/g' ${TEMPDIR}/bootscripts/*.cmd

  FILE="*.cmd"
  if [ "$SERIAL_MODE" ];then
   #Set the Serial Console: console=CONSOLE
   sed -i -e 's:SERIAL_CONSOLE:'$SERIAL_CONSOLE':g' ${TEMPDIR}/bootscripts/*.cmd

   #mx53: In serial mode, NetInstall needs all traces of VIDEO removed..

   #video=\${framebuffer}:\${dvimode}
   sed -i -e 's:'\${framebuffer}'::g' ${TEMPDIR}/bootscripts/${FILE}
   sed -i -e 's:'\${dvimode}'::g' ${TEMPDIR}/bootscripts/${FILE}
   #video=:
   sed -i -e "s/video=: //g" ${TEMPDIR}/bootscripts/${FILE}
   sed -i -e "s/video=://g" ${TEMPDIR}/bootscripts/${FILE}
  else
   #Set the Video Console
   #Set the Video Console
   sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/*.cmd

   sed -i -e 's:VIDEO_FB:'$VIDEO_FB':g' ${TEMPDIR}/bootscripts/${FILE}
   sed -i -e 's:VIDEO_TIMING:'$VIDEO_TIMING':g' ${TEMPDIR}/bootscripts/${FILE}
  fi
 fi

 if [ "$PRINTK" ];then
  sed -i 's/bootargs/bootargs earlyprintk/g' ${TEMPDIR}/bootscripts/*.cmd
 fi
}

function setup_bootscripts {
	mkdir -p ${TEMPDIR}/bootscripts/
	boot_uenv_txt_template
	tweak_boot_scripts
}

function extract_zimage {
 mkdir -p ${TEMPDIR}/kernel
 echo "Extracting Kernel Boot Image"
 #FIXME
 DISTARCH="wheezy-${ARCH}"
 if [ ! "${DI_BROKEN_USE_CROSS}" ] ; then
  dpkg -x "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" ${TEMPDIR}/kernel
 else
  dpkg -x "${DIR}/dl/${DISTARCH}/${CROSS_DEB_FILE}" ${TEMPDIR}/kernel
 fi
 #FIXME
 DISTARCH="${ACTUAL_DIST}-${ARCH}"
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
 echo "Debug: now using FDISK_FIRST_SECTOR over fdisk's depreciated method..."

 #With util-linux, 2.18+, the first sector is now 2048...
 FDISK_FIRST_SECTOR="1"
 if test $(fdisk -v | grep -o -E '2\.[0-9]+' | cut -d'.' -f2) -ge 18 ; then
  FDISK_FIRST_SECTOR="2048"
 fi

fdisk ${MMC} << END
n
p
1
${FDISK_FIRST_SECTOR}
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
 echo "Creating rootfs ${ROOTFS_TYPE} Partition"
 echo "-----------------------------"

 unset END_BOOT
 END_BOOT=$(LC_ALL=C parted -s ${MMC} unit mb print free | grep primary | awk '{print $3}' | cut -d "M" -f1)

 unset END_DEVICE
 END_DEVICE=$(LC_ALL=C parted -s ${MMC} unit mb print free | grep Free | tail -n 1 | awk '{print $2}' | cut -d "M" -f1)

 parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ${ROOTFS_TYPE} ${END_BOOT} ${END_DEVICE}
 sync

 if [ "$FDISK_DEBUG" ];then
  echo "Debug: ${ROOTFS_TYPE} Partition"
  echo "-----------------------------"
  echo "parted --script ${PARTED_ALIGN} ${MMC} mkpart primary ${ROOTFS_TYPE} ${END_BOOT} ${END_DEVICE}"
  fdisk -l ${MMC}
 fi
}

function format_boot_partition {
 echo "Formating Boot Partition"
 echo "-----------------------------"
 mkfs.vfat -F 16 ${MMC}${PARTITION_PREFIX}1 -n ${BOOT_LABEL}
}

function format_rootfs_partition {
 echo "Formating rootfs Partition as ${ROOTFS_TYPE}"
 echo "-----------------------------"
 mkfs.${ROOTFS_TYPE} ${MMC}${PARTITION_PREFIX}2 -L ${ROOTFS_LABEL}
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
		if [ -f ${TEMPDIR}/kernel/boot/${VMLINUZ} ] ; then
			LINUX_VER=$(ls ${TEMPDIR}/kernel/boot/${VMLINUZ} | awk -F'vmlinuz-' '{print $2}')
			echo "Using mkimage to create uImage"
			echo "-----------------------------"
			mkimage -A arm -O linux -T kernel -C none -a ${ZRELADD} -e ${ZRELADD} -n ${LINUX_VER} -d ${TEMPDIR}/kernel/boot/${VMLINUZ} ${TEMPDIR}/disk/uImage
			echo "Debug: zImage for future u-boot bootz support"
			cp -v ${TEMPDIR}/kernel/boot/${VMLINUZ} ${TEMPDIR}/disk/zImage
		fi

		if [ "${DO_UBOOT}" ] ; then
			echo "Copying uEnv.txt based boot scripts to Boot Partition"
			echo "-----------------------------"
			cp -v ${TEMPDIR}/bootscripts/normal.cmd ${TEMPDIR}/disk/uEnv.txt
			cat  ${TEMPDIR}/bootscripts/normal.cmd
			echo "-----------------------------"
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

if [ ! -f /boot/initrd.img-\$(uname -r) ] ; then
sudo update-initramfs -c -k \$(uname -r)
else
sudo update-initramfs -u -k \$(uname -r)
fi

if [ -f /boot/initrd.img-\$(uname -r) ] ; then
sudo mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-\$(uname -r) /boot/uboot/uInitrd
fi

if [ -f /boot/uboot/boot.cmd ] ; then
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d /boot/uboot/boot.cmd /boot/uboot/boot.scr
sudo cp /boot/uboot/boot.scr /boot/uboot/boot.ini
fi

if [ -f /boot/uboot/serial.cmd ] ; then
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d /boot/uboot/serial.cmd /boot/uboot/boot.scr
fi

if [ -f /boot/uboot/user.cmd ] ; then
sudo mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset Nand" -d /boot/uboot/user.cmd /boot/uboot/user.scr
fi

update_boot_files

cd ${TEMPDIR}/disk
sync
cd "${DIR}/"

 echo "Debug: Contents of Boot Partition"
 echo "-----------------------------"
 ls -lh ${TEMPDIR}/disk/
 echo "-----------------------------"

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

 if mount -t ${ROOTFS_TYPE} ${MMC}${PARTITION_PREFIX}2 ${TEMPDIR}/disk; then

 if [ -f "${DIR}/dl/${DISTARCH}/${ROOTFS_IMAGE}" ] ; then
   pv "${DIR}/dl/${DISTARCH}/${ROOTFS_IMAGE}" | sudo tar --numeric-owner --preserve-permissions -xjf - -C ${TEMPDIR}/disk/
   echo "Transfer of Base Rootfs Complete, syncing to disk"
   echo "-----------------------------"
   sync
   sync
 fi

 #FIXME:
 DISTARCH="wheezy-${ARCH}"
 dpkg -x "${DIR}/dl/${DISTARCH}/${ACTUAL_DEB_FILE}" ${TEMPDIR}/disk/
 #FIXME:
 DISTARCH="${ACTUAL_DIST}-${ARCH}"

	case "${DISTRO_TYPE}" in
	f14-armel)
		#LABEL="mmcblk2fs"          /                       ext3    defaults        1 1
		sed -i 's:LABEL="mmcblk2fs":/dev/mmcblk0p2:g' ${TEMPDIR}/disk/etc/fstab
		sed -i 's:ext3:'$ROOTFS_TYPE':g' ${TEMPDIR}/disk/etc/fstab
		;;
	f17-armel|f17-armhf)
		#LABEL="rootfs"          /                       ext4    defaults        1 1
		sed -i 's:LABEL="rootfs":/dev/mmcblk0p2:g' ${TEMPDIR}/disk/etc/fstab
		sed -i 's:ext4:'$ROOTFS_TYPE':g' ${TEMPDIR}/disk/etc/fstab
		;;
	esac

if [ "$BTROOTFS_TYPE_FSTAB" ] ; then
 sed -i 's/auto   errors=remount-ro/btrfs   defaults/g' ${TEMPDIR}/disk/etc/fstab
fi


	case "${DISTRO_TYPE}" in
	f14-armel)
		cat > ${TEMPDIR}/disk/etc/init/ttyO2.conf <<-__EOF__
			start on stopped rc RUNLEVEL=[2345]
			stop on starting runlevel [016]
			
			respawn
			exec /sbin/agetty /dev/ttyO2 115200
		__EOF__

		;;
	esac

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

 echo "Fedora: Adding root login over serial: ${SERIAL} to /etc/securetty"
 cat ${TEMPDIR}/disk/etc/securetty | grep ${SERIAL} || echo ${SERIAL} >> ${TEMPDIR}/disk/etc/securetty

	cat >> ${TEMPDIR}/disk/etc/rc.d/rc.sysinit <<-__EOF__
		#!/bin/sh

		if [ ! -f /lib/modules/\$(uname -r)/modules.dep ] ; then
			/sbin/depmod -a
		fi
	__EOF__

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
 cd "${DIR}/"

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
 echo "-----------------------------"
 echo "Default user: ${USER}"
 echo "Default pass: ${PASS}"
 echo "-----------------------------"
 echo "Reminder: Kernel/Modules: depmod will run on first, boot, so make sure to reboot once."
 echo "-----------------------------"
}

function check_mmc {

 FDISK=$(LC_ALL=C fdisk -l 2>/dev/null | grep "Disk ${MMC}" | awk '{print $2}')

 if test "-$FDISK-" = "-$MMC:-"
 then
  echo ""
  echo "I see..."
  echo "fdisk -l:"
  LC_ALL=C fdisk -l 2>/dev/null | grep "Disk /dev/" --color=never
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
  LC_ALL=C fdisk -l 2>/dev/null | grep "Disk /dev/" --color=never
  echo ""
  echo "mount:"
  mount | grep -v none | grep "/dev/" --color=never
  echo ""
  exit
 fi
}

function is_omap {
	IS_OMAP=1
	SPL_BOOT=1
	SUBARCH="omap"

	UIMAGE_ADDR="0x80300000"
	UINITRD_ADDR="0x81600000"

	ZRELADD="0x80008000"

	SERIAL_CONSOLE="${SERIAL},115200n8"

	VIDEO_CONSOLE="console=tty0"

	#Older DSS2 omapfb framebuffer driver:
	VIDEO_DRV="omapfb.mode=dvi"
	VIDEO_OMAP_RAM="12MB"
	VIDEO_OMAPFB_MODE="dvi"
	VIDEO_TIMING="1280x720MR-16@60"

	#KMS Video Options (overrides when edid fails)
	# From: ls /sys/class/drm/
	# Unknown-1 might be s-video..
	KMS_VIDEO_RESOLUTION="1280x720"
	KMS_VIDEOA="video=DVI-D-1"
	unset KMS_VIDEOB
}

function is_imx53 {
 IS_IMX=1
 UIMAGE_ADDR="0x70800000"
 UINITRD_ADDR="0x72100000"
 SERIAL_CONSOLE="${SERIAL},115200"
 ZRELADD="0x70008000"
 SUBARCH="imx"
 VIDEO_CONSOLE="console=tty0"
 VIDEO_FB="mxcdi1fb"
 VIDEO_TIMING="RGB24,1280x720M@60"
}

function check_uboot_type {
	unset DO_UBOOT
	unset IN_VALID_UBOOT

	case "${UBOOT_TYPE}" in
	beagle_bx)
		SYSTEM="beagle_bx"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_BX"
		SERIAL="ttyO2"
		is_omap
		;;
	beagle_cx)
		SYSTEM="beagle_cx"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_CX"
		SERIAL="ttyO2"
		is_omap
		;;
	beagle_xm)
		SYSTEM="beagle_xm"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_XM"
		SERIAL="ttyO2"
		is_omap
		;;
	bone)
		SYSTEM="bone"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBONE_A"
		SERIAL="ttyO0"
		is_omap

		SUBARCH="omap-psp"
		SERIAL_MODE=1
		unset KMS_VIDEOA
		;;
	igepv2)
		SYSTEM="igepv2"
		DO_UBOOT=1
		BOOTLOADER="IGEP00X0"
		SERIAL="ttyO2"
		is_omap

		SERIAL_MODE=1
		;;
	panda)
		SYSTEM="panda"
		DO_UBOOT=1
		BOOTLOADER="PANDABOARD"
		SMSC95XX_MOREMEM=1
		SERIAL="ttyO2"
		is_omap
		VIDEO_OMAP_RAM="16MB"
		KMS_VIDEOB="video=HDMI-A-1"
		;;
	panda_es)
		SYSTEM="panda_es"
		DO_UBOOT=1
		BOOTLOADER="PANDABOARD_ES"
		SMSC95XX_MOREMEM=1
		SERIAL="ttyO2"
		is_omap
		VIDEO_OMAP_RAM="16MB"
		KMS_VIDEOB="video=HDMI-A-1"
		;;
	crane)
		SYSTEM="crane"
		DO_UBOOT=1
		BOOTLOADER="CRANEBOARD"
		SERIAL="ttyO2"
		is_omap

		BETA_KERNEL=1
		SERIAL_MODE=1
		;;
	mx53loco)
		SYSTEM="mx53loco"
		DO_UBOOT=1
		DD_UBOOT=1
		BOOTLOADER="MX53LOCO"
		SERIAL="ttymxc0"
		is_imx53
		SUBARCH="imx"
		;;
	*)
		IN_VALID_UBOOT=1
		cat <<-__EOF__
			-----------------------------
			ERROR: This script does not currently recognize the selected: [--uboot ${UBOOT_TYPE}] option..
			Please rerun $(basename $0) with a valid [--uboot <device>] option from the list below:
			-----------------------------
			-Supported TI Devices:-------
			beagle_bx - <BeagleBoard Ax/Bx>
			beagle_cx - <BeagleBoard Cx>
			beagle_xm - <BeagleBoard xMA/B/C>
			bone - <BeagleBone Ax>
			igepv2 - <serial mode only>
			panda - <PandaBoard Ax>
			panda_es - <PandaBoard ES>
			-Supported Freescale Devices:
			mx53loco - <Quick Start Board>
			-----------------------------
		__EOF__
		exit
		;;
	esac
}

function check_distro {
	unset IN_VALID_DISTRO

	case "${DISTRO_TYPE}" in
	f14-armel|f14-sfp|f14)
		DIST=f14
		ARCH=armel
		ACTUAL_DIST="${DIST}"
		USER="root"
		PASS="fedoraarm"
		;;
	f17-armel|f17-sfp)
		DIST=f17
		ARCH=armel
		ACTUAL_DIST="${DIST}"
		USER="root"
		PASS="fedoraarm"
		;;
	f17-armhf|f17-hfp)
		DIST=f17
		ARCH=armhf
		ACTUAL_DIST="${DIST}"
		USER="root"
		PASS="fedoraarm"
		;;
	*)
		IN_VALID_DISTRO=1
		usage
		;;
	esac

	DISTARCH="${DIST}-${ARCH}"
}

function usage {
    echo "usage: sudo $(basename $0) --mmc /dev/sdX --uboot <dev board>"
cat <<EOF

Script Version git: ${GIT_VERSION}
-----------------------------
Bugs email: "bugs at rcn-ee.com"

Required Options:
--mmc </dev/sdX>

--uboot <dev board>
    (omap)
    beagle_bx - <BeagleBoard Ax/Bx>
    beagle_cx - <BeagleBoard Cx>
    beagle_xm - <BeagleBoard xMA/B/C>
    bone - <BeagleBone Ax>
    igepv2 - <serial mode only>
    panda - <PandaBoard Ax>
    panda_es - <PandaBoard ES>

    (freescale)
    mx53loco

Optional:
--distro <distro>
    Fedora:
      f14 <default>

--addon <additional peripheral device>
    pico
    ulcd <beagle xm>

--rootfs <fs_type>
    ext2
    ext3
    ext4 - <set as default>
    btrfs

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
        --firmware)
            FIRMWARE=1
            ;;
        --serial-mode)
            SERIAL_MODE=1
            ;;
        --addon)
            checkparm $2
            ADDON=$2
            ;;
        --rootfs)
            checkparm $2
            ROOTFS_TYPE="$2"
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

if [ ! "${MMC}" ] ; then
	echo "ERROR: --mmc undefined"
	usage
fi

if [ "$IN_VALID_UBOOT" ] ; then
	echo "ERROR: --uboot undefined"
	usage
fi

if ! is_valid_rootfs_type ${ROOTFS_TYPE} ; then
	echo "ERROR: ${ROOTFS_TYPE} is not a valid root filesystem type"
	echo "Valid types: ${VALID_ROOTFS_TYPES}"
	exit
fi

if [ "${ROOTFS_TYPE}" = "btrfs" ] ; then
	BTRFS_FSTAB=1
fi

if [ -n "${ADDON}" ] ; then
	if ! is_valid_addon ${ADDON} ; then
		echo "ERROR: ${ADDON} is not a valid addon type"
		echo "-----------------------------"
		echo "Supported --addon options:"
		echo "    pico"
		echo "    ulcd <for the beagleboard xm>"
		exit
	fi
fi

 echo ""
 echo "Script Version git: ${GIT_VERSION}"
 echo "-----------------------------"

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


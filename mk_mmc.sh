#!/bin/bash
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
#
# Latest can be found at:
# http://github.com/RobertCNelson/fedora-media-builder/blob/master/mk_mmc.sh

#REQUIREMENTS:
#uEnv.txt bootscript support

MIRROR="http://rcn-ee.net/deb"
BACKUP_MIRROR="http://rcn-ee.homeip.net:81/dl/mirrors/deb"

BOOT_LABEL="boot"
PARTITION_PREFIX=""

unset MMC
unset USE_BETA_BOOTLOADER
unset DD_UBOOT
unset ADDON

#Common KMS:
unset USE_KMS
unset KMS_OVERRIDE

unset FIRMWARE
unset SERIAL_MODE
unset BETA_KERNEL
unset EXPERIMENTAL_KERNEL
unset USB_ROOTFS
unset KERNEL_DEB

unset SVIDEO_NTSC
unset SVIDEO_PAL

GIT_VERSION=$(git rev-parse --short HEAD)
IN_VALID_UBOOT=1

#Defaults
ROOTFS_TYPE="ext4"
ROOTFS_LABEL="rootfs"

#use wheezy kernel debs
DEBIAN="wheezy"

DIST="f14"
ARCH="armel"
DISTRO="${DIST}-${ARCH}"
DEBARCH="${DEBIAN}-${ARCH}"

USER="root"
PASS="fedoraarm"

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
	check_for_command pv pv

	if [ "${NEEDS_COMMAND}" ] ; then
		echo ""
		echo "Your system is missing some dependencies"
		echo "Ubuntu/Debian: sudo apt-get install uboot-mkimage wget pv dosfstools parted"
		echo "Fedora: as root: yum install uboot-tools wget pv dosfstools parted dpkg patch"
		echo "Gentoo: emerge u-boot-tools wget pv dosfstools parted dpkg"
		echo ""
		exit
	fi

	#Check for gnu-fdisk
	#FIXME: GNU Fdisk seems to halt at "Using /dev/xx" when trying to script it..
	if fdisk -v | grep "GNU Fdisk" >/dev/null ; then
		echo "Sorry, this script currently doesn't work with GNU Fdisk."
		echo "Install the version of fdisk from your distribution's util-linux package."
		exit
	fi

	unset PARTED_ALIGN
	if parted -v | grep parted | grep 2.[1-3] >/dev/null ; then
		PARTED_ALIGN="--align cylinder"
	fi
}

function rcn-ee_down_use_mirror {
	echo "rcn-ee.net down, switching to slower backup mirror"
	echo "-----------------------------"
	MIRROR=${BACKUP_MIRROR}
	RCNEEDOWN=1
}

function dl_bootloader {
 echo ""
 echo "Downloading Device's Bootloader"
 echo "-----------------------------"

 mkdir -p ${TEMPDIR}/dl/${DISTRO}
 mkdir -p "${DIR}/dl/${DISTRO}"

	unset RCNEEDOWN
	echo "attempting to use rcn-ee.net for dl files [10 second time out]..."
	wget -T 10 -t 1 --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/tools/latest/bootloader

	if [ ! -f ${TEMPDIR}/dl/bootloader ] ; then
		rcn-ee_down_use_mirror
		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/tools/latest/bootloader
	fi

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

	if [ "${BETA_KERNEL}" ] ; then
		KERNEL_SEL="TESTING"
	fi

	if [ "${EXPERIMENTAL_KERNEL}" ] ; then
		KERNEL_SEL="EXPERIMENTAL"
	fi

	mkdir -p ${DIR}/dl/${DEBARCH}

	if [ ! "${KERNEL_DEB}" ] ; then
		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/${DEBARCH}/LATEST-${SUBARCH}

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
			FTP_DIR=$(echo ${FTP_DIR} | awk -F'/' '{print $6}')
		fi
		KERNEL=$(echo ${FTP_DIR} | sed 's/v//')

		wget --no-verbose --directory-prefix=${TEMPDIR}/dl/ ${MIRROR}/${DEBARCH}/${FTP_DIR}/
		ACTUAL_DEB_FILE=$(cat ${TEMPDIR}/dl/index.html | grep linux-image)
		ACTUAL_DEB_FILE=$(echo ${ACTUAL_DEB_FILE} | awk -F ".deb" '{print $1}')
		ACTUAL_DEB_FILE=${ACTUAL_DEB_FILE##*linux-image-}
		ACTUAL_DEB_FILE="linux-image-${ACTUAL_DEB_FILE}.deb"

		wget -c --directory-prefix="${DIR}/dl/${DEBARCH}" ${MIRROR}/${DEBARCH}/v${KERNEL}/${ACTUAL_DEB_FILE}
	else
		KERNEL=${DEB_FILE}
		#Remove all "\" from file name.
		ACTUAL_DEB_FILE=$(echo ${DEB_FILE} | sed 's!.*/!!' | grep linux-image)
		cp -v ${DEB_FILE} "${DIR}/dl/${DEBARCH}/"
	fi

	echo "Using: ${ACTUAL_DEB_FILE}"
}

function dl_root_image {
	echo ""
	echo "Downloading Fedora Root Image"
	echo "-----------------------------"

	case "${DISTRO}" in
	f14-armel)
		ROOTFS_MD5SUM=$F14_MD5SUM
		ROOTFS_IMAGE=$F14_IMAGE
		FEDORA_MIRROR="http://fedora.roving-it.com/"
		;;
	f17-armel)
		ROOTFS_MD5SUM=$F17_SF_MD5SUM
		ROOTFS_IMAGE=$F17_SF_IMAGE
		FEDORA_MIRROR="http://fedora.roving-it.com/"
		;;
	f17-armhf)
		ROOTFS_MD5SUM=$F17_HF_MD5SUM
		ROOTFS_IMAGE=$F17_HF_IMAGE
		FEDORA_MIRROR="http://fedora.roving-it.com/"
		;;
	esac

	if [ -f "${DIR}/dl/${DISTRO}/${ROOTFS_IMAGE}" ]; then
		MD5SUM=$(md5sum "${DIR}/dl/${DISTRO}/${ROOTFS_IMAGE}" | awk '{print $1}')
		if [ "x${ROOTFS_MD5SUM}" != "x${MD5SUM}" ]; then
			echo "Note: md5sum has changed: $MD5SUM"
			echo "-----------------------------"
			rm -f "${DIR}/dl/${DISTRO}/${ROOTFS_IMAGE}" || true
			wget --directory-prefix="${DIR}/dl/${DISTRO}" ${FEDORA_MIRROR}/${ROOTFS_IMAGE}
			NEW_MD5SUM=$(md5sum "${DIR}/dl/${DISTRO}/${ROOTFS_IMAGE}" | awk '{print $1}')
			echo "Note: new md5sum $NEW_MD5SUM"
			echo "-----------------------------"
		fi
	else
		wget --directory-prefix="${DIR}/dl/${DISTRO}" ${FEDORA_MIRROR}/${ROOTFS_IMAGE}
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

	case "${DISTRO}" in
	f14-armel)
		#V3.1 needs 1.9.4 for ar9170
		#wget -c --directory-prefix="${DIR}/dl/${DISTRO}" http://www.kernel.org/pub/linux/kernel/people/chr/carl9170/fw/1.9.4/carl9170-1.fw
		wget -c --directory-prefix="${DIR}/dl/${DISTRO}" http://rcn-ee.net/firmware/carl9170/1.9.4/carl9170-1.fw
		AR9170_FW="carl9170-1.fw"
		;;
	f17-armel)
		#V3.1 needs 1.9.4 for ar9170
		#wget -c --directory-prefix="${DIR}/dl/${DISTRO}" http://www.kernel.org/pub/linux/kernel/people/chr/carl9170/fw/1.9.4/carl9170-1.fw
		wget -c --directory-prefix="${DIR}/dl/${DISTRO}" http://rcn-ee.net/firmware/carl9170/1.9.4/carl9170-1.fw
		AR9170_FW="carl9170-1.fw"
		;;
	f17-armhf)
		#V3.1 needs 1.9.4 for ar9170
		#wget -c --directory-prefix="${DIR}/dl/${DISTRO}" http://www.kernel.org/pub/linux/kernel/people/chr/carl9170/fw/1.9.4/carl9170-1.fw
		wget -c --directory-prefix="${DIR}/dl/${DISTRO}" http://rcn-ee.net/firmware/carl9170/1.9.4/carl9170-1.fw
		AR9170_FW="carl9170-1.fw"
		;;
	esac
}

function boot_uenv_txt_template {
	#(rcn-ee)in a way these are better then boot.scr
	#but each target is going to have a slightly different entry point..

	if [ ! "${USE_KMS}" ] ; then
		cat > ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			UENV_VRAM
			UENV_FB
			UENV_TIMING
		__EOF__
	fi

	if [ ! "${USE_ZIMAGE}" ] ; then
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			bootfile=uImage
			bootinitrd=uInitrd
			boot=bootm

		__EOF__
	else
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			bootfile=zImage
			bootinitrd=initrd.img
			boot=bootz

		__EOF__
	fi

	cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
		address_image=IMAGE_ADDR
		address_initrd=INITRD_ADDR

		console=SERIAL_CONSOLE

		mmcroot=/dev/mmcblk0p2 ro
		mmcrootfstype=FINAL_FSTYPE rootwait fixrtc

		xyz_load_image=fatload mmc 0:1 \${address_image} \${bootfile}
		xyz_load_initrd=fatload mmc 0:1 \${address_initrd} \${bootinitrd}

		xyz_mmcboot=run xyz_load_image; echo Booting from mmc ...

		mmcargs=setenv bootargs console=\${console} \${optargs} VIDEO_DISPLAY root=\${mmcroot} rootfstype=\${mmcrootfstype} \${device_args}

	__EOF__

	case "${SYSTEM}" in
	beagle_bx|beagle_cx)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			deviceargs=setenv device_args mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2} musb_hdrc.fifo_mode=5
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image}

		__EOF__
		;;
	beagle_xm)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			deviceargs=setenv device_args mpurate=\${mpurate} buddy=\${buddy} buddy2=\${buddy2}
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image}

		__EOF__
		;;
	crane|igepv2|mx51evk|mx53loco|panda|panda_es)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			optargs=VIDEO_CONSOLE
			deviceargs=setenv device_args
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image}

		__EOF__
		;;
	bone)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			deviceargs=setenv device_args ip=\${ip_method}
			mmc_load_uimage=run xyz_mmcboot; run bootargs_defaults; run deviceargs; run mmcargs; \${boot} \${address_image}

		__EOF__
		;;
	bone_zimage)
		cat >> ${TEMPDIR}/bootscripts/normal.cmd <<-__EOF__
			deviceargs=setenv device_args ip=\${ip_method}
			mmc_load_uimage=run xyz_mmcboot; run bootargs_defaults; run deviceargs; run mmcargs; \${boot} \${address_image}
			loaduimage=run xyz_mmcboot; run deviceargs; run mmcargs; \${boot} \${address_image}

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
		KMS_OVERRIDE=1
		KMS_VIDEOA="video=DVI-D-1"
		KMS_VIDEO_RESOLUTION="640x480"
	fi

	if [ "x${ADDON}" == "xulcd" ] ; then
		VIDEO_TIMING="800x480MR-16@60"
		KMS_OVERRIDE=1
		KMS_VIDEOA="video=DVI-D-1"
		KMS_VIDEO_RESOLUTION="800x480"
	fi

	if [ "${SVIDEO_NTSC}" ] ; then
		VIDEO_TIMING="ntsc"
		VIDEO_OMAPFB_MODE="tv"
		##FIXME need to figure out KMS Options
	fi

	if [ "${SVIDEO_PAL}" ] ; then
		VIDEO_TIMING="pal"
		VIDEO_OMAPFB_MODE="tv"
		##FIXME need to figure out KMS Options
	fi

	ALL="*.cmd"
	#Set kernel boot address
	sed -i -e 's:IMAGE_ADDR:'$IMAGE_ADDR':g' ${TEMPDIR}/bootscripts/${ALL}

	#Set initrd boot address
	sed -i -e 's:INITRD_ADDR:'$INITRD_ADDR':g' ${TEMPDIR}/bootscripts/${ALL}

	#Set the Serial Console
	sed -i -e 's:SERIAL_CONSOLE:'$SERIAL_CONSOLE':g' ${TEMPDIR}/bootscripts/${ALL}

	#Set filesystem type
	sed -i -e 's:FINAL_FSTYPE:'$ROOTFS_TYPE':g' ${TEMPDIR}/bootscripts/${ALL}

	if [ "${HAS_OMAPFB_DSS2}" ] && [ ! "${SERIAL_MODE}" ] ; then
		#UENV_VRAM -> vram=12MB
		sed -i -e 's:UENV_VRAM:vram=VIDEO_OMAP_RAM:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:VIDEO_OMAP_RAM:'$VIDEO_OMAP_RAM':g' ${TEMPDIR}/bootscripts/${ALL}

		#UENV_FB -> defaultdisplay=dvi
		sed -i -e 's:UENV_FB:defaultdisplay=VIDEO_OMAPFB_MODE:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:VIDEO_OMAPFB_MODE:'$VIDEO_OMAPFB_MODE':g' ${TEMPDIR}/bootscripts/${ALL}

		#UENV_TIMING -> dvimode=1280x720MR-16@60
		sed -i -e 's:UENV_TIMING:dvimode=VIDEO_TIMING:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:VIDEO_TIMING:'$VIDEO_TIMING':g' ${TEMPDIR}/bootscripts/${ALL}

		#optargs=VIDEO_CONSOLE -> optargs=console=tty0
		sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/${ALL}

		#Setting up:
		#vram=\${vram} omapfb.mode=\${defaultdisplay}:\${dvimode} omapdss.def_disp=\${defaultdisplay}
		sed -i -e 's:VIDEO_DISPLAY:TMP_VRAM TMP_OMAPFB TMP_OMAPDSS:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:TMP_VRAM:'vram=\${vram}':g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's/TMP_OMAPFB/'omapfb.mode=\${defaultdisplay}:\${dvimode}'/g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:TMP_OMAPDSS:'omapdss.def_disp=\${defaultdisplay}':g' ${TEMPDIR}/bootscripts/${ALL}
	fi

	if [ "${HAS_IMX_BLOB}" ] && [ ! "${SERIAL_MODE}" ] ; then
		#not used:
		sed -i -e 's:UENV_VRAM::g' ${TEMPDIR}/bootscripts/${ALL}

		#framebuffer=VIDEO_FB
		sed -i -e 's:UENV_FB:framebuffer=VIDEO_FB:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:VIDEO_FB:'$VIDEO_FB':g' ${TEMPDIR}/bootscripts/${ALL}

		#dvimode=VIDEO_TIMING
		sed -i -e 's:UENV_TIMING:dvimode=VIDEO_TIMING:g' ${TEMPDIR}/bootscripts/${ALL}
		sed -i -e 's:VIDEO_TIMING:'$VIDEO_TIMING':g' ${TEMPDIR}/bootscripts/${ALL}

		#optargs=VIDEO_CONSOLE -> optargs=console=tty0
		sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/${ALL}

		#video=\${framebuffer}:${dvimode}
		sed -i -e 's/VIDEO_DISPLAY/'video=\${framebuffer}:\${dvimode}'/g' ${TEMPDIR}/bootscripts/${ALL}
	fi

	if [ "${USE_KMS}" ] && [ ! "${SERIAL_MODE}" ] ; then
		#optargs=VIDEO_CONSOLE
		sed -i -e 's:VIDEO_CONSOLE:console=tty0:g' ${TEMPDIR}/bootscripts/${ALL}

		if [ "${KMS_OVERRIDE}" ] ; then
			sed -i -e 's/VIDEO_DISPLAY/'${KMS_VIDEOA}:${KMS_VIDEO_RESOLUTION}'/g' ${TEMPDIR}/bootscripts/${ALL}
		else
			sed -i -e 's:VIDEO_DISPLAY ::g' ${TEMPDIR}/bootscripts/${ALL}
		fi
	fi

	if [ "${SERIAL_MODE}" ] ; then
		#In pure serial mode, remove all traces of VIDEO
		if [ ! "${USE_KMS}" ] ; then
			sed -i -e 's:UENV_VRAM::g' ${TEMPDIR}/bootscripts/${ALL}
			sed -i -e 's:UENV_FB::g' ${TEMPDIR}/bootscripts/${ALL}
			sed -i -e 's:UENV_TIMING::g' ${TEMPDIR}/bootscripts/${ALL}
		fi
		sed -i -e 's:VIDEO_DISPLAY ::g' ${TEMPDIR}/bootscripts/${ALL}

		#optargs=VIDEO_CONSOLE -> optargs=
		sed -i -e 's:VIDEO_CONSOLE::g' ${TEMPDIR}/bootscripts/${ALL}
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
	dpkg -x "${DIR}/dl/${DEBARCH}/${ACTUAL_DEB_FILE}" ${TEMPDIR}/kernel
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

	fdisk ${MMC} <<-__EOF__
		n
		p
		1

		+64M
		t
		e
		p
		w
	__EOF__

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

	mkdir -p ${TEMPDIR}/disk

	if mount -t vfat ${MMC}${PARTITION_PREFIX}1 ${TEMPDIR}/disk; then

		mkdir -p ${TEMPDIR}/disk/backup
		if [ "${SPL_BOOT}" ] ; then
			if [ -f ${TEMPDIR}/dl/${MLO} ]; then
				cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/MLO
				cp -v ${TEMPDIR}/dl/${MLO} ${TEMPDIR}/disk/backup/MLO
				echo "-----------------------------"
			fi
		fi

		if [ ! "${DD_UBOOT}" ] ; then
			if [ -f ${TEMPDIR}/dl/${UBOOT} ]; then
				if echo ${UBOOT} | grep img > /dev/null 2>&1;then
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.img
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/backup/u-boot.img
					echo "-----------------------------"
				else
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/u-boot.bin
					cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/backup/u-boot.bin
					echo "-----------------------------"
				fi
			fi
		fi

		VMLINUZ="vmlinuz-*"
		if [ -f ${TEMPDIR}/kernel/boot/${VMLINUZ} ] ; then
			LINUX_VER=$(ls ${TEMPDIR}/kernel/boot/${VMLINUZ} | awk -F'vmlinuz-' '{print $2}')
			if [ ! "${USE_ZIMAGE}" ] ; then
				echo "Using mkimage to create uImage"
				mkimage -A arm -O linux -T kernel -C none -a ${ZRELADD} -e ${ZRELADD} -n ${LINUX_VER} -d ${TEMPDIR}/kernel/boot/${VMLINUZ} ${TEMPDIR}/disk/uImage
				echo "-----------------------------"
			fi
			echo "Copying Kernel image:"
			cp -v ${TEMPDIR}/kernel/boot/${VMLINUZ} ${TEMPDIR}/disk/zImage
			echo "-----------------------------"
		fi

		echo "Copying uEnv.txt based boot scripts to Boot Partition"
		echo "-----------------------------"
		cp -v ${TEMPDIR}/bootscripts/normal.cmd ${TEMPDIR}/disk/uEnv.txt
		cp -v ${TEMPDIR}/bootscripts/normal.cmd ${TEMPDIR}/disk/backup/uEnv.txt
		echo "-----------------------------"
		cat  ${TEMPDIR}/bootscripts/normal.cmd
		echo "-----------------------------"

cat > ${TEMPDIR}/readme.txt <<script_readme

These can be run from anywhere, but just in case change to "cd /boot/uboot"

Tools:

 "./tools/update_boot_files.sh"

Updated with a custom uImage and modules or modified the boot.cmd/user.com files with new boot args? Run "./tools/update_boot_files.sh" to regenerate all boot files...

script_readme

	cat > ${TEMPDIR}/update_boot_files.sh <<-__EOF__
		#!/bin/sh

		if ! id | grep -q root; then
		        echo "must be run as root"
		        exit
		fi

		cd /boot/uboot
		mount -o remount,rw /boot/uboot

		if [ ! -f /boot/initrd.img-\$(uname -r) ] ; then
		        update-initramfs -c -k \$(uname -r)
		else
		        update-initramfs -u -k \$(uname -r)
		fi

		if [ -f /boot/initrd.img-\$(uname -r) ] ; then
		        cp -v /boot/initrd.img-\$(uname -r) /boot/uboot/initrd.img
		fi

		#legacy uImage support:
		if [ -f /boot/uboot/uImage ] ; then
		        if [ -f /boot/initrd.img-\$(uname -r) ] ; then
		                mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n initramfs -d /boot/initrd.img-\$(uname -r) /boot/uboot/uInitrd
		        fi
		        if [ -f /boot/uboot/boot.cmd ] ; then
		                mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d /boot/uboot/boot.cmd /boot/uboot/boot.scr
		                cp -v /boot/uboot/boot.scr /boot/uboot/boot.ini
		        fi
		        if [ -f /boot/uboot/serial.cmd ] ; then
		                mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Boot Script" -d /boot/uboot/serial.cmd /boot/uboot/boot.scr
		        fi
		        if [ -f /boot/uboot/user.cmd ] ; then
		                mkimage -A arm -O linux -T script -C none -a 0 -e 0 -n "Reset Nand" -d /boot/uboot/user.cmd /boot/uboot/user.scr
		        fi
		fi

	__EOF__


	cat > ${TEMPDIR}/suspend_mount_debug.sh <<-__EOF__
		#!/bin/bash

		if ! id | grep -q root; then
		        echo "must be run as root"
		        exit
		fi

		mkdir -p /debug
		mount -t debugfs debugfs /debug

	__EOF__

	cat > ${TEMPDIR}/suspend.sh <<-__EOF__
		#!/bin/bash

		if ! id | grep -q root; then
		        echo "must be run as root"
		        exit
		fi

		echo mem > /sys/power/state

	__EOF__

	mkdir -p ${TEMPDIR}/disk/tools
	cp -v ${TEMPDIR}/readme.txt ${TEMPDIR}/disk/tools/readme.txt

	cp -v ${TEMPDIR}/suspend_mount_debug.sh ${TEMPDIR}/disk/tools/
	chmod +x ${TEMPDIR}/disk/tools/suspend_mount_debug.sh

	cp -v ${TEMPDIR}/suspend.sh ${TEMPDIR}/disk/tools/
	chmod +x ${TEMPDIR}/disk/tools/suspend.sh

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

		if [ -f "${DIR}/dl/${DISTRO}/${ROOTFS_IMAGE}" ] ; then

			echo "${DIR}/dl/${DISTRO}/${ROOTFS_IMAGE}" | grep ".bz2" && DECOM="xjf"
			echo "${DIR}/dl/${DISTRO}/${ROOTFS_IMAGE}" | grep ".xz" && DECOM="xJf"

			pv "${DIR}/dl/${DISTRO}/${ROOTFS_IMAGE}" | tar --numeric-owner --preserve-permissions -${DECOM} - -C ${TEMPDIR}/disk/
			echo "Transfer of Base Rootfs is Complete, now syncing to disk..."
			sync
			sync
			echo "-----------------------------"
		fi

	dpkg -x "${DIR}/dl/${DEBARCH}/${ACTUAL_DEB_FILE}" ${TEMPDIR}/disk/

	case "${DISTRO}" in
	f14-armel)
		#LABEL="mmcblk2fs"          /                       ext3    defaults        1 1
		sed -i 's:LABEL="mmcblk2fs":/dev/mmcblk0p2:g' ${TEMPDIR}/disk/etc/fstab
		sed -i 's:ext3:'$ROOTFS_TYPE':g' ${TEMPDIR}/disk/etc/fstab

		cat > ${TEMPDIR}/disk/etc/init/ttyO2.conf <<-__EOF__
			start on stopped rc RUNLEVEL=[2345]
			stop on runlevel [016]
			
			instance ttyO2
			respawn
			pre-start exec /sbin/securetty ttyO2
			exec /sbin/agetty /dev/ttyO2 115200

		__EOF__

		;;
	f17-armel|f17-armhf)
		#LABEL="rootfs"          /                       ext4    defaults        1 1
		sed -i 's:LABEL="rootfs":/dev/mmcblk0p2:g' ${TEMPDIR}/disk/etc/fstab
		sed -i 's:ext4:'$ROOTFS_TYPE':g' ${TEMPDIR}/disk/etc/fstab
		;;
	esac

		if [ "${BTRFS_FSTAB}" ] ; then
			sed -i 's/auto   errors=remount-ro/btrfs   defaults/g' ${TEMPDIR}/disk/etc/fstab
		fi

	#So most of the default images use ttyO2, but the bone uses ttyO0, need to find a better way..
	if [ "x${SERIAL}" != "xttyO2" ] ; then 
		if [ -f ${TEMPDIR}/disk/etc/init/ttyO2.conf ] ; then
			echo "Fedora: Serial Login: fixing /etc/init/ttyO2.conf to use ${SERIAL}"
			echo "-----------------------------"
			mv ${TEMPDIR}/disk/etc/init/ttyO2.conf ${TEMPDIR}/disk/etc/init/${SERIAL}.conf
			sed -i -e 's:ttyO2:'$SERIAL':g' ${TEMPDIR}/disk/etc/init/${SERIAL}.conf
		fi
	fi

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

	if [ "x${FDISK}" = "x${MMC}:" ] ; then
		echo ""
		echo "I see..."
		echo "fdisk -l:"
		LC_ALL=C fdisk -l 2>/dev/null | grep "Disk /dev/" --color=never
		echo ""
		echo "mount:"
		mount | grep -v none | grep "/dev/" --color=never
		echo ""
		read -p "Are you 100% sure, on selecting [${MMC}] (y/n)? "
		[ "${REPLY}" == "y" ] || exit
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

	IMAGE_ADDR="0x80300000"
	INITRD_ADDR="0x81600000"

	ZRELADD="0x80008000"

	SERIAL_CONSOLE="${SERIAL},115200n8"

	VIDEO_CONSOLE="console=tty0"

	#Older DSS2 omapfb framebuffer driver:
	HAS_OMAPFB_DSS2=1
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

function is_imx {
	IS_IMX=1
	SERIAL_CONSOLE="${SERIAL},115200"
	SUBARCH="imx"

	VIDEO_CONSOLE="console=tty0"
	HAS_IMX_BLOB=1
	VIDEO_FB="mxcdi1fb"
	VIDEO_TIMING="RGB24,1280x720M@60"
}

function check_uboot_type {
	unset SPL_BOOT
	unset DO_UBOOT
	unset IN_VALID_UBOOT
	unset SMSC95XX_MOREMEM
	unset USE_ZIMAGE

	case "${UBOOT_TYPE}" in
	beagle_bx)
		SYSTEM="beagle_bx"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_BX"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1
		;;
	beagle_cx)
		SYSTEM="beagle_cx"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_CX"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1
		;;
	beagle_xm)
		SYSTEM="beagle_xm"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_XM"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1
		;;
	beagle_xm_kms)
		SYSTEM="beagle_xm"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBOARD_XM"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1

		USE_KMS=1
		unset HAS_OMAPFB_DSS2

		BETA_KERNEL=1
		;;
	bone)
		SYSTEM="bone"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBONE_A"
		SERIAL="ttyO0"
		is_omap

		SUBARCH="omap-psp"

		SERIAL_MODE=1

		unset HAS_OMAPFB_DSS2
		unset KMS_VIDEOA
		;;
	bone_zimage)
		SYSTEM="bone_zimage"
		DO_UBOOT=1
		BOOTLOADER="BEAGLEBONE_A"
		SERIAL="ttyO0"
		is_omap
		USE_ZIMAGE=1

		USE_BETA_BOOTLOADER=1

		SUBARCH="omap-psp"

		SERIAL_MODE=1

		unset HAS_OMAPFB_DSS2
		unset KMS_VIDEOA
		;;
	igepv2)
		SYSTEM="igepv2"
		DO_UBOOT=1
		BOOTLOADER="IGEP00X0"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1

		SERIAL_MODE=1
		;;
	panda)
		SYSTEM="panda"
		DO_UBOOT=1
		BOOTLOADER="PANDABOARD"
		SMSC95XX_MOREMEM=1
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1
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
		USE_ZIMAGE=1
		VIDEO_OMAP_RAM="16MB"
		KMS_VIDEOB="video=HDMI-A-1"
		;;
	panda_kms)
		SYSTEM="panda_es"
		DO_UBOOT=1
		BOOTLOADER="PANDABOARD_ES"
		SMSC95XX_MOREMEM=1
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1

		USE_KMS=1
		unset HAS_OMAPFB_DSS2
		KMS_VIDEOB="video=HDMI-A-1"

		BETA_KERNEL=1
		;;
	crane)
		SYSTEM="crane"
		DO_UBOOT=1
		BOOTLOADER="CRANEBOARD"
		SERIAL="ttyO2"
		is_omap
		USE_ZIMAGE=1

		BETA_KERNEL=1
		SERIAL_MODE=1
		;;
	mx51evk)
		SYSTEM="mx51evk"
		DO_UBOOT=1
		DD_UBOOT=1
		BOOTLOADER="MX51EVK"
		SERIAL="ttymxc0"
		is_imx
		USE_ZIMAGE=1
		ZRELADD="0x90008000"
		IMAGE_ADDR="0x90800000"
		INITRD_ADDR="0x92100000"
		BETA_KERNEL=1
		SERIAL_MODE=1
		;;
	mx53loco)
		SYSTEM="mx53loco"
		DO_UBOOT=1
		DD_UBOOT=1
		BOOTLOADER="MX53LOCO"
		SERIAL="ttymxc0"
		is_imx
		USE_ZIMAGE=1
		ZRELADD="0x70008000"
		IMAGE_ADDR="0x70800000"
		INITRD_ADDR="0x72100000"
		BETA_KERNEL=1
		SERIAL_MODE=1
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
			mx51evk - <mx51 Dev Board>
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
		USER="root"
		PASS="fedoraarm"
		DISTRO="${DIST}-${ARCH}"
		DEBARCH="${DEBIAN}-${ARCH}"
		;;
	f17-armel|f17-sfp)
		DIST=f17
		ARCH=armel
		USER="root"
		PASS="fedoraarm"
		DISTRO="${DIST}-${ARCH}"
		DEBARCH="${DEBIAN}-${ARCH}"
		;;
	f17-armhf|f17-hfp)
		DIST=f17
		ARCH=armhf
		USER="root"
		PASS="fedoraarm"
		DISTRO="${DIST}-${ARCH}"
		DEBARCH="${DEBIAN}-${ARCH}"
		;;
	*)
		IN_VALID_DISTRO=1
		usage
		;;
	esac
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
	mx51evk
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
            check_root
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
        --use-beta-kernel)
            BETA_KERNEL=1
            ;;
        --use-experimental-kernel)
            EXPERIMENTAL_KERNEL=1
            ;;
        --use-beta-bootloader)
            USE_BETA_BOOTLOADER=1
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

unset BTRFS_FSTAB
if [ "x${ROOTFS_TYPE}" == "xbtrfs" ] ; then
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

 check_root
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


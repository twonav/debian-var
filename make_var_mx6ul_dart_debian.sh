#!/bin/bash
# It is designed to build Debian linux for Variscite imx6ul-dart module
# script tested in OS debian (jessie)
# prepare host OS system:
#  sudo apt-get install binfmt-support qemu qemu-user-static debootstrap kpartx
#  sudo apt-get install lvm2 dosfstools gpart binutils git lib32ncurses5-dev python-m2crypto
#  sudo apt-get install gawk wget git-core diffstat unzip texinfo gcc-multilib build-essential chrpath socat libsdl1.2-dev
#  sudo apt-get install autoconf libtool libglib2.0-dev libarchive-dev
#  sudo apt-get install python-git xterm sed cvs subversion coreutils texi2html
#  sudo apt-get install docbook-utils python-pysqlite2 help2man make gcc g++ desktop-file-utils libgl1-mesa-dev
#  sudo apt-get install libglu1-mesa-dev mercurial automake groff curl lzop asciidoc u-boot-tools mtd-utils
#  NOTE: HOST should have all packages upgraded to the latest version, because it has been observed that not having them
#  actulalized. unnecessary dependencies are added to the kernel debian package.
#  IMPORTANT: another debian package needed is:
#  sudo apt-get install gcc-arm-linux-gnueabihf
#  This package is necessary to remove the (libc6) dependency
#

# -e  Exit immediately if a command exits with a non-zero status.
set -e

UBUNTU_VERSION=`cat /etc/lsb-release | grep RELEASE | awk -F= '{ print $2 }' | awk -F. '{ print $1 }'`

SCRIPT_NAME=${0##*/}
readonly SCRIPT_VERSION="0.6"

#### Exports Variables ####
#### global variables ####
readonly ABSOLUTE_FILENAME=`readlink -e "$0"`
readonly ABSOLUTE_DIRECTORY=`dirname ${ABSOLUTE_FILENAME}`
readonly SCRIPT_POINT=${ABSOLUTE_DIRECTORY}
readonly SCRIPT_START_DATE=`date +%Y%m%d`
readonly LOOP_MAJOR=7

# Colors
readonly BACKGROUND_RED='\e[1;37;41m'
readonly BACKGROUND_GREEN='\e[1;37;42m'
readonly BACKGROUND_YELLOW='\e[1;33m'
readonly BACKGROUND_BLACK='\e[0m'

# default mirror
readonly DEF_DEBIAN_MIRROR="http://ftp.de.debian.org/debian/"
readonly DEB_RELEASE="jessie"
readonly DEF_ROOTFS_TARBAR_NAME="rootfs.tar.bz2"

## base paths
readonly DEF_BUILDENV="${ABSOLUTE_DIRECTORY}"
readonly DEF_SRC_DIR="${DEF_BUILDENV}/src"
readonly G_ROOTFS_DIR="${DEF_BUILDENV}/rootfs"
readonly G_TMP_DIR="${DEF_BUILDENV}/tmp"
readonly G_TOOLS_PATH="${DEF_BUILDENV}/toolchain"
readonly G_VARISCITE_PATH="${DEF_BUILDENV}/variscite"
readonly G_TWONAV_PATH="${DEF_BUILDENV}/twonav"
readonly SDCARD_ZIMAGE_DIR=/media/$(logname)/BOOT-VARSOM
readonly SDCARD_ROOTFS_DIR=/media/$(logname)/rootfs


## LINUX kernel: git, config, paths and etc
readonly G_LINUX_KERNEL_SRC_DIR="${DEF_SRC_DIR}/kernel"
G_LINUX_KERNEL_GIT="git@github.com:twonav/linux-2.6-imx.git"
readonly G_LINUX_KERNEL_BRANCH="imx-rel_imx_4.1.15_2.0.0_twonav"

readonly BRANDS="os twonav"                                                     
readonly MODELS="aventura crosstop trail"                                       
readonly G_TWONAV_DTB="imx6ull-var-dart-emmc_wifi.dtb $(for i in $BRANDS ; do for j in $MODELS ; do echo imx6ull-var-dart-$i-$j-2018.dtb ; done ; done)"

## uboot
readonly G_UBOOT_SRC_DIR="${DEF_SRC_DIR}/uboot"
G_UBOOT_GIT="git@github.com:twonav/uboot-imx.git"
readonly G_UBOOT_BRANCH="imx_v2016.03_4.1.15_2.0.0_twonav"
readonly G_UBOOT_DEF_CONFIG_MMC='mx6ull_14x14_evk_emmc_defconfig'
readonly G_UBOOT_DEF_CONFIG_NAND='mx6ul_var_dart_nand_defconfig'
readonly G_UBOOT_NAME_FOR_EMMC='u-boot.imx'


## ubi
readonly G_UBI_FILE_NAME='rootfs.ubi.img'

num_cpus() {
	local NCPUS=$(awk '/^processor/{print $3}' </proc/cpuinfo | wc -l)
	echo $((NCPUS + 0 > 0 ? NCPUS : 4))
}

## CROSS_COMPILER config and paths
readonly G_CROSS_COMPILEER_PATH="${G_TOOLS_PATH}/gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabihf/bin"
readonly G_CROSS_COMPILEER_PREFFIX="arm-linux-gnueabihf-"
readonly G_CROSS_COMPILEER_JOPTION="-j $(num_cpus)"
readonly G_EXT_CROSS_COMPILER_NAME='gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabihf.tar.xz'
readonly G_EXT_CROSS_COMPILER_LINK="http://releases.linaro.org/components/toolchain/binaries/4.9-2016.02/arm-linux-gnueabihf/${G_EXT_CROSS_COMPILER_NAME}"

############## user rootfs packages ##########
#We need the binaries to make it run, but we need the *dev packages to compile it. Maybe we can split into two packages types: rootfs and sysroot
readonly G_USER_PACKAGES="minicom tree bash-completion libc6 gdbserver libelf1 libdw1 libelf-dev libdw-dev uuid-dev libssl-dev libstdc++-4.9-dev libsdl1.2-dev libsdl-mixer1.2-dev libsdl-ttf2.0-dev libcurl4-gnutls-dev libapt-pkg-dev libiw-dev libnm-glib-dev libdbus-glib-1-dev libglib2.0-dev libbluetooth-dev libreadline-dev libxi-dev libxinerama-dev libxcursor-dev libudev-dev libusb-dev libibus-1.0-dev evtest libjack-dev libgbm-dev libmad0 libfuse2 fuse exfat-fuse exfat-utils ntfs-3g libevdev2 libsdl2-ttf-dev libsdl2-mixer-dev rsync"
readonly G_EXTRAS_PACKAGES="ttf-ubuntu-font-family libsdl2-dev"

#### Input params #####
PARAM_DEB_LOCAL_MIRROR="${DEF_DEBIAN_MIRROR}"
PARAM_OUTPUT_DIR="${DEF_BUILDENV}/output"
PARAM_DEBUG="0"
PARAM_REBUILD="0"
PARAM_CMD="all"
PARAM_BLOCK_DEVICE="na"
PARAM_KERNEL_NAME=""
PARAM_DEVICE="ALL"
PARAM_DEVICE_TYPE="twonav-aventura-2018"


### usage ###
function usage() {
	echo "This program version ${SCRIPT_VERSION}"
	echo " Used for make debian(${DEB_RELEASE}) image for \"imx6ul-var-dart\" board"
	echo " and create booted sdcard"
	echo ""
	echo "Usage:"
	echo " ./${SCRIPT_NAME} options"
	echo "Example:"
	echo " sudo ./${SCRIPT_NAME} -c package -t twonav-aventura-2018"
	echo ""
	echo "Options:"
	echo "  -h|--help   -- print this help"
	echo "  -c|--cmd <command>"
	echo "     Supported commands:"
	echo "       deploy      		-- prepare environment for all commands"
	echo "       all         		-- build or rebuild kernel/bootloader/rootfs"
	echo "       bootloader  		-- build or rebuild bootloader (u-boot+SPL)"
	echo "       kernel      		-- build or rebuild linux kernel for this board"
	echo "       package     		-- build or rebuild linux kernel package for this board"
	echo "       modules     		-- build or rebuild linux kernel modules and install in rootfs directory for this board"
	echo "       kernel_to_sd		-- copy kernel and modules contents to sdcard"
	echo "       -r|--rebuild		-- rebuild kernel and modules"
	echo "       rootfs      		-- build or rebuild debian rootfs filesystem (includes: make debian apks, make and install kernel moduled,"
	echo "                   		   make and install extern modules (wifi/bt), create rootfs.ubi.img and rootfs.tar.bz2)"
	echo "       rubi        		-- generate or regenerate rootfs.ubi.img image from rootfs folder "
	echo "       rtar        		-- generate or regenerate rootfs.tar.bz2 image from rootfs folder "
	echo "       clean       		-- clean all build artifacts (not delete sources code and resulted images (output folder))"
	echo "       sdcard      		-- create bootting sdcard for this device"
	echo "       -o|--output 		-- custom select output directory (default: \"${PARAM_OUTPUT_DIR}\")"
	echo "       -d|--dev    		-- select sdcard device (exmple: -d /dev/sde)"
	echo "       --debug     		-- enable debug mode for this script"
	echo "       -k|--instpkg		-- install package in rootfs"
	echo "       -t|--type   		-- twonav-aventura-2018/twonav-trail-2018/crosstop-2018"
	echo "Examples of use:"
	echo "  make only linux kernel for board: sudo ./${SCRIPT_NAME} --cmd kernel"
	echo "  make only rootfs for board:       sudo ./${SCRIPT_NAME} --cmd rootfs"
	echo "  create boot sdcard:               sudo ./${SCRIPT_NAME} --cmd sdcard --dev /dev/sdX"
	echo "  deploy and build:                 ./${SCRIPT_NAME} --cmd deploy && sudo ./${SCRIPT_NAME} --cmd all"
	echo ""
}

###### parse input arguments ##
readonly SHORTOPTS="k:c:o:d:h:r:t:"
readonly LONGOPTS="instpkg:,cmd:,output:,dev:,help,debug,rebuild,type:"

ARGS=$(getopt -s bash --options ${SHORTOPTS}  \
  --longoptions ${LONGOPTS} --name ${SCRIPT_NAME} -- "$@" )

eval set -- "$ARGS"

while true; do
	case $1 in
		-k|--instpkg ) # param pkg to install
			PARAM_INSTALL_PKG="$2";
			shift
			;;
		-c|--cmd ) # script command
			PARAM_CMD="$2";
			shift
			;;
		-o|--output ) # select output dir
			PARAM_OUTPUT_DIR="$2";
			shift
			;;
		-d|--dev ) # block device (for create sdcard)
			[ -e ${2} ] && {
				PARAM_BLOCK_DEVICE=${2};
			};
			shift
			;;
		-r|--rebuild ) # rebuild kernel
			PARAM_REBUILD=1;
			shift
			;;
		--debug ) # enable debug
			PARAM_DEBUG=1;
			shift
			;;
		-t|--type ) # twonav-aventura/trail-2018/crosstop-2018
			PARAM_DEVICE_TYPE="$2"
			shift
			;;
		-h|--help ) # get help
			usage
			exit 0;
			;;
		-- )
			shift
			break
			;;
		* )
			shift
			break
			;;
	esac
	shift
done

## enable tarce options in debug mode
[ "${PARAM_DEBUG}" = "1" ] && {
	echo "Debug mode enabled!"
	set -x
};

## declarate dinamic variables ##
readonly G_ROOTFS_TARBAR_PATH="${PARAM_OUTPUT_DIR}/${DEF_ROOTFS_TARBAR_NAME}"

## device type: twonav-aventura/trail-2018/crosstop-2018
readonly DEVICE="$PARAM_DEVICE_TYPE"
readonly DEVICE_FACTORY="twonav-factory-2018"

readonly UNIFIED_DEVICE="twonav-2018"

#Provisional until we define different kernels on the go.
readonly KERNEL_NAME="4.1.15-"$UNIFIED_DEVICE

# Parse kernel version from file
readonly TWONAV_KERNEL_VERSION_PATH="${G_LINUX_KERNEL_SRC_DIR}/twonav_kernel_version"

## defconfig
readonly G_LINUX_KERNEL_DEF_CONFIG="imx6ul-var-dart-${UNIFIED_DEVICE}_defconfig"

readonly G_KERNEL_PACKAGES="linux-headers-4.1.15-$UNIFIED_DEVICE linux-image-4.1.15-$UNIFIED_DEVICE"
readonly G_TWONAV_PACKAGES=twonav-all-2018

##uboot formatted name
readonly TWONAV_UBOOT_NAME_FOR_EMMC="u-boot_$DEVICE_FACTORY.imx"

###### local functions ######

### printing functions ###

# print error message
# $1 - printing string
function pr_error() {
	echo "E: $1"
}

# print warning message
# $1 - printing string
function pr_warning() {
	echo "W: $1"
}

# print info message
# $1 - printing string
function pr_info() {
	echo "I: $1"
}

# print debug message
# $1 - printing string
function pr_debug() {
	echo "D: $1"
}


### work functions ###

# get sources from git repository
# $1 - git repository
# $2 - branch name
# $3 - output dir
# $4 - commit id
function get_git_src() {
	# clone src code
	git clone ${1} -b ${2} ${3}
	cd ${3}
	if [ ! -z "$4" ]; then
		git reset --hard ${4}
	fi
	RET=$?
	cd -
	return $RET
}

# update sources from git repository
# $1 - output dir
# $2 - credential url
function git_update() {
	cd ${1}
	git pull
	RET=$?
	cd -
	return $RET
}

function make_prepare() {
## create src dirs
	mkdir -p ${G_LINUX_KERNEL_SRC_DIR} && :;
	mkdir -p ${G_UBOOT_SRC_DIR} && :;
	mkdir -p ${G_TOOLS_PATH} && :;

##	mkdir -p ${G_CROSS_COMPILEER_PATH} && :;

## create rootfs dir
	mkdir -p ${G_ROOTFS_DIR} && :;

## create out dir
	mkdir -p ${PARAM_OUTPUT_DIR} && :;

## create tmp dir
	mkdir -p ${G_TMP_DIR} && :;
}

# function generate rootfs in input dir
# $1 - rootfs base dir
function make_debian_rootfs() {
	local ROOTFS_BASE=$1

	pr_info "Make debian(${DEB_RELEASE}) rootfs start..."

	# umount previus mounts (if fail)
	umount ${ROOTFS_BASE}/{sys,proc,dev/pts,dev} 2>/dev/null && :;

## clear rootfs dir
	rm -rf ${ROOTFS_BASE}/* && :;

	pr_info "rootfs: debootstrap"
	debootstrap --verbose --foreign --arch armhf ${DEB_RELEASE} ${ROOTFS_BASE}/ ${PARAM_DEB_LOCAL_MIRROR}

## prepare qemu
	pr_info "rootfs: debootstrap in rootfs (second-stage)"
	cp /usr/bin/qemu-arm-static ${ROOTFS_BASE}/usr/bin/
	mount -o bind /proc ${ROOTFS_BASE}/proc
	mount -o bind /dev ${ROOTFS_BASE}/dev
	mount -o bind /dev/pts ${ROOTFS_BASE}/dev/pts
	mount -o bind /sys ${ROOTFS_BASE}/sys
	LANG=C chroot $ROOTFS_BASE /debootstrap/debootstrap --second-stage

	# delete unused folder
	LANG=C chroot $ROOTFS_BASE rm -rf  ${ROOTFS_BASE}/debootstrap

	pr_info "rootfs: generate default configs"
	mkdir -p ${ROOTFS_BASE}/etc/sudoers.d/
	echo "user ALL=(root) /usr/bin/apt-get, /usr/bin/dpkg, /usr/bin/vi, /sbin/reboot" > ${ROOTFS_BASE}/etc/sudoers.d/user
	chmod 0440 ${ROOTFS_BASE}/etc/sudoers.d/user


echo "deb $PARAM_DEB_LOCAL_MIRROR ${DEB_RELEASE} main contrib non-free
" > etc/apt/sources.list

echo "deb http://apt.twonav.com/ CompeGPS_Channels/Product2018_UnifiedTwoNav/Beta/TwoNav/" >> etc/apt/sources.list.d/twonav.list
echo "deb http://apt.twonav.com/ CompeGPS_Channels/Product2018_UnifiedTwoNav/Beta/Kernel/" >> etc/apt/sources.list.d/twonav.list
echo "deb http://apt.twonav.com/ CompeGPS_Channels/Product2018_UnifiedTwoNav/Beta/Extras/" >> etc/apt/sources.list.d/twonav.list

echo "
# /dev/mmcblk0p1  /boot           vfat    defaults        0       0
" > etc/fstab

echo "twonav" > etc/hostname

echo "auto lo
iface lo inet loopback
" > etc/network/interfaces

## twonav extra paths and files

mkdir etc/twonav
echo "1234-5678-7654" > etc/twonav/VeloDevID.txt

## Fake model (required by twonav-all-2018 postinst, in order to apply specific /opt/twonav-products/ files)
pr_info "rootfs: Fake model \"${DEVICE}\" "

mkdir proc/device-tree
echo "$DEVICE" > proc/device-tree/model

mkdir opt/twonav
cp -r ${G_TWONAV_PATH}/recovery opt/twonav
cp -r ${G_TWONAV_PATH}/tools/* bin
cp -r ${G_TWONAV_PATH}/scripts/* opt/twonav

echo "
if [ -f /etc/bash_completion ]; then
 . /etc/bash_completion
fi
" >> etc/profile

echo "
locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8
locales locales/default_environment_locale select en_US.UTF-8
console-common	console-data/keymap/policy	select	Select keymap from full list
keyboard-configuration keyboard-configuration/variant select 'English (US)'
openssh-server openssh-server/permit-root-login select true
slim shared/default-x-display-manager select slim
" > debconf.set

	pr_info "rootfs: prepare install packages in rootfs"
## apt-get install without starting
cat > ${ROOTFS_BASE}/usr/sbin/policy-rc.d << EOF
#!/bin/sh
exit 101
EOF

chmod +x ${ROOTFS_BASE}/usr/sbin/policy-rc.d

## third packages stage
cat > third-stage << EOF
#!/bin/bash
# apply debconfig options
debconf-set-selections /debconf.set
rm -f /debconf.set

function protected_install() {
    local _name=\${1}
    local repeated_cnt=5;
    local RET_CODE=1;

    for (( c=0; c<\${repeated_cnt}; c++ ))
    do
        apt-get install -y --force-yes \${_name} && {
            RET_CODE=0;
            break;
        };

        echo ""
        echo "##################################"
        echo "## Fix missing packages \${_name} ###"
        echo "##################################"
        echo ""

        sleep 2;
    done

    return \${RET_CODE}
}


# update packages and install base
apt-get update || apt-get update

protected_install locales
protected_install ntp
protected_install openssh-server
protected_install nfs-common

# packages required when flashing emmc
protected_install dosfstools
protected_install bzip2

# fix config for sshd (added user login for password)
sed -i -e 's/\PermitRootLogin.*/PermitRootLogin\tyes/g' /etc/ssh/sshd_config

# enable Xorg
protected_install Xorg

# network manager
protected_install network-manager-gnome

# added alsa & alsa utilites
protected_install alsa-base
protected_install alsa-utils
# protected_install gstreamer0.10-plugins-good
protected_install gstreamer0.10-alsa

# added i2c tools
protected_install i2c-tools

# added usb tools
protected_install usbutils

# added net tools
protected_install iperf

#media
protected_install audacious
# protected_install parole

# wifi
protected_install wpasupplicant

# mtd
protected_install mtd-utils

# bluetooth
protected_install bluetooth
protected_install bluez
protected_install bluez-obexd
protected_install bluez-tools
protected_install libbluetooth3
protected_install blueman
protected_install gconf2

# wifi support packages
protected_install hostapd
protected_install udhcpd

# can support
protected_install can-utils

# psmisc utils (killall and etc)
protected_install psmisc

# editors
protected_install nano
protected_install vim

# delete unused packages ##
apt-get -y remove xscreensaver
apt-get -y remove xserver-xorg-video-ati
apt-get -y remove xserver-xorg-video-r128
apt-get -y remove xserver-xorg-video-radeon
apt-get -y remove xserver-xorg-video-mach64
apt-get -y remove manpages
apt-get -y remove gstreamer0.10-x
apt-get -y remove hddtemp

apt-get -y autoremove

# Remove foreign man pages and locales
rm -rf /usr/share/man/??
rm -rf /usr/share/man/??_*
rm -rf /var/cache/man/??
rm -rf /var/cache/man/??_*
(cd /usr/share/locale; ls | grep -v en_[GU] | xargs rm -rf)

# Remove document files
rm -rf /usr/share/doc


# create users and set password
echo "root:keepcalm" | chpasswd

# sado kill
rm -f third-stage
EOF

	pr_info "rootfs: install selected debian packages (third-stage)"
	chmod +x third-stage
	LANG=C chroot ${ROOTFS_BASE} /third-stage

## fourth-stage ##
### install variscite-bluetooth init script
#	install -m 0755 ${G_VARISCITE_PATH}/brcm_patchram_plus ${ROOTFS_BASE}/usr/bin/
#	install -m 0755 ${G_VARISCITE_PATH}/variscite-bluetooth ${ROOTFS_BASE}/etc/init.d/
#	LANG=C chroot ${ROOTFS_BASE} update-rc.d variscite-bluetooth defaults
#	LANG=C chroot ${ROOTFS_BASE} update-rc.d variscite-bluetooth enable 2 3 4 5

### install variscite-wifi init script
#	install -m 0755 ${G_VARISCITE_PATH}/variscite-wifi ${ROOTFS_BASE}/etc/init.d/
#	LANG=C chroot ${ROOTFS_BASE} update-rc.d variscite-wifi defaults
#	LANG=C chroot ${ROOTFS_BASE} update-rc.d variscite-wifi enable S

## end packages stage ##
[ "${G_USER_PACKAGES}" != "" ] && {

	pr_info "rootfs: install user defined packages (user-stage)"
	pr_info "rootfs: G_USER_PACKAGES \"${G_USER_PACKAGES}\" "
	pr_info "rootfs: G_EXTRAS_PACKAGES \"${G_EXTRAS_PACKAGES}\" "
	pr_info "rootfs: G_KERNEL_PACKAGES \"${G_KERNEL_PACKAGES}\" "
	pr_info "rootfs: G_TWONAV_PACKAGES \"${G_TWONAV_PACKAGES}\" "

echo "#!/bin/bash
# update packages
apt-get update

# install all user packages
echo -e \"${BACKGROUND_GREEN} Installing USER_PACKAGES... ${BACKGROUND_BLACK}\"
apt-get -y --force-yes install ${G_USER_PACKAGES}
if [ \$? -gt 0 ]; then
	echo -e \"${BACKGROUND_RED} ERROR in apt-get install USER_PACKAGES ${BACKGROUND_BLACK}\"
fi

echo -e \"${BACKGROUND_GREEN} Installing EXTRAS_PACKAGES... ${BACKGROUND_BLACK}\"
apt-get -y --force-yes install ${G_EXTRAS_PACKAGES}
if [ \$? -gt 0 ]; then
	echo -e \"${BACKGROUND_RED} ERROR in apt-get install EXTRAS_PACKAGES ${BACKGROUND_BLACK}\"
fi

echo -e \"${BACKGROUND_GREEN} Purging KERNEL_PACKAGES... ${BACKGROUND_BLACK}\"
apt-get -y --force-yes purge ${G_KERNEL_PACKAGES}
if [ \$? -gt 0 ]; then
	echo -e \"${BACKGROUND_RED} ERROR in apt-get purge KERNEL_PACKAGES ${BACKGROUND_BLACK}\"
fi

echo -e \"${BACKGROUND_GREEN} Installing KERNEL_PACKAGES... ${BACKGROUND_BLACK}\"
DEBIAN_FRONTEND=noninteractive apt-get -y --force-yes install ${G_KERNEL_PACKAGES}
if [ \$? -gt 0 ]; then
	echo -e \"${BACKGROUND_RED} ERROR in apt-get install KERNEL_PACKAGES ${BACKGROUND_BLACK}\"
fi

echo -e \"${BACKGROUND_GREEN} Installing TWONAV_PACKAGES... ${BACKGROUND_BLACK}\"
apt-get -y --force-yes install ${G_TWONAV_PACKAGES}
if [ \$? -gt 0 ]; then
	echo -e \"${BACKGROUND_RED} ERROR in apt-get install TWONAV_PACKAGES ${BACKGROUND_BLACK}\"
fi

echo -e \"${BACKGROUND_GREEN} SUCCESS user-stage ${BACKGROUND_BLACK}\"

rm -f user-stage
" > user-stage

	chmod +x user-stage
	LANG=C chroot ${ROOTFS_BASE} /user-stage

## Remove faked model
	pr_info "rootfs: Removing faked model \"${DEVICE}\" "
	rm -rf proc/device-tree
	pr_info "rootfs: Removed faked model \"${DEVICE}\" "
};

## fix files links and missing files ##
	echo "Fixing softlinks..."
	ln -sfv ../../../lib/arm-linux-gnueabihf/libz.so.1.2.8 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libz.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libm.so.6 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libm.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libdl.so.2 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libdl.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libdbus-1.so.3.8.14 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libdbus-1.so
	ln -sfv libdbus-glib-1.so.2 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libdbus-glib-1.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libglib-2.0.so.0 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libglib-2.0.so
	ln -sfv libnm-glib.so.4 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libnm-glib.so
	ln -sfv libnm-util.so.2 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libnm-util.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libuuid.so.1.3.0 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libuuid.so

	ln -sfv ../../../lib/arm-linux-gnueabihf/libanl.so.1 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libanl.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libBrokenLocale.so.1 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libBrokenLocale.so 
	ln -sfv ../../../lib/arm-linux-gnueabihf/libcidn.so.1 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libcidn.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libcrypt.so.1 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libcrypt.so 
	ln -sfv ../../../lib/arm-linux-gnueabihf/libhistory.so.6 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libhistory.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libiw.so.30 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libiw.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libnsl.so.1 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libnsl.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libnss_compat.so.2 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libnss_compat.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libnss_dns.so.2 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libnss_dns.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libnss_files.so.2 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libnss_files.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libnss_hesiod.so.2 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libnss_hesiod.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libnss_nisplus.so.2 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libnss_nisplus.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libnss_nis.so.2 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libnss_nis.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libpcre.so.3 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libpcre.so
	ln -sfv libpng12.so.0 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libpng12.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libpng12.so.0 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libpng12.so.0
	ln -sfv libpng12.so ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libpng.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libreadline.so.6 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libreadline.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libresolv.so.2 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libresolv.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/librt.so.1 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/librt.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libslang.so.2 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libslang.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libthread_db.so.1 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libthread_db.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libtinfo.so.5 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libtinfo.so
	ln -sfv ../../../var/lib/dpkg/alternatives/libtxc-dxtn-arm-linux-gnueabihf ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libtxc_dxtn.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libudev.so.1.5.0 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libudev.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libusb-0.1.so.4 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libusb-0.1.so.4
	ln -sfv ../../../lib/arm-linux-gnueabihf/libusb-0.1.so.4.4.4 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libusb.so
	ln -sfv ../../../lib/arm-linux-gnueabihf/libutil.so.1 ${ROOTFS_BASE}/usr/lib/arm-linux-gnueabihf/libutil.so
	echo "Softlinks Fixed"

## binaries rootfs patching ##
	install -m 0644 ${G_VARISCITE_PATH}/issue ${ROOTFS_BASE}/etc/
	install -m 0644 ${G_VARISCITE_PATH}/issue.net ${ROOTFS_BASE}/etc/
	install -m 0644 ${G_VARISCITE_PATH}/hostapd.conf ${ROOTFS_BASE}/etc/
	install -m 0644 ${G_VARISCITE_PATH}/uuid.h ${ROOTFS_BASE}/usr/include/bluetooth/

## added alsa default configs ##
	install -m 0644 ${G_VARISCITE_PATH}/asound.state ${ROOTFS_BASE}/var/lib/alsa/
	install -m 0644 ${G_VARISCITE_PATH}/asound.conf ${ROOTFS_BASE}/etc/
	install -m 0664 ${G_TWONAV_PATH}/mixer/.asoundrc ${ROOTFS_BASE}/root/

## Revert regular booting
	rm -f ${ROOTFS_BASE}/usr/sbin/policy-rc.d

## Include firmware files for wlan/bt
	mkdir -p ${ROOTFS_BASE}/lib/firmware/ti-connectivity
	cp -r ${G_TWONAV_PATH}/firmware/ti-connectivity ${ROOTFS_BASE}/lib/firmware


# added mirror to source list
echo "#deb ${DEF_DEBIAN_MIRROR} ${DEB_RELEASE} main contrib non-free
" > etc/apt/sources.list

echo "deb ${DEF_DEBIAN_MIRROR} ${DEB_RELEASE} main contrib non-free
" > etc/apt/sources.list.save

	pr_info "rootfs: clean"

## clenup command
echo "#!/bin/bash
apt-get clean
rm -f cleanup
" > cleanup

	# clean all packages
	chmod +x cleanup
	LANG=C chroot ${ROOTFS_BASE} /cleanup
	umount ${ROOTFS_BASE}/{sys,proc,dev/pts,dev}
	return 0;
}

# make tarbar arx from footfs
# $1 -- packet folder
# $2 -- output arx full name
function make_tarbar() {
	cd $1

	pr_info "make tarbar arx from folder ${1}"
	pr_info "Remove old arx $2"
	rm $2 > /dev/null 2>&1 && :;

	pr_info "Create $2"

	tar jcf $2 .
	success=$?
	[ $success -eq 0 ] || {
	# fail
	    rm $2 > /dev/null 2>&1 && :;
	};

	cd -
}

# make linux kernel modules
# $1 -- cross compiller prefix
# $2 -- linux defconfig file
# $3 -- linux dtb files
# $4 -- linux dirname
# $5 -- out patch
function make_kernel() {
	pr_info "make kernel .config"
	make ARCH=arm CROSS_COMPILE=${1} ${G_CROSS_COMPILEER_JOPTION} -C ${4}/ ${2}

	make ARCH=arm CROSS_COMPILE=${1} ${G_CROSS_COMPILEER_JOPTION} -C ${4} oldconfig

	pr_info "make kernel"
	make CROSS_COMPILE=${1} ARCH=arm ${G_CROSS_COMPILEER_JOPTION} -C ${4}/ zImage

	pr_info "make ${3} file"
	make CROSS_COMPILE=${1} ARCH=arm ${G_CROSS_COMPILEER_JOPTION} -C ${4} ${3}

	pr_info "Copy kernel and dtb files to output dir: ${5}"
	cp ${4}/arch/arm/boot/zImage ${5}/;
	cp ${4}/arch/arm/boot/dts/*.dtb ${5}/;

	return 0;
}

# clean kernel
# $1 -- linux dir path
function clean_kernel() {
	pr_info "Clean linux kernel"

	make ARCH=arm -C ${1}/ mrproper

	return 0;
}

# make linux kernel modules
# $1 -- cross compiller prefix
# $2 -- linux defconfig file
# $3 -- linux dirname
# $4 -- out modules patch
function make_kernel_modules() {
	pr_info "make kernel modules .config"
	make ARCH=arm CROSS_COMPILE=${1} ${G_CROSS_COMPILEER_JOPTION} -C ${3}/ ${2}

	make ARCH=arm CROSS_COMPILE=${1} ${G_CROSS_COMPILEER_JOPTION} -C ${3} oldconfig

	pr_info "Compiling Linux kernel modules"
	make ARCH=arm CROSS_COMPILE=${1} ${G_CROSS_COMPILEER_JOPTION} -C ${3}/ modules

	pr_info "Installing Linux kernel modules to ${4}"
	make CROSS_COMPILE=${1} ARCH=arm INSTALL_MOD_PATH=${4}/ ${G_CROSS_COMPILEER_JOPTION} -C ${3}/ modules_install

	return 0;
}

###################### Twonav kernel package fix for older kernel  packages ##########
function pkg_info_gen() {
	local OLD_KERN_BRANDS="twonav os"
	local OLD_KERN_MODELS="trail aventura"
	local BREAK_VERSION="1.0.20"
	echo -n "$1"
	local i j cnt=0
	for i in $OLD_KERN_BRANDS ; do for j in $OLD_KERN_MODELS ; do
		if ((cnt++ > 0)) ; then echo "," ; fi
		echo -en "\t$2-4.1.15-$i-$j-2018 (<= $BREAK_VERSION)"
	done ; done
	echo
}

function fix_unified_kernel_control_files() {
	local i
	local LINUX_DEBIAN_PATH=${1}/debian/${2}-$KERNEL_NAME/DEBIAN		

	for i in "Breaks:" "Replaces:" ; do
		pkg_info_gen "$i" ${2}>> $LINUX_DEBIAN_PATH/control		
	done
}
# ###############################################################################################



# build linux kernel package
# $1 -- cross compiller prefix
# $2 -- linux dirname
# $3 -- rootfs dirname
# $4 -- out patch
function build_kernel_package() {
	readonly KERNEL_VERSION=`cat ${TWONAV_KERNEL_VERSION_PATH}`
	cd ${2}

	pr_info "Kernel package: make-kpkg"

	if [ "$UBUNTU_VERSION" -ge 16 ]; then
		DEB_HOST_ARCH=armhf make-kpkg --revision=$KERNEL_VERSION ${G_CROSS_COMPILEER_JOPTION} --rootcmd fakeroot --arch arm --cross-compile ${1} --initrd linux_headers linux_image
	else
		DEB_HOST_ARCH=armhf make-kpkg --revision=$KERNEL_VERSION ${G_CROSS_COMPILEER_JOPTION} --rootcmd fakeroot --arch arm --cross-compile ${1} --initrd --zImage linux_headers linux_image
	fi

	#cp -r ${3}/lib/modules/$KERNEL_NAME/updates ${2}/debian/linux-image-$KERNEL_NAME/lib/modules/$KERNEL_NAME/
	#cp ${3}/lib/modules/$KERNEL_NAME/modules.*  ${2}/debian/linux-image-$KERNEL_NAME/lib/modules/$KERNEL_NAME/
	
	pr_info "Kernel package: Copying all dtb to kernel package"
	for dtb in $G_TWONAV_DTB
	do
		cp "${2}/arch/arm/boot/dts/$dtb" ${2}/debian/linux-image-$KERNEL_NAME/boot	
	done

	## Repacks linux-image with TwoNav modifications
	pr_info "Kernel package: Repacking linux-image with TwoNav modifications..."
	local KERN_IMAGE_BASE_NAME="linux-image"	
	fix_unified_kernel_control_files $2 $KERN_IMAGE_BASE_NAME	
	cp ${2}/arch/arm/boot/zImage ${2}/debian/linux-image-$KERNEL_NAME/boot		
	dpkg --build ${2}/debian/$KERN_IMAGE_BASE_NAME-$KERNEL_NAME ..

	## Repacks linux-headers with TwoNav modifications
	pr_info "Kernel package: Repacking linux-headers with TwoNav modifications..."
	local KERN_HEADERS_BASE_NAME="linux-headers"
	fix_unified_kernel_control_files $2 $KERN_HEADERS_BASE_NAME	
	dpkg --build ${2}/debian/$KERN_HEADERS_BASE_NAME-$KERNEL_NAME ..

	mv ../*.deb ${4}/;
	
	cd -
	
	return 0;
}

function copy_kernel() {
	pr_info "Copying kernel to sdcard"

	[ "${PARAM_REBUILD}" = "1" ] && {
		echo "Recompiling kernel..."
		cmd_make_kernel
		cmd_make_kmodules
	};


	rm -rf /media/ebosch/rootfs/lib/modules/* || {
		pr_error "Failed #$? prepare modules dir"
		return 1;
	};

	rm -rf /media/ebosch/BOOT-VARSOM/*.dtb || {
		pr_error "Failed #$? prepare dtb dir"
		return 1;
	};

	pr_info "Copy kernel and dtb files to output dir: /media/ebosch/BOOT-VARSOM"
	cp ${1}/arch/arm/boot/zImage ${SDCARD_ZIMAGE_DIR};
	cp ${1}/arch/arm/boot/dts/*.dtb ${SDCARD_ZIMAGE_DIR};

	pr_info "Installing Linux kernel modules to /media/ebosch/rootfs/lib/modules/"
	cp -r ${2}/lib/modules/* ${SDCARD_ROOTFS_DIR}/lib/modules/

	sync
}

# make uboot
# $1 uboot path
# $2 outputdir
function make_uboot() {
### make emmc uboot ###
	pr_info "Make SPL & u-boot: ${G_UBOOT_DEF_CONFIG_MMC}"
	pr_info "Uboot for ${DEVICE}"
	pr_info "File Name = ${TWONAV_UBOOT_NAME_FOR_EMMC}"

	# clean work directory 
	make ARCH=arm -C ${1} CROSS_COMPILE=${G_CROSS_COMPILEER_PATH}/${G_CROSS_COMPILEER_PREFFIX} ${G_CROSS_COMPILEER_JOPTION} mrproper

	# make uboot config for mmc
	make ARCH=arm -C ${1} CROSS_COMPILE=${G_CROSS_COMPILEER_PATH}/${G_CROSS_COMPILEER_PREFFIX} ${G_CROSS_COMPILEER_JOPTION} ${G_UBOOT_DEF_CONFIG_MMC}

	# make uboot
	make ARCH=arm -C ${1} CROSS_COMPILE=${G_CROSS_COMPILEER_PATH}/${G_CROSS_COMPILEER_PREFFIX} ${G_CROSS_COMPILEER_JOPTION} KCFLAGS="-DTWONAV_DEVICE=\\\"$DEVICE_FACTORY\\\""

	# copy images
	cp ${1}/${G_UBOOT_NAME_FOR_EMMC} ${2}/${TWONAV_UBOOT_NAME_FOR_EMMC}

	return 0;
}

# clean uboot
# $1 -- u-boot dir path
function clean_uboot() {
	pr_info "Clean uboot"

	make ARCH=arm -C ${1}/ mrproper

	return 0;
}

# make *.ubi image from rootfs
# params:
#  $1 -- path to rootfs dir
#  $2 -- tmp dir
#  $3 -- output dir
#  $4 -- ubi file name
function make_ubi() {
	readonly local _rootfs=${1};
	readonly local _tmp=${2};
	readonly local _output=${3};
	readonly local _ubi_file_name=${4};

	readonly local UBI_CFG="${_tmp}/ubi.cfg"
	readonly local UBIFS_IMG="${_tmp}/rootfs.ubifs"
	readonly local UBI_IMG="${_output}/${_ubi_file_name}"

	# gnerate ubifs file
	pr_info "Generate ubi config file: ${UBI_CFG}"
cat > ${UBI_CFG} << EOF
[ubifs]
mode=ubi
image=${UBIFS_IMG}
vol_id=0
vol_type=dynamic
vol_name=rootfs
vol_flags=autoresize
EOF
	# delete previus images
	rm -f ${UBI_IMG} && :;
	rm -f ${UBIFS_IMG} && :;

	pr_info "Creating $UBIFS_IMG image"
	mkfs.ubifs -x zlib -m 2048  -e 124KiB -c 3965 -r ${_rootfs} $UBIFS_IMG

	pr_info "Creating $UBI_IMG image"
	ubinize -o ${UBI_IMG} -m 2048 -p 128KiB -s 2048 -O 2048 ${UBI_CFG}

	# delete unused file
	rm -f ${UBIFS_IMG} && :;
	rm -f ${UBI_CFG} && :;

	return 0;
}

# make sdcard for device
# $1 -- block device
function check_sdcard()
{
	# Check that parameter is a valid block device
	if [ ! -b "$1" ]; then
          pr_error "$1 is not a valid block device, exiting"
	   return 1
        fi

	local dev=$(basename $1)

	# Check that /sys/block/$dev exists
	if [ ! -d /sys/block/$dev ]; then
	  pr_error "Directory /sys/block/${dev} missing, exiting"
	  return 1
        fi

	# Get device parameters
	local removable=$(cat /sys/block/${dev}/removable)
	local block_size=$(cat /sys/class/block/${dev}/queue/physical_block_size)
	local size_bytes=$((${block_size}*$(cat /sys/class/block/${dev}/size)))
	local size_gib=$(bc <<< "scale=1; ${size_bytes}/(1024*1024*1024)")

	# Check that device is either removable or loop
	if [ "$removable" != "1" -a $(stat -c '%t' /dev/$dev) != ${LOOP_MAJOR} ]; then
          pr_error "$1 is not a removable device, exiting"
	  return 1
        fi

	# Check that device is attached
	if [ ${size_bytes} -eq 0 ]; then
          pr_error "$1 is not attached, exiting"
          return 1
	fi

	pr_info "Device: ${LPARAM_BLOCK_DEVICE}, ${size_gib}GiB"
	pr_info "================================================"
	read -p "Press Enter to continue"

	return 0
}

# make sdcard for device
# $1 -- block device
# $2 -- output images dir
function make_sdcard() {
	readonly local LPARAM_BLOCK_DEVICE=${1}
	readonly local LPARAM_OUTPUT_DIR=${2}
	readonly local P1_MOUNT_DIR="${G_TMP_DIR}/p1"
	readonly local P2_MOUNT_DIR="${G_TMP_DIR}/p2"
	readonly local DEBIAN_IMAGES_TO_ROOTFS_POINT="opt/images/Debian"

	readonly local BOOTLOAD_RESERVE=4
	readonly local BOOT_ROM_SIZE=8
	readonly local SPARE_SIZE=0

	make_prepare;

	[ "${LPARAM_BLOCK_DEVICE}" = "na" ] && {
		pr_warning "No valid block device: ${LPARAM_BLOCK_DEVICE}"
		return 1;
	};

	local part=""
	if [ `echo ${LPARAM_BLOCK_DEVICE} | grep -c mmcblk` -ne 0 ]; then
		part="p"
	fi
	if [ `echo ${LPARAM_BLOCK_DEVICE} | grep -c loop` -ne 0 ]; then
		part="p"
	fi

	# Check that we're using a valid device
	if ! check_sdcard ${LPARAM_BLOCK_DEVICE}; then
		return 1
	fi

	for ((i=0; i<10; i++))
	do
		if [ `mount | grep -c ${LPARAM_BLOCK_DEVICE}${part}$i` -ne 0 ]; then
			umount ${LPARAM_BLOCK_DEVICE}${part}$i
		fi
	done

	# Call sfdisk to get total card size
	local TOTAL_SIZE=`sfdisk -s ${LPARAM_BLOCK_DEVICE}`
	local TOTAL_SIZE=`expr ${TOTAL_SIZE} / 1024`
	local ROOTFS_SIZE=`expr ${TOTAL_SIZE} - ${BOOTLOAD_RESERVE} - ${BOOT_ROM_SIZE} - ${SPARE_SIZE}`

	function format_sdcard
	{
		pr_info "Formating SDCARD partitions"
		mkfs.vfat ${LPARAM_BLOCK_DEVICE}${part}1 -n BOOT-VARSOM
		mkfs.ext4 ${LPARAM_BLOCK_DEVICE}${part}2 -L rootfs
	}

	function flash_u-boot
	{
		pr_info "Flashing U-Boot"
		dd if=${LPARAM_OUTPUT_DIR}/${TWONAV_UBOOT_NAME_FOR_EMMC} of=${LPARAM_BLOCK_DEVICE} bs=1K seek=1; sync
	}

	function flash_sdcard
	{
		pr_info "Flashing \"BOOT-VARSOM\" partition"
		cp ${LPARAM_OUTPUT_DIR}/*.dtb	${P1_MOUNT_DIR}/
		cp ${LPARAM_OUTPUT_DIR}/zImage	${P1_MOUNT_DIR}/zImage
		sync

		pr_info "Flashing \"rootfs\" partition"
		tar -xjf ${LPARAM_OUTPUT_DIR}/${DEF_ROOTFS_TARBAR_NAME} -C ${P2_MOUNT_DIR}/
	}

	function copy_debian_images
	{
		mkdir -p ${P2_MOUNT_DIR}/${DEBIAN_IMAGES_TO_ROOTFS_POINT}

		pr_info "Copying Debian images to /${DEBIAN_IMAGES_TO_ROOTFS_POINT}"
		cp ${LPARAM_OUTPUT_DIR}/zImage 						${P2_MOUNT_DIR}/${DEBIAN_IMAGES_TO_ROOTFS_POINT}/
		cp ${LPARAM_OUTPUT_DIR}/${DEF_ROOTFS_TARBAR_NAME}	${P2_MOUNT_DIR}/${DEBIAN_IMAGES_TO_ROOTFS_POINT}/${DEF_ROOTFS_TARBAR_NAME}
		cp ${LPARAM_OUTPUT_DIR}/${G_UBI_FILE_NAME}			${P2_MOUNT_DIR}/${DEBIAN_IMAGES_TO_ROOTFS_POINT}/${G_UBI_FILE_NAME}

		cp ${LPARAM_OUTPUT_DIR}/*.dtb						${P2_MOUNT_DIR}/${DEBIAN_IMAGES_TO_ROOTFS_POINT}/

		pr_info "Copying MMC U-Boot to /${DEBIAN_IMAGES_TO_ROOTFS_POINT}"
		cp ${LPARAM_OUTPUT_DIR}/${TWONAV_UBOOT_NAME_FOR_EMMC}	${P2_MOUNT_DIR}/${DEBIAN_IMAGES_TO_ROOTFS_POINT}/

		return 0;
	}

	function copy_scripts
	{
		pr_info "Copying scripts to /${DEBIAN_IMAGES_TO_ROOTFS_POINT}"
		cp ${G_VARISCITE_PATH}/debian-emmc.sh	${P2_MOUNT_DIR}/usr/sbin/
		cp ${G_VARISCITE_PATH}/debian-nand.sh	${P2_MOUNT_DIR}/usr/sbin/
		cp ${G_VARISCITE_PATH}/kobs-ng		${P2_MOUNT_DIR}/usr/sbin/
		### For future use. Now it breaks boot.
		cp ${G_VARISCITE_PATH}/rc.flasher	${P2_MOUNT_DIR}/etc/rc.local 
	
		# added exec options
		chmod +x ${P2_MOUNT_DIR}/usr/sbin/debian-emmc.sh ${P2_MOUNT_DIR}/usr/sbin/kobs-ng ${P2_MOUNT_DIR}/etc/rc.local
	}

	function ceildiv
	{
	    local num=$1
	    local div=$2
	    echo $(( (num + div - 1) / div ))
	}

	# Delete the partitions
	for ((i=0; i<10; i++))
	do
		if [ `ls ${LPARAM_BLOCK_DEVICE}${part}$i 2> /dev/null | grep -c ${LPARAM_BLOCK_DEVICE}${part}$i` -ne 0 ]; then
			dd if=/dev/zero of=${LPARAM_BLOCK_DEVICE}${part}$i bs=512 count=1024
		fi
	done
	sync

	((echo d; echo 1; echo d; echo 2; echo d; echo 3; echo d; echo w) | fdisk ${LPARAM_BLOCK_DEVICE} &> /dev/null) || true
	sync

	dd if=/dev/zero of=${LPARAM_BLOCK_DEVICE} bs=1024 count=4096
	sleep 2; sync;

	pr_info "Creating new partitions"

	# Create a new partition table
fdisk ${LPARAM_BLOCK_DEVICE} <<EOF
n
p
1
8192
262143
n
p
2
262144

p
w
EOF
	sleep 2; sync;

	# Get total card size
	total_size=`sfdisk -s ${LPARAM_BLOCK_DEVICE}`
	total_size=`expr ${total_size} / 1024`
	boot_rom_sizeb=`expr ${BOOT_ROM_SIZE} + ${BOOTLOAD_RESERVE}`
	rootfs_size=`expr ${total_size} - ${boot_rom_sizeb} - ${SPARE_SIZE}`

	pr_info "ROOT SIZE=${rootfs_size} TOTAl SIZE=${total_size} BOOTROM SIZE=${boot_rom_sizeb}"
	sleep 2; sync;

	# Format the partitions
	format_sdcard
	sleep 2; sync;

	flash_u-boot
	sleep 2; sync;

	# Mount the partitions
	mkdir -p ${P1_MOUNT_DIR}
	mkdir -p ${P2_MOUNT_DIR}
	sync

	mount ${LPARAM_BLOCK_DEVICE}${part}1  ${P1_MOUNT_DIR}
	mount ${LPARAM_BLOCK_DEVICE}${part}2  ${P2_MOUNT_DIR}
	sleep 2; sync;

	flash_sdcard
	copy_debian_images
	copy_scripts

	pr_info "Sync sdcard..."
	sync
	umount ${P1_MOUNT_DIR}
	umount ${P2_MOUNT_DIR}

	rm -rf ${P1_MOUNT_DIR}
	rm -rf ${P2_MOUNT_DIR}

	pr_info "Done make sdcard!"

	return 0;
}

#################### commands ################

function cmd_install_package() {	
# example:
# $ sudo ./make_var_mx6ul_dart_debian.sh -c instpkg -k libmad0-dev
	cp /usr/bin/qemu-arm-static ${G_ROOTFS_DIR}/usr/bin/
	mount -o bind /proc ${G_ROOTFS_DIR}/proc
	mount -o bind /dev ${G_ROOTFS_DIR}/dev
	mount -o bind /dev/pts ${G_ROOTFS_DIR}/dev/pts
	mount -o bind /sys ${G_ROOTFS_DIR}/sys
	LANG=C chroot $G_ROOTFS_DIR apt-get update
	echo "LANG=C chroot $G_ROOTFS_DIR apt-get -y install ${PARAM_INSTALL_PKG}"
	LANG=C chroot $G_ROOTFS_DIR apt-get -y install ${PARAM_INSTALL_PKG}
	umount ${G_ROOTFS_DIR}/{sys,proc,dev/pts,dev} 2>/dev/null && :;
}

function cmd_make_deploy() {
	make_prepare;

	# get kernel repository
	(( `ls ${G_LINUX_KERNEL_SRC_DIR} 2>/dev/null | wc -l` == 0 )) && {
		pr_info "Get kernel repository";
		get_git_src ${G_LINUX_KERNEL_GIT} ${G_LINUX_KERNEL_BRANCH} ${G_LINUX_KERNEL_SRC_DIR}
	};

	# get uboot repository
	(( `ls ${G_UBOOT_SRC_DIR} 2>/dev/null | wc -l` == 0 )) && {
		pr_info "Get uboot repository";
		get_git_src ${G_UBOOT_GIT} ${G_UBOOT_BRANCH} ${G_UBOOT_SRC_DIR}
	};

	# get linaro toolchain
	(( `ls ${G_CROSS_COMPILEER_PATH} 2>/dev/null | wc -l` == 0 )) && {
		pr_info "Get and unpack cross compiler";
		wget -c ${G_EXT_CROSS_COMPILER_LINK} -O ${G_TMP_DIR}/${G_EXT_CROSS_COMPILER_NAME}
		tar -xJf ${G_TMP_DIR}/${G_EXT_CROSS_COMPILER_NAME} -C ${G_TOOLS_PATH}/
		rm -rf ${G_TMP_DIR}/${G_EXT_CROSS_COMPILER_NAME} && :;
	};

	return 0;
}

function cmd_update_repositories() {
	make_prepare;

	pr_info "Updating kernel repository";
	git_update ${G_LINUX_KERNEL_SRC_DIR}

	pr_info "Updating uboot repository";
	git_update ${G_UBOOT_SRC_DIR}

	return 0;
}

function cmd_make_rootfs() {
	make_prepare;

	## make debian rootfs
	cd ${G_ROOTFS_DIR}
	make_debian_rootfs ${G_ROOTFS_DIR} || {
		pr_error "Failed #$? in function make_debian_rootfs"
		cd -;
		return 1;
	}
	cd -

	## make and apply modules in rootfs
	make_kernel_modules ${G_CROSS_COMPILEER_PATH}/${G_CROSS_COMPILEER_PREFFIX} ${G_LINUX_KERNEL_DEF_CONFIG} ${G_LINUX_KERNEL_SRC_DIR} ${G_ROOTFS_DIR} || {
		pr_error "Failed #$? in function make_kernel_modules"
		return 2;
	}

	## make kernel package
	build_kernel_package ${G_CROSS_COMPILEER_PATH}/${G_CROSS_COMPILEER_PREFFIX} ${G_LINUX_KERNEL_SRC_DIR} ${G_ROOTFS_DIR} ${PARAM_OUTPUT_DIR} || {
		pr_error "Failed #$? in function build_kernel_package"
		return 1;
	};

	## pack rootfs
	make_tarbar ${G_ROOTFS_DIR} ${G_ROOTFS_TARBAR_PATH} || {
		pr_error "Failed #$? in function make_tarbar"
		return 4;
	}

	## pack to ubi
	#make_ubi ${G_ROOTFS_DIR} ${G_TMP_DIR} ${PARAM_OUTPUT_DIR} ${G_UBI_FILE_NAME}  || {
	#	pr_error "Failed #$? in function make_ubi"
	#	return 5;
	#};

	return 0;
}

function cmd_make_uboot() {
	make_prepare;

	make_uboot ${G_UBOOT_SRC_DIR} ${PARAM_OUTPUT_DIR} || {
		pr_error "Failed #$? in function make_uboot"
		return 1;
	};

	return 0;
}

function cmd_make_kernel() {
	make_prepare;

	make_kernel ${G_CROSS_COMPILEER_PATH}/${G_CROSS_COMPILEER_PREFFIX} ${G_LINUX_KERNEL_DEF_CONFIG} "${G_TWONAV_DTB}" ${G_LINUX_KERNEL_SRC_DIR} ${PARAM_OUTPUT_DIR} || {
		pr_error "Failed #$? in function make_kernel"
		return 1;
	};

	return 0;
}

function cmd_build_kernel_package() {
	make_prepare;

	build_kernel_package ${G_CROSS_COMPILEER_PATH}/${G_CROSS_COMPILEER_PREFFIX} ${G_LINUX_KERNEL_SRC_DIR} ${G_ROOTFS_DIR} ${PARAM_OUTPUT_DIR} || {
		pr_error "Failed #$? in function build_kernel_package"
		return 1;
	};

	return 0;

}


function cmd_make_kmodules() {
	make_prepare;

	rm -rf ${G_ROOTFS_DIR}/lib/modules/* || {
		pr_error "Failed #$? prepare modules dir"
		return 1;
	};

	make_kernel_modules ${G_CROSS_COMPILEER_PATH}/${G_CROSS_COMPILEER_PREFFIX} ${G_LINUX_KERNEL_DEF_CONFIG} ${G_LINUX_KERNEL_SRC_DIR} ${G_ROOTFS_DIR} || {
		pr_error "Failed #$? in function make_kmodules"
		return 2;
	};

	return 0;
}

function cmd_copy_kernel() {
	make_prepare;

	copy_kernel ${G_LINUX_KERNEL_SRC_DIR} ${G_ROOTFS_DIR} || {
		pr_error "Failed #$? in function copy_kernel"
		return 1;
	};

	return 0;
}

function cmd_make_rfs_ubi() {
	make_prepare;

	make_ubi ${G_ROOTFS_DIR} ${G_TMP_DIR} ${PARAM_OUTPUT_DIR} ${G_UBI_FILE_NAME} || {
		pr_error "Failed #$? in function make_ubi"
		return 1;
	};

	return 0;
}

function cmd_make_rfs_tar() {
	make_prepare;

	## pack rootfs
	make_tarbar ${G_ROOTFS_DIR} ${G_ROOTFS_TARBAR_PATH} || {
		pr_error "Failed #$? in function make_tarbar"
		return 1;
	}

	return 0;
}

function cmd_make_sdcard() {
	make_prepare;

	make_sdcard ${PARAM_BLOCK_DEVICE} ${PARAM_OUTPUT_DIR} || {
		pr_error "Failed #$? in function make_sdcard"
		return 1;
	};

	return 0;
}

function cmd_make_clean() {

	## clean kernel, dtb, modules
	clean_kernel ${G_LINUX_KERNEL_SRC_DIR} || {
		pr_error "Failed #$? in function clean_kernel"
		return 1;
	};

	## clean u-boot
	clean_uboot ${G_UBOOT_SRC_DIR} || {
		pr_error "Failed #$? in function clean_uboot"
		return 2;
	};

	## delete tmp dirs and etc
	pr_info "Delete tmp dir ${G_TMP_DIR}"
	rm -rf ${G_TMP_DIR} && :;

	pr_info "Delete rootfs dir ${G_ROOTFS_DIR}"
	rm -rf ${G_ROOTFS_DIR} && :;

	return 0;
}

#################### main function #######################

## test for root access support (msrc not allowed)
[ "$PARAM_CMD" != "deploy" ] && [ "$PARAM_CMD" != "update" ] && [ ${EUID} -ne 0 ] && {
	pr_error "this command must be run as root (or sudo/su)"
	exit 1;
};

V_RET_CODE=0;

START_TIME=`date +%s`


pr_info "Command: \"$PARAM_CMD\" start..."

case $PARAM_CMD in
	instpkg )
		cmd_install_package || {
			V_RET_CODE=1;
		};
		;;
	deploy )
		cmd_make_deploy || {
			V_RET_CODE=1;
		};
		;;
	rootfs )
		cmd_make_rootfs || {
			V_RET_CODE=1;
		};
		;;
	bootloader )
		cmd_make_uboot || {
			V_RET_CODE=1;
		}
		;;
	kernel )
		cmd_make_kernel || {
			V_RET_CODE=1;
		};
		;;
	package )
		(cmd_make_kernel &&
		cmd_make_kmodules &&
		cmd_build_kernel_package ) || {
			V_RET_CODE=1;
		};
		;;
	modules )
		cmd_make_kmodules || {
			V_RET_CODE=1;
		};
		;;
	update )
		(cmd_make_clean &&
		 cmd_update_repositories ) || {
			V_RET_CODE=1;
		};
		;;
	kernel_to_sd )
		cmd_copy_kernel || {
			V_RET_CODE=1;
		};
		;;
	sdcard )
		cmd_make_sdcard || {
			V_RET_CODE=1;
		};
		;;
	rubi )
		cmd_make_rfs_ubi || {
			V_RET_CODE=1;
		};
		;;
	rtar )
		cmd_make_rfs_tar || {
			V_RET_CODE=1;
		};
		;;
	all )
		(cmd_make_uboot  &&
		 cmd_make_kernel &&
		 cmd_make_rootfs ) || {
			V_RET_CODE=1;
		};
		;;
	clean )
		cmd_make_clean || {
			V_RET_CODE=1;
		};
		;;
	* )
		pr_error "Invalid input command: \"${PARAM_CMD}\"";
		V_RET_CODE=1;
		;;
esac

END_TIME=`date +%s`

TOTAL_TIME=$((END_TIME-START_TIME))

pr_info ""
pr_info "Command: \"$PARAM_CMD\" end ($TOTAL_TIME seconds). Exit code: ${V_RET_CODE}"
pr_info ""


exit ${V_RET_CODE};

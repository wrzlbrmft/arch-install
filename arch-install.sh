#!/usr/bin/env bash

INSTALL_HOME=$( cd "`dirname "${BASH_SOURCE[0]}"`" && pwd )
INSTALL_SCRIPT="`basename "${BASH_SOURCE[0]}"`"
INSTALL_NAME="`printf "$INSTALL_SCRIPT" | awk -F '.' '{ print $1 }'`"

doPrintHelpMessage() {
	printf "Usage: ./$INSTALL_SCRIPT [-h] [-c config] [target [options...]]\n"
}

while getopts :hc: opt; do
	case "$opt" in
		h)
			doPrintHelpMessage
			exit 0
			;;

		c)
			INSTALL_CONFIG="$OPTARG"
			;;

		:)
			printf "ERROR: "
			case "$OPTARG" in
				c)
					printf "Missing config file"
					;;
			esac
			printf "\n"
			exit 1
			;;

		\?)
			printf "ERROR: Invalid option ('-$OPTARG')\n"
			exit 1
			;;
	esac
done
shift $((OPTIND - 1))

INSTALL_TARGET="$1"
shift
INSTALL_OPTIONS="$@"

if [ -z "$INSTALL_CONFIG" ]; then
	INSTALL_CONFIG="$INSTALL_HOME/$INSTALL_NAME.conf"
fi

if [ ! -f "$INSTALL_CONFIG" ]; then
	printf "ERROR: Config file not found ('$INSTALL_CONFIG')\n"
	exit 1
fi

if [ -z "$INSTALL_TARGET" ]; then
	INSTALL_TARGET="base"
fi

. "$INSTALL_CONFIG"

doCopyToChroot() {
	CHROOT_INSTALL_HOME="/mnt/root/`basename "$INSTALL_HOME"`"
	mkdir -p "$CHROOT_INSTALL_HOME"

	cp -p "${BASH_SOURCE[0]}" "$CHROOT_INSTALL_HOME"
	cp -p "$INSTALL_CONFIG" "$CHROOT_INSTALL_HOME"
}

doChroot() {
	local IN_CHROOT_INSTALL_HOME="/root/`basename "$CHROOT_INSTALL_HOME"`"
	local IN_CHROOT_INSTALL_CONFIG="$IN_CHROOT_INSTALL_HOME/`basename "$INSTALL_CONFIG"`"

	arch-chroot /mnt /usr/bin/bash -c "'$IN_CHROOT_INSTALL_HOME/$INSTALL_SCRIPT' -c '$IN_CHROOT_INSTALL_CONFIG' chroot"
}

doCopyToSu() {
	SU_USER_HOME="`eval printf "~$SU_USER"`"
	SU_INSTALL_HOME="$SU_USER_HOME/`basename "$INSTALL_HOME"`"
	mkdir -p "$SU_INSTALL_HOME"

	cp -p "${BASH_SOURCE[0]}" "$SU_INSTALL_HOME"
	cp -p "$INSTALL_CONFIG" "$SU_INSTALL_HOME"

	local SU_USER_GROUP="`id -gn "$SU_USER"`"
	chown -R "$SU_USER:$SU_USER_GROUP" "$SU_INSTALL_HOME"
}

doSu() {
	local IN_SU_INSTALL_HOME="$SU_USER_HOME/`basename "$SU_INSTALL_HOME"`"
	local IN_SU_INSTALL_CONFIG="$IN_SU_INSTALL_HOME/`basename "$INSTALL_CONFIG"`"

	/bin/su - "$SU_USER" -c "'$IN_SU_INSTALL_HOME/$INSTALL_SCRIPT' -c '$IN_SU_INSTALL_CONFIG' $@"
}

doDeactivateAllSwaps() {
	swapoff -a
}

getAllPartitions() {
	lsblk -l -n -o NAME "$INSTALL_DEVICE" | grep -v "^`basename "$INSTALL_DEVICE"`$"
}

doFlush() {
	sync
	sync
	sync
}

doWipeAllPartitions() {
	for i in $( getAllPartitions | sort -r ); do
		dd if=/dev/zero of="$INSTALL_DEVICE_HOME/$i" bs=1M count=1
	done

	doFlush
}

doPartProbe() {
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
}

doDeleteAllPartitions() {
	fdisk "$INSTALL_DEVICE" << __END__
o
w
__END__

	doPartProbe
}

doWipeDevice() {
	dd if=/dev/zero of="$INSTALL_DEVICE" bs=1M count=1

	doPartProbe
}

doCreateNewPartitions() {
	parted -a optimal "$INSTALL_DEVICE" << __END__
mklabel msdos
u MiB
mkpart primary linux-swap 1 $BOOT_SIZE
mkpart primary linux-swap $BOOT_SIZE $SWAP_SIZE
mkpart primary linux-swap $SWAP_SIZE 100%
toggle 1 boot
quit
__END__

	doPartProbe

	fdisk "$INSTALL_DEVICE" << __END__
t
1
83
t
2
82
t
3
83
w
__END__

	doPartProbe
}

doDetectDevices() {
	local ALL_PARTITIONS=($( getAllPartitions ))
	BOOT_DEVICE="$INSTALL_DEVICE_HOME/${ALL_PARTITIONS[0]}"
	SWAP_DEVICE="$INSTALL_DEVICE_HOME/${ALL_PARTITIONS[1]}"
	ROOT_DEVICE="$INSTALL_DEVICE_HOME/${ALL_PARTITIONS[2]}"
}

doCreateNewPartitionsLuks() {
	parted -a optimal "$INSTALL_DEVICE" << __END__
mklabel msdos
u MiB
mkpart primary linux-swap 1 $BOOT_SIZE
mkpart primary linux-swap $BOOT_SIZE 100%
toggle 1 boot
quit
__END__

	doPartProbe

	fdisk "$INSTALL_DEVICE" << __END__
t
1
83
t
2
8e
w
__END__

	doPartProbe
}

doDetectDevicesLuks() {
	local ALL_PARTITIONS=($( getAllPartitions ))
	BOOT_DEVICE="$INSTALL_DEVICE_HOME/${ALL_PARTITIONS[0]}"
	LUKS_DEVICE="$INSTALL_DEVICE_HOME/${ALL_PARTITIONS[1]}"
}

case "$INSTALL_TARGET" in
	base)
		doDeactivateAllSwaps
		doWipeAllPartitions
		doDeleteAllPartitions
		doWipeDevice

		if [ "$LVM_ON_LUKS" == "yes" ]; then
			doCreateNewPartitionsLuks
			doDetectDevicesLuks
		else
			doCreateNewPartitions
			doDetectDevices
		fi

		doCopyToChroot
		doChroot
		;;

	chroot)
		doCopyToSu
		doSu suInstallYaourt

		exit 0
		;;

	suInstallYaourt)
		exit 0
		;;

	*)
		printf "ERROR: Unknown target ('$INSTALL_TARGET')\n"
		exit 1
		;;
esac

#!/usr/bin/env bash
# usage: ./arch-install.sh [-h|--help|<conf>]

case "$1" in
	-h|--help)
		printf "usage: ./`basename "${BASH_SOURCE[0]}"` [-h|--help|<conf>]\n"
		exit 0
		;;

	*)
		INSTALL_CONF="$1"
		;;
esac

INSTALL_HOME=$( cd "`dirname "${BASH_SOURCE[0]}"`" && pwd )
INSTALL_NAME="`basename "${BASH_SOURCE[0]}"`"
INSTALL_BASE="`basename "${BASH_SOURCE[0]}" | awk -F '.' '{ print $1 }'`"

if [ -z "$INSTALL_CONF" ]; then
	INSTALL_CONF="$INSTALL_HOME/$INSTALL_BASE.conf"
fi

if [ ! -f "$INSTALL_CONF" ]; then
	printf "ERROR: File not found ('$INSTALL_CONF')\n"
	exit 1
fi

. "$INSTALL_CONF"

doDeactivateAllSwaps() {
	swapoff -a
}

getAllPartitions() {
	lsblk -l -n -o NAME "$INSTALL_DEVICE" | grep -v "^`basename "$INSTALL_DEVICE"`$"
}

doWipeAllPartitions() {
	for i in $( getAllPartitions | sort -r ); do
		dd if=/dev/zero of=/dev/"$i" bs=10240k count=1
	done
	sync; sync; sync
}

doDeleteAllPartitions() {
	fdisk "$INSTALL_DEVICE" << __END__
o
w
__END__
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
}

doWipeDevice() {
	dd if=/dev/zero of="$INSTALL_DEVICE" bs=10240k count=1
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
}

doCreateNewPartitions() {
	parted -a optimal "$INSTALL_DEVICE" << __END__
mklabel msdos
u MiB
mkpart primary linux-swap 1 $BOOT_PARTITION_SIZE
mkpart primary linux-swap $BOOT_PARTITION_SIZE 100%
toggle 1 boot
quit
__END__
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"

	fdisk "$INSTALL_DEVICE" << __END__
t
1
83
t
2
8e
w
__END__
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
}

identifyPartitions() {
	local ALL_PARTITIONS=($( getAllPartitions ))
	BOOT_PARTITION="/dev/${ALL_PARTITIONS[0]}"
	LUKS_PARTITION="/dev/${ALL_PARTITIONS[1]}"
}

doCreateLuksLvm() {
	cryptsetup -q -y -c aes-xts-plain64 -s 512 -h sha512 luksFormat "$LUKS_PARTITION"
	cryptsetup luksOpen "$LUKS_PARTITION" lvm
}

doCreateLvmVolumes() {
	pvcreate /dev/mapper/lvm
	vgcreate main /dev/mapper/lvm
	lvcreate -L "$SWAP_PARTITION_SIZE"M -n swap main
	lvcreate -l 100%FREE -n root main
}

doFormat() {
	mkfs.ext2 -L boot "$BOOT_PARTITION"
	mkswap -L swap /dev/mapper/main-swap
	mkfs.ext4 -L root /dev/mapper/main-root
}

doMount() {
	mount /dev/mapper/main-root /mnt
	mkdir /mnt/boot
	mount "$BOOT_PARTITION" /mnt/boot
	swapon /dev/mapper/main-swap
}

doPacstrap() {
	pacstrap /mnt base
}

doGenfstab() {
	genfstab -p -U /mnt >> /mnt/etc/fstab
}

doDeactivateAllSwaps
doWipeAllPartitions
doDeleteAllPartitions
doWipeDevice

doCreateNewPartitions
doWipeAllPartitions
identifyPartitions
doCreateLuksLvm
doCreateLvmVolumes
doFormat
doMount

doPacstrap
doGenfstab

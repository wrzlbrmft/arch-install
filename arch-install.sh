#!/usr/bin/env bash
# usage: ./arch-install.sh [-h] [<conf>]

INSTALL_HOME=$( cd "`dirname "${BASH_SOURCE[0]}"`" && pwd )
INSTALL_NAME="`basename "${BASH_SOURCE[0]}"`"
INSTALL_BASE="`printf "$INSTALL_NAME" | awk -F '.' '{ print $1 }'`"

printHelpMessage() {
	printf "usage: ./$INSTALL_NAME [-h] [<conf>]\n"
}

IN_CHROOT="0"

while getopts :hc opt; do
	case $opt in
		h)
			printHelpMessage
			exit 0
			;;

		c)
			IN_CHROOT="1"
			;;

		\?)
			printf "ERROR: Invalid option ('-$OPTARG')\n"
			exit 1
			;;
	esac
done
shift $((OPTIND - 1))

INSTALL_CONF="$1"

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
		dd if=/dev/zero of="/dev/$i" bs=10240k count=1
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

determineNewPartitions() {
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

doCopyToChroot() {
	CHROOT_INSTALL_HOME="/mnt/root/`basename "$INSTALL_HOME"`"
	mkdir -p "$CHROOT_INSTALL_HOME"
	cp -p "${BASH_SOURCE[0]}" "$CHROOT_INSTALL_HOME"
	cp -p "$INSTALL_CONF" "$CHROOT_INSTALL_HOME"
}

doChroot() {
	local IN_CHROOT_INSTALL_HOME="/root/`basename "$CHROOT_INSTALL_HOME"`"
	local IN_CHROOT_INSTALL_CONF="$IN_CHROOT_INSTALL_HOME/`basename "$INSTALL_CONF"`"
	arch-chroot /mnt /usr/bin/bash -c "'$IN_CHROOT_INSTALL_HOME/$INSTALL_NAME' -c '$IN_CHROOT_INSTALL_CONF'"
}

doSetHostname() {
	printf "$HOSTNAME\n" > /etc/hostname
}

doSetTimezone() {
	ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}

doSetLocale() {
	cat /etc/locale.gen | sed -e 's/^#\('"$LOCALE"'\)\s*$/\1/' > /tmp/locale.gen
	cat /tmp/locale.gen > /etc/locale.gen
	rm /tmp/locale.gen

	locale-gen

	printf "LANG=$LOCALE_LANG\n" > /etc/locale.conf
}

doSetVConsole() {
	printf "KEYMAP=$VCONSOLE_KEYMAP\n" > /etc/vconsole.conf
	printf "FONT=$VCONSOLE_FONT\n" >> /etc/vconsole.conf
}

doMkinitcpio() {
	cat /etc/mkinitcpio.conf | sed -e 's/^\(\(HOOKS\)="\([^"]\+\)"\)$/#\1\n\2="\3"/' > /tmp/mkinitcpio.conf
	cat /tmp/mkinitcpio.conf | awk 'm = $0 ~ /^HOOKS="([^"]+)"$/ { \
			gsub(/keyboard/, "", $0); \
			gsub(/filesystems/, "keyboard keymap encrypt lvm2 filesystems", $0); \
			gsub(/  /, " ", $0); \
			print \
		} !m { print }' > /etc/mkinitcpio.conf
	rm /tmp/mkinitcpio.conf

	mkinitcpio -p linux
}

doSetRootPassword() {
	passwd root
}

determineLuksUuid() {
	LUKS_UUID="`cryptsetup luksUUID "$LUKS_PARTITION"`"
}

doInstallGrub() {
	pacman -S --noconfirm grub

	grub-install --target=i386-pc --recheck "$INSTALL_DEVICE"

	cat /etc/default/grub | sed -e 's/^\(\(GRUB_CMDLINE_LINUX_DEFAULT\)="\([^"]\+\)"\)$/#\1\n\2="\3"/' > /tmp/default-grub
	cat /tmp/default-grub | awk 'm = $0 ~ /^GRUB_CMDLINE_LINUX_DEFAULT="([^"]+)"$/ { \
			gsub(/quiet/, "quiet cryptdevice=UUID=\"'"$LUKS_UUID"'\":main root=/dev/mapper/main-root lang='"$VCONSOLE_KEYMAP"' locale='"$LOCALE_LANG"'", $0); \
			print \
		} !m { print }' > /etc/default/grub
	rm /tmp/default-grub

	grub-mkconfig -o /boot/grub/grub.cfg
}

doCreateCrypttab() {
	printf "main UUID=\"$LUKS_UUID\" none luks\n" > /etc/crypttab
}

if [ "$IN_CHROOT" == "1" ]; then

	doSetHostname
	doSetTimezone
	doSetLocale
	doSetVConsole

	doMkinitcpio

	doSetRootPassword

	determineNewPartitions
	determineLuksUuid

	doInstallGrub

	doCreateCrypttab

	exit 0

else

	doDeactivateAllSwaps
	doWipeAllPartitions
	doDeleteAllPartitions
	doWipeDevice

	doCreateNewPartitions
	doWipeAllPartitions
	determineNewPartitions
	doCreateLuksLvm
	doCreateLvmVolumes
	doFormat
	doMount

	doPacstrap
	doGenfstab

	doCopyToChroot
	doChroot

fi

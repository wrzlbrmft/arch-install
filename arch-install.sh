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
	parted -s -a optimal "$INSTALL_DEVICE" mklabel msdos

	local START="1"; local END="$BOOT_SIZE"
	parted -s -a optimal "$INSTALL_DEVICE" mkpart primary linux-swap "${START}MiB" "${END}MiB"

	START="$END"; let END+=SWAP_SIZE
	parted -s -a optimal "$INSTALL_DEVICE" mkpart primary linux-swap "${START}MiB" "${END}MiB"

	START="$END"; END="100%"
	parted -s -a optimal "$INSTALL_DEVICE" mkpart primary linux-swap "${START}MiB" "${END}MiB"

	parted -s -a optimal "$INSTALL_DEVICE" toggle 1 boot

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
	parted -s -a optimal "$INSTALL_DEVICE" mklabel msdos

	local START="1"; local END="$BOOT_SIZE"
	parted -s -a optimal "$INSTALL_DEVICE" mkpart primary linux-swap "${START}MiB" "${END}MiB"

	START="$END"; END="100%"
	parted -s -a optimal "$INSTALL_DEVICE" mkpart primary linux-swap "${START}MiB" "${END}MiB"

	parted -s -a optimal "$INSTALL_DEVICE" toggle 1 boot

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

doCreateLuks() {
	cryptsetup -q -y -c aes-xts-plain64 -s 512 -h sha512 luksFormat "$LUKS_DEVICE"
	cryptsetup luksOpen "$LUKS_DEVICE" "$LUKS_NAME"
}

doCreateLuksLvm() {
	local LUKS_LVM_DEVICE="$LVM_DEVICE_HOME/$LUKS_NAME"
	pvcreate "$LUKS_LVM_DEVICE"
	vgcreate "$LUKS_LVM_NAME" "$LUKS_LVM_DEVICE"
	lvcreate -L "${SWAP_SIZE}M" -n "$SWAP_LABEL" "$LUKS_LVM_NAME"
	lvcreate -l 100%FREE -n "$ROOT_LABEL" "$LUKS_LVM_NAME"
}

doDetectDevicesLuksLvm() {
	SWAP_DEVICE="$LVM_DEVICE_HOME/$LUKS_LVM_NAME-$SWAP_LABEL"
	ROOT_DEVICE="$LVM_DEVICE_HOME/$LUKS_LVM_NAME-$ROOT_LABEL"
}

doFormat() {
	mkfs.ext2 -L "$BOOT_LABEL" "$BOOT_DEVICE"
	mkswap -L "$SWAP_LABEL" "$SWAP_DEVICE"
	mkfs.ext4 -L "$ROOT_LABEL" "$ROOT_DEVICE"
}

doMount() {
	mount "$ROOT_DEVICE" /mnt
	mkdir /mnt/boot
	mount "$BOOT_DEVICE" /mnt/boot
	swapon "$SWAP_DEVICE"
}

doPacstrap() {
	pacstrap /mnt base

	doFlush
}

doGenerateFstab() {
	genfstab -p -U /mnt >> /mnt/etc/fstab
}

doSetHostname() {
	printf "$HOSTNAME\n" > /etc/hostname
}

doSetTimezone() {
	ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}

doGenerateLocale() {
	cat /etc/locale.gen | sed -e 's/^#\('"$LOCALE"'\)\s*$/\1/' > /tmp/locale.gen
	cat /tmp/locale.gen > /etc/locale.gen
	rm /tmp/locale.gen

	locale-gen
}

doSetLocale() {
	printf "LANG=$LOCALE_LANG\n" > /etc/locale.conf
}

doSetConsole() {
	printf "KEYMAP=$CONSOLE_KEYMAP\n" > /etc/vconsole.conf
	printf "FONT=$CONSOLE_FONT\n" >> /etc/vconsole.conf
}

doEditMkinitcpioLuks() {
	cat /etc/mkinitcpio.conf | sed -e 's/^\(\(HOOKS\)="\([^"]\+\)"\)$/#\1\n\2="\3"/' > /tmp/mkinitcpio.conf
	cat /tmp/mkinitcpio.conf | awk 'm = $0 ~ /^HOOKS="([^"]+)"$/ { \
			gsub(/keyboard/, "", $0); \
			gsub(/filesystems/, "keyboard keymap encrypt lvm2 filesystems", $0); \
			gsub(/  /, " ", $0); \
			print \
		} !m { print }' > /etc/mkinitcpio.conf
	rm /tmp/mkinitcpio.conf
}

doMkinitcpio() {
	mkinitcpio -p linux
}

doSetRootPassword() {
	passwd root
}

doInstallGrub() {
	pacman -S --noconfirm grub

	grub-install --target=i386-pc --recheck "$INSTALL_DEVICE"
}

doEditGrubConfig() {
	cat /etc/default/grub | sed -e 's/^\(\(GRUB_CMDLINE_LINUX_DEFAULT\)="\([^"]\+\)"\)$/#\1\n\2="\3"/' > /tmp/default-grub
	cat /tmp/default-grub | awk 'm = $0 ~ /^GRUB_CMDLINE_LINUX_DEFAULT="([^"]+)"$/ { \
			gsub(/quiet/, "quiet root='"$ROOT_DEVICE"' lang='"$CONSOLE_KEYMAP"' locale='"$LOCALE_LANG"'", $0); \
			print \
		} !m { print }' > /etc/default/grub
	rm /tmp/default-grub
}

doDetectLuksUuid() {
	LUKS_UUID="`cryptsetup luksUUID "$LUKS_DEVICE"`"
}

doEditGrubConfigLuks() {
	cat /etc/default/grub | sed -e 's/^\(\(GRUB_CMDLINE_LINUX_DEFAULT\)="\([^"]\+\)"\)$/#\1\n\2="\3"/' > /tmp/default-grub
	cat /tmp/default-grub | awk 'm = $0 ~ /^GRUB_CMDLINE_LINUX_DEFAULT="([^"]+)"$/ { \
			gsub(/quiet/, "quiet cryptdevice=UUID=\"'"$LUKS_UUID"'\":'"$LUKS_LVM_NAME"' root='"$ROOT_DEVICE"' lang='"$CONSOLE_KEYMAP"' locale='"$LOCALE_LANG"'", $0); \
			print \
		} !m { print }' > /etc/default/grub
	rm /tmp/default-grub
}

doGenerateGrubConfig() {
	grub-mkconfig -o /boot/grub/grub.cfg
}

doCreateCrypttabLuks() {
	printf "$LUKS_LVM_NAME UUID=\"$LUKS_UUID\" none luks\n" > /etc/crypttab
}

doAddHostUser() {
	groupadd "$HOST_USER_GROUP"
	useradd -g "$HOST_USER_GROUP" -G "$HOST_USER_GROUPS_EXTRA" -d "/$HOST_USER_USERNAME" -s /bin/bash -c "$HOST_USER_REALNAME" -m "$HOST_USER_USERNAME"
	HOST_USER_HOME="`eval printf "~$HOST_USER_USERNAME"`"
	chmod 0751 "$HOST_USER_HOME"
	passwd -l "$HOST_USER_USERNAME"
}

doAddMainUser() {
	useradd -g "$MAIN_USER_GROUP" -G "$MAIN_USER_GROUPS_EXTRA" -s /bin/bash -c "$MAIN_USER_REALNAME" -m "$MAIN_USER_USERNAME"
	MAIN_USER_HOME="`eval printf "~$MAIN_USER_USERNAME"`"
	chmod 0751 "$MAIN_USER_HOME"
	passwd "$MAIN_USER_USERNAME"
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
			doCreateLuks
			doCreateLuksLvm
			doDetectDevicesLuksLvm
		else
			doCreateNewPartitions
			doDetectDevices
		fi

		doFormat
		doMount

		doPacstrap

		doGenerateFstab

		doCopyToChroot
		doChroot

		exit 0
		;;

	chroot)
		doSetHostname
		doSetTimezone
		doGenerateLocale
		doSetLocale
		doSetConsole

		if [ "$LVM_ON_LUKS" == "yes" ]; then
			doEditMkinitcpioLuks
		fi

		doMkinitcpio

		doSetRootPassword

		doInstallGrub

		if [ "$LVM_ON_LUKS" = "yes" ]; then
			doDetectDevicesLuks
			doDetectDevicesLuksLvm
			doDetectLuksUuid
			doEditGrubConfigLuks
		else
			doDetectDevices
			doEditGrubConfig
		fi

		doGenerateGrubConfig

		if [ "$LVM_ON_LUKS" == "yes" ]; then
			doCreateCrypttabLuks
		fi

		if [ "$ADD_HOST_USER" == "yes" ]; then
			doAddHostUser
		fi

		if [ "$ADD_MAIN_USER" == "yes" ]; then
			doAddMainUser
		fi

		doCopyToSu
		doSu suInstallYaourt
		doSu suYaourt foo bar

		exit 0
		;;

	suInstallYaourt)
		printf "suInstallYaourt\n"
		exit 0
		;;

	suYaourt)
		printf "suYaourt: $INSTALL_OPTIONS\n"
		exit 0
		;;

	*)
		printf "ERROR: Unknown target ('$INSTALL_TARGET')\n"
		exit 1
		;;
esac

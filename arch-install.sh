#!/usr/bin/env bash
# usage: ./arch-install.sh [-h] [<conf>]

# HOME is the directory of the install script, e.g. "/root/arch-install"
# NAME is the file name, e.g. "arch-install.sh"
# BASE is the file name without extension, e.g. "install-arch"
INSTALL_HOME=$( cd "`dirname "${BASH_SOURCE[0]}"`" && pwd )
INSTALL_NAME="`basename "${BASH_SOURCE[0]}"`"
INSTALL_BASE="`printf "$INSTALL_NAME" | awk -F '.' '{ print $1 }'`"

# prints a help message about the script usage
printHelpMessage() {
	printf "usage: ./$INSTALL_NAME [-h] [<conf>]\n"
}

# whether we are inside the chroot environment (default: no)
IN_CHROOT="0"

# process command-line options
while getopts :hc opt; do
	case $opt in
		h)
			printHelpMessage
			exit 0
			;;

		c)
			# we are inside the chroot environment
			IN_CHROOT="1"
			;;

		\?)
			printf "ERROR: Invalid option ('-$OPTARG')\n"
			exit 1
			;;
	esac
done
shift $((OPTIND - 1))

# last command-line option is an optional conf file
INSTALL_CONF="$1"

if [ -z "$INSTALL_CONF" ]; then
	# if no conf file is given, use the default: next to the install script, with ".conf" extension
	INSTALL_CONF="$INSTALL_HOME/$INSTALL_BASE.conf"
fi

if [ ! -f "$INSTALL_CONF" ]; then
	# if the conf file does not exist
	printf "ERROR: File not found ('$INSTALL_CONF')\n"
	exit 1
fi

# include conf file
. "$INSTALL_CONF"

# ========= functions =========

# globally deactivates all swap partitions and files
doDeactivateAllSwaps() {
	swapoff -a
}

# returns all currently existing partitions on the installation device (one per line)
# NOTE: the partitions are returned without "/dev/", i.e. "/dev/sda1" is returned as "sda1"
getAllPartitions() {
	# lsblk also lists the installation device itself, so filter it out using grep
	lsblk -l -n -o NAME "$INSTALL_DEVICE" | grep -v "^`basename "$INSTALL_DEVICE"`$"
}

# wipes the superblocks of all partitions on the installation device
doWipeAllPartitions() {
	# sort in reverse order, so that logical partitions are wiped first
	for i in $( getAllPartitions | sort -r ); do
		dd if=/dev/zero of="/dev/$i" bs=1024k count=1
	done
	sync; sync; sync
}

# deletes all partitions on the installation device
doDeleteAllPartitions() {
	# simply create a new empty partition table
	fdisk "$INSTALL_DEVICE" << __END__
o
w
__END__
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
}

# wipes the partition table of the installation device
doWipeDevice() {
	dd if=/dev/zero of="$INSTALL_DEVICE" bs=1024k count=1
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
	partprobe "$INSTALL_DEVICE"
}

# creates the new partitions on the installation device
# NOTE: you can configure the size of the boot partition via BOOT_PARTITION_SIZE
#       see README for further information about the partition/volume layout
doCreateNewPartitions() {
	# first create a new empty partition table, then create the two new primary partitions
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

	# change the partition types (83 = Linux, 8e = Linux LVM)
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

# determines the two new primary partitions
determineNewPartitions() {
	local ALL_PARTITIONS=($( getAllPartitions ))
	# add the missing "/dev/" to the partitions returned by getAllPartitions
	BOOT_PARTITION="/dev/${ALL_PARTITIONS[0]}"
	LUKS_PARTITION="/dev/${ALL_PARTITIONS[1]}"
}

# creates the encrypted partition using LUKS and opens it
# the encrypted partition will host the two LVM volumes "swap" and "root"
doCreateLuksLvm() {
	# this will ask for a password twice (verify)
	cryptsetup -q -y -c aes-xts-plain64 -s 512 -h sha512 luksFormat "$LUKS_PARTITION"
	# this will ask for the password again
	cryptsetup luksOpen "$LUKS_PARTITION" lvm
}

# creates the two LVM volumes "swap" and "root"
# NOTE: you can configure the size of the swap volume via SWAP_VOLUME_SIZE
#       see README for further information about the partition/volume layout
doCreateLvmVolumes() {
	pvcreate /dev/mapper/lvm
	vgcreate main /dev/mapper/lvm
	lvcreate -L "$SWAP_VOLUME_SIZE"M -n swap main
	lvcreate -l 100%FREE -n root main
}

# formats the new partitions and volumes
doFormat() {
	mkfs.ext2 -L boot "$BOOT_PARTITION"
	mkswap -L swap /dev/mapper/main-swap
	mkfs.ext4 -L root /dev/mapper/main-root
}

# mounts the new partitions and volumes
doMount() {
	mount /dev/mapper/main-root /mnt
	mkdir /mnt/boot
	mount "$BOOT_PARTITION" /mnt/boot
	swapon /dev/mapper/main-swap
}

# installs the Arch Linux base system
doPacstrap() {
	pacstrap /mnt base
}

# generates the fstab file
doGenerateFstab() {
	# use UUIDs
	genfstab -p -U /mnt >> /mnt/etc/fstab
}

# copies both the install script and the current conf file into the chroot environment
doCopyToChroot() {
	# create a sub-directory (ideally named after the git checkout folder)
	CHROOT_INSTALL_HOME="/mnt/root/`basename "$INSTALL_HOME"`"
	mkdir -p "$CHROOT_INSTALL_HOME"

	# copy both the install script and the current conf file
	cp -p "${BASH_SOURCE[0]}" "$CHROOT_INSTALL_HOME"
	cp -p "$INSTALL_CONF" "$CHROOT_INSTALL_HOME"
}

# chroots into the new installed system
doChroot() {
	# start the install script inside chroot to continue with the installation process
	local IN_CHROOT_INSTALL_HOME="/root/`basename "$CHROOT_INSTALL_HOME"`"
	local IN_CHROOT_INSTALL_CONF="$IN_CHROOT_INSTALL_HOME/`basename "$INSTALL_CONF"`"

	# the "-c" option tells the install script to continue with the in-chroot part (sets IN_CHROOT="1")
	arch-chroot /mnt /usr/bin/bash -c "'$IN_CHROOT_INSTALL_HOME/$INSTALL_NAME' -c '$IN_CHROOT_INSTALL_CONF'"
}

# sets the hostname
# NOTE: you can configure the hostname via HOSTNAME
#       see README for further information about the available conf settings
doSetHostname() {
	printf "$HOSTNAME\n" > /etc/hostname
}

# sets the time zone
# NOTE: you can configure the timezone via TIMEZONE
#       see README for further information about the available conf settings
doSetTimezone() {
	# the timezone needs to be in /usr/share/zoneinfo
	ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}

# generates the locale about to be set
# NOTE: you can configure the locale via LOCALE
#       see README for further information about the available conf settings
doGenerateLocale() {
	# remove the "#" in front of the desired locale in /etc/locale.gen
	cat /etc/locale.gen | sed -e 's/^#\('"$LOCALE"'\)\s*$/\1/' > /tmp/locale.gen
	cat /tmp/locale.gen > /etc/locale.gen
	rm /tmp/locale.gen

	# generate locale
	locale-gen
}

# sets the locale language
# NOTE: you can configure the locale language via LOCALE_LANG (usually derived from LOCALE)
#       see README for further information about the available conf settings
doSetLocale() {
	# create /etc/locale.conf
	printf "LANG=$LOCALE_LANG\n" > /etc/locale.conf
}

# sets both the keymap and font of the virtual console
# NOTE: you can configure the virtual console via VCONSOLE_*
#       see README for further information about the available conf settings
doSetVConsole() {
	# create /etc/vconsole.conf
	printf "KEYMAP=$VCONSOLE_KEYMAP\n" > /etc/vconsole.conf
	printf "FONT=$VCONSOLE_FONT\n" >> /etc/vconsole.conf
}

# configures and creates the initramfs
doMkinitcpio() {
	# modify the initramfs hooks because of the encrypted partition:
	# - remove "keyboard" (it is probably listed after "filesystems" right now)
	# - add "keyboard" again in front of "filesystems" as well as "keymap encrypt lvm2"
	cat /etc/mkinitcpio.conf | sed -e 's/^\(\(HOOKS\)="\([^"]\+\)"\)$/#\1\n\2="\3"/' > /tmp/mkinitcpio.conf
	cat /tmp/mkinitcpio.conf | awk 'm = $0 ~ /^HOOKS="([^"]+)"$/ { \
			gsub(/keyboard/, "", $0); \
			gsub(/filesystems/, "keyboard keymap encrypt lvm2 filesystems", $0); \
			gsub(/  /, " ", $0); \
			print \
		} !m { print }' > /etc/mkinitcpio.conf
	rm /tmp/mkinitcpio.conf

	# generate initramfs
	mkinitcpio -p linux
}

# sets the root password
doSetRootPassword() {
	# this will ask for a password twice (verify)
	passwd root
}

# determines the UUID of the encrypted partition
determineLuksUuid() {
	LUKS_UUID="`cryptsetup luksUUID "$LUKS_PARTITION"`"
}

# installs the GRUB boot loader
doInstallGrub() {
	# install the package
	pacman -S --noconfirm grub

	# install GRUB into the MBR of the installation device
	grub-install --target=i386-pc --recheck "$INSTALL_DEVICE"

	# modify the kernel parameters because of the encrypted partition:
	# - add information about the encrypted partition (using its UUID)
	# - add information about the root partition
	# - add both keymap and locale (for password input)
	cat /etc/default/grub | sed -e 's/^\(\(GRUB_CMDLINE_LINUX_DEFAULT\)="\([^"]\+\)"\)$/#\1\n\2="\3"/' > /tmp/default-grub
	cat /tmp/default-grub | awk 'm = $0 ~ /^GRUB_CMDLINE_LINUX_DEFAULT="([^"]+)"$/ { \
			gsub(/quiet/, "quiet cryptdevice=UUID=\"'"$LUKS_UUID"'\":main root=/dev/mapper/main-root lang='"$VCONSOLE_KEYMAP"' locale='"$LOCALE_LANG"'", $0); \
			print \
		} !m { print }' > /etc/default/grub
	rm /tmp/default-grub

	# generate GRUB configuration
	grub-mkconfig -o /boot/grub/grub.cfg
}

# creates the crypttab file
doCreateCrypttab() {
	# create /etc/crypttab
	printf "main UUID=\"$LUKS_UUID\" none luks\n" > /etc/crypttab
}

# ========= main program =========

if [ "$IN_CHROOT" == "1" ]; then
# when we are inside the chroot environment

	# configure the new installed system
	doSetHostname
	doSetTimezone
	doGenerateLocale
	doSetLocale
	doSetVConsole

	# create initramfs
	doMkinitcpio

	# set the root password
	doSetRootPassword

	# re-determine partitions and UUID, used for the boot loader installation
	determineNewPartitions
	determineLuksUuid

	# install the GRUB boot loader
	doInstallGrub

	# create the crypttab file
	doCreateCrypttab

	# exit the chroot environment
	exit 0

else
# when we are not inside the chroot environment

	# clean up the installation device
	doDeactivateAllSwaps
	doWipeAllPartitions
	doDeleteAllPartitions
	doWipeDevice

	# create, format and mount the new partitions and volumes
	doCreateNewPartitions
	doWipeAllPartitions
	determineNewPartitions
	doCreateLuksLvm
	doCreateLvmVolumes
	doFormat
	doMount

	# install the Arch Linux base system
	doPacstrap

	# generate the fstab file
	doGenerateFstab

	# chroot into the new installed system
	# NOTE: the install script is copied into the chroot environment then
	#       started again with the "-c" option (sets IN_CHROOT="1")
	doCopyToChroot
	doChroot

fi

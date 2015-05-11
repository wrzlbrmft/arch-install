#!/usr/bin/env bash

INSTALL_HOME=$( cd "`dirname "${BASH_SOURCE[0]}"`" && pwd )
INSTALL_SCRIPT="`basename "${BASH_SOURCE[0]}"`"
INSTALL_NAME="`printf "$INSTALL_SCRIPT" | awk -F '.' '{ print $1 }'`"

doPrint() {
	printf "[$INSTALL_NAME] $*\n"
}

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
INSTALL_OPTIONS="$*"

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

	arch-chroot /mnt /usr/bin/bash -c "'$IN_CHROOT_INSTALL_HOME/$INSTALL_SCRIPT' -c '$IN_CHROOT_INSTALL_CONFIG' $*"
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

	/bin/su - "$SU_USER" -c "'$IN_SU_INSTALL_HOME/$INSTALL_SCRIPT' -c '$IN_SU_INSTALL_CONFIG' $*"
}

doSuSudo() {
	local SU_USER_SUDO_NOPASSWD="/etc/sudoers.d/$SU_USER"

	cat > "$SU_USER_SUDO_NOPASSWD" << __END__
$SU_USER ALL=(ALL) NOPASSWD: ALL
__END__

	doSu $*

	rm "$SU_USER_SUDO_NOPASSWD"
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
	doPrint "Formatting LUKS device"
	cryptsetup -q -y -c aes-xts-plain64 -s 512 -h sha512 luksFormat "$LUKS_DEVICE"

	doPrint "Opening LUKS device"
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
	mkfs -t "$BOOT_FILESYSTEM" -L "$BOOT_LABEL" "$BOOT_DEVICE"
	mkswap -L "$SWAP_LABEL" "$SWAP_DEVICE"
	mkfs -t "$ROOT_FILESYSTEM" -L "$ROOT_LABEL" "$ROOT_DEVICE"
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
	cat > /etc/hostname << __END__
$HOSTNAME
__END__
}

doSetTimezone() {
	ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}

doEnableLocale() {
	cat /etc/locale.gen | sed -e 's/^#\('"$LOCALE"'\)\s*$/\1/' > /tmp/locale.gen
	cat /tmp/locale.gen > /etc/locale.gen
	rm /tmp/locale.gen
}

doGenerateLocale() {
	locale-gen
}

doSetLocale() {
	cat > /etc/locale.conf << __END__
LANG=$LOCALE_LANG
__END__
}

doSetConsole() {
	cat > /etc/vconsole.conf << __END__
KEYMAP=$CONSOLE_KEYMAP
FONT=$CONSOLE_FONT
__END__
}

doEnableServiceDhcpcd() {
	systemctl enable dhcpcd.service
}

doEditMkinitcpioLuks() {
	cat /etc/mkinitcpio.conf | sed -e 's/^\(\(HOOKS\)="\([^"]\+\)"\)$/#\1\n\2="\3"/' > /tmp/mkinitcpio.conf
	cat /tmp/mkinitcpio.conf | awk 'm = $0 ~ /^HOOKS="([^"]+)"$/ {
			gsub(/keyboard/, "", $0);
			gsub(/filesystems/, "keyboard keymap encrypt lvm2 filesystems", $0);
			gsub(/  /, " ", $0);
			print
		} !m { print }' > /etc/mkinitcpio.conf
	rm /tmp/mkinitcpio.conf
}

doMkinitcpio() {
	mkinitcpio -p linux
}

doSetRootPassword() {
	doPrint "Setting password for user 'root'"
	passwd root
}

doInstallGrub() {
	pacman -S --noconfirm --needed grub

	grub-install --target=i386-pc --recheck "$INSTALL_DEVICE"
}

doEditGrubConfig() {
	cat /etc/default/grub | sed -e 's/^\(\(GRUB_CMDLINE_LINUX_DEFAULT\)="\([^"]\+\)"\)$/#\1\n\2="\3"/' > /tmp/default-grub
	cat /tmp/default-grub | awk 'm = $0 ~ /^GRUB_CMDLINE_LINUX_DEFAULT="([^"]+)"$/ {
			gsub(/quiet/, "quiet root='"$ROOT_DEVICE"' lang='"$CONSOLE_KEYMAP"' locale='"$LOCALE_LANG"'", $0);
			print
		} !m { print }' > /etc/default/grub
	rm /tmp/default-grub
}

doDetectLuksUuid() {
	LUKS_UUID="`cryptsetup luksUUID "$LUKS_DEVICE"`"
}

doEditGrubConfigLuks() {
	cat /etc/default/grub | sed -e 's/^\(\(GRUB_CMDLINE_LINUX_DEFAULT\)="\([^"]\+\)"\)$/#\1\n\2="\3"/' > /tmp/default-grub
	cat /tmp/default-grub | awk 'm = $0 ~ /^GRUB_CMDLINE_LINUX_DEFAULT="([^"]+)"$/ {
			gsub(/quiet/, "quiet cryptdevice=UUID=\"'"$LUKS_UUID"'\":'"$LUKS_LVM_NAME"' root='"$ROOT_DEVICE"' lang='"$CONSOLE_KEYMAP"' locale='"$LOCALE_LANG"'", $0);
			print
		} !m { print }' > /etc/default/grub
	rm /tmp/default-grub
}

doGenerateGrubConfig() {
	grub-mkconfig -o /boot/grub/grub.cfg
}

doCreateCrypttabLuks() {
	cat > /etc/crypttab << __END__
$LUKS_LVM_NAME UUID="$LUKS_UUID" none luks
__END__
}

doAddHostUser() {
	groupadd "$HOST_USER_GROUP"

	useradd -g "$HOST_USER_GROUP" -G "$HOST_USER_GROUPS_EXTRA" -d "/$HOST_USER_USERNAME" -s /bin/bash -c "$HOST_USER_REALNAME" -m "$HOST_USER_USERNAME"
	HOST_USER_HOME="`eval printf "~$HOST_USER_USERNAME"`"
	chmod 0751 "$HOST_USER_HOME"
	doPrint "Setting password for host user '$HOST_USER_USERNAME'"
	passwd -l "$HOST_USER_USERNAME"
}

doAddMainUser() {
	useradd -g "$MAIN_USER_GROUP" -G "$MAIN_USER_GROUPS_EXTRA" -s /bin/bash -c "$MAIN_USER_REALNAME" -m "$MAIN_USER_USERNAME"
	MAIN_USER_HOME="`eval printf "~$MAIN_USER_USERNAME"`"
	chmod 0751 "$MAIN_USER_HOME"
	doPrint "Setting password for main user '$MAIN_USER_USERNAME'"
	passwd "$MAIN_USER_USERNAME"
}

doInstallSsh() {
	pacman -S --noconfirm --needed openssh
}

doEnableServiceSshd() {
	systemctl enable sshd.service
}

doInstallSudo() {
	pacman -S --noconfirm --needed sudo

	cat /etc/sudoers | sed -e 's/^#\s*\(%wheel ALL=(ALL) ALL\)$/\1/' > /tmp/sudoers
	cat /tmp/sudoers > /etc/sudoers
	rm /tmp/sudoers
}

doInstallDevel() {
	pacman -S --noconfirm --needed base-devel
}

doCreateSoftwareDirectory() {
	mkdir -p software/aaa.dist
	chmod 0700 software
	chmod 0700 software/aaa.dist
}

doInstallYaourt() {
	doCreateSoftwareDirectory
	cd software/aaa.dist

	curl -O https://aur.archlinux.org/packages/pa/package-query/package-query.tar.gz
	tar xvf package-query.tar.gz
	cd package-query
	makepkg -i -s --noconfirm --needed
	cd ..

	curl -O https://aur.archlinux.org/packages/ya/yaourt/yaourt.tar.gz
	tar xvf yaourt.tar.gz
	cd yaourt
	makepkg -i -s --noconfirm --needed
	cd ..

	cd ../..
}

doYaourt() {
	yaourt -S --noconfirm --needed $INSTALL_OPTIONS
}

doEnableMultilib() {
	cat /etc/pacman.conf | sed -e '/^#\[multilib\]$/ {
			N; /\n#Include/ {
				s/^#//
				s/\n#/\n/
			}
		}' > /tmp/pacman.conf
	cat /tmp/pacman.conf > /etc/pacman.conf
	rm /tmp/pacman.conf

	pacman -Sy
}

doInstallX11() {
	pacman -S --noconfirm --needed \
		xorg-server \
		xorg-server-utils \
		xorg-utils \
		xorg-xinit \
		xorg-fonts-75dpi \
		xorg-fonts-100dpi \
		xorg-twm \
		xorg-xclock \
		xterm \
		$X11_PACKAGES_VIDEO \
		$X11_PACKAGES_EXTRA
}

doX11KeyboardConf() {
	cat > /etc/X11/xorg.conf.d/00-keyboard.conf << __END__
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "$X11_KEYBOARD_LAYOUT"
        Option "XkbModel" "$X11_KEYBOARD_MODEL"
        Option "XkbVariant" "$X11_KEYBOARD_VARIANT"
        Option "XkbOptions" "$X11_KEYBOARD_OPTIONS"
EndSection
__END__
}

doX11InstallFonts() {
	pacman -S --noconfirm --needed \
		ttf-dejavu \
		ttf-droid \
		ttf-liberation \
		ttf-symbola

	doSuSudo suYaourt ttf-ms-fonts
}

doX11InstallXfce() {
	pacman -S --noconfirm --needed \
		xfce4 \
		xfce4-goodies

	doSuSudo suYaourt menulibre
}

doX11InstallUbuntuFontRendering() {
	pacman -Rdd --noconfirm cairo
	doSuSudo suYaourt cairo-ubuntu

	pacman -Rdd --noconfirm cairo
	doSuSudo suYaourt cairo-ubuntu

	pacman -Rdd --noconfirm freetype2
	doSuSudo suYaourt freetype2-ubuntu

	pacman -Rdd --noconfirm fontconfig
	doSuSudo suYaourt fontconfig-ubuntu
}

doUpdateIconCache() {
	for i in $( find /usr/share/icons/* -maxdepth 0 -type d ); do
		gtk-update-icon-cache "$i"
	done
}

doX11InstallThemes() {
	pacman -S --noconfirm --needed numix-themes

	doSuSudo suYaourt \
		xfce-theme-numix-extra-colors \
		gtk-theme-config \
		elementary-xfce-icons \
		xcursor-human

	doUpdateIconCache
}

doX11InstallLightdm() {
	pacman -S --noconfirm --needed \
		lightdm \
		lightdm-gtk-greeter
}

doEnableServiceLightdm() {
	systemctl enable lightdm.service
}

doX11InstallTeamviewer() {
	doSuSudo suYaourt teamviewer
}

doEnableServiceTeamviewerd() {
	systemctl enable teamviewerd
}

doInstallNetworkManager() {
	pacman -S --noconfirm --needed \
		networkmanager \
		networkmanager-vpnc \
		modemmanager

	if [ "$INSTALL_X11" == "yes" ]; then
		pacman -S --noconfirm --needed network-manager-applet
	fi
}

doEnableServiceNetworkManager() {
	systemctl enable NetworkManager.service
}

doInstallPulseaudio() {
	pacman -S --noconfirm --needed \
		pulseaudio \
		pulseaudio-alsa

	if [ "$INSTALL_X11" == "yes" ]; then
		pacman -S --noconfirm --needed \
			paprefs \
			pavucontrol

		doSuSudo suYaourt pulseaudio-ctl
	fi
}

doDisablePcSpeaker() {
	cat >> /etc/modprobe.d/blacklist.conf << __END__
blacklist pcspkr
__END__
}

doInstallPackageSets() {
	for i in $INSTALL_PACKAGE_SETS; do
		j="$i":pacman
		if [ ! -z "${PACKAGE_SET[$j]}" ]; then
			pacman -S --noconfirm --needed ${PACKAGE_SET[$j]}
		fi

		j="$i":yaourt
		if [ ! -z "${PACKAGE_SET[$j]}" ]; then
			doSuSudo suYaourt ${PACKAGE_SET[$j]}
		fi
	done
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
		doChroot chroot

		exit 0
		;;

	chroot)
		doSetHostname
		doSetTimezone

		doEnableLocale
		doGenerateLocale
		doSetLocale

		doSetConsole

		if [ "$ENABLE_SERVICE_DHCPCD" == "yes" ]; then
			doEnableServiceDhcpcd
		fi

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

		if [ "$INSTALL_SSH" == "yes" ]; then
			doInstallSsh

			if [ "$ENABLE_SERVICE_SSHD" == "yes" ]; then
				doEnableServiceSshd
			fi
		fi

		if [ "$INSTALL_SUDO" == "yes" ]; then
			doInstallSudo
		fi

		if [ "$INSTALL_DEVEL" == "yes" ]; then
			doInstallDevel
		fi

		if [ "$INSTALL_YAOURT" == "yes" ]; then
			doCopyToSu
			doSuSudo suInstallYaourt
		fi

		if [ "$ENABLE_MULTILIB" == "yes" ]; then
			doEnableMultilib
		fi

		if [ "$INSTALL_X11" == "yes" ]; then
			doInstallX11

			if [ "$X11_KEYBOARD_CONF" == "yes" ]; then
				doX11KeyboardConf
			fi

			if [ "$X11_INSTALL_FONTS" == "yes" ]; then
				doX11InstallFonts
			fi

			if [ "$X11_INSTALL_XFCE" == "yes" ]; then
				doX11InstallXfce
			fi

			if [ "$X11_INSTALL_UBUNTU_FONT_RENDERING" == "yes" ]; then
				doX11InstallUbuntuFontRendering
			fi

			if [ "$X11_INSTALL_THEMES" == "yes" ]; then
				doX11InstallThemes
			fi

			if [ "$X11_INSTALL_LIGHTDM" == "yes" ]; then
				doX11InstallLightdm

				if [ "$ENABLE_SERVICE_LIGHTDM" == "yes" ]; then
					doEnableServiceLightdm
				fi
			fi

			if [ "$X11_INSTALL_TEAMVIEWER" == "yes" ]; then
				doX11InstallTeamviewer

				if [ "$ENABLE_SERVICE_TEAMVIEWERD" == "yes" ]; then
					doEnableServiceTeamviewerd
				fi
			fi
		fi

		if [ "$INSTALL_NETWORK_MANAGER" == "yes" ]; then
			doInstallNetworkManager

			if [ "$ENABLE_SERVICE_NETWORK_MANAGER" == "yes" ]; then
				doEnableServiceNetworkManager
			fi
		fi

		if [ "$INSTALL_PULSEAUDIO" == "yes" ]; then
			doInstallPulseaudio
		fi

		if [ "$DISABLE_PC_SPEAKER" == "yes" ]; then
			doDisablePcSpeaker
		fi

		if [ ! -z "$INSTALL_PACKAGE_SETS" ]; then
			doInstallPackageSets
		fi

		exit 0
		;;

	suInstallYaourt)
		doInstallYaourt
		exit 0
		;;

	suYaourt)
		doYaourt
		exit 0
		;;

	*)
		printf "ERROR: Unknown target ('$INSTALL_TARGET')\n"
		exit 1
		;;
esac

# arch-install

A highly configurable script installing
[Arch Linux](https://www.archlinux.org/).

## Feature Highlights

* Fully automated installation of a ready-to-use [Arch Linux](https://www.archlinux.org/) system
* Installation to any device, including USB sticks or into a [VirtualBox](https://www.virtualbox.org/) VM
* Auto-detecting SSDs to configure [TRIM](http://en.wikipedia.org/wiki/Trim_(computing))
* Supports both BIOS (legacy) and [EFI/UEFI](http://en.wikipedia.org/wiki/Unified_Extensible_Firmware_Interface) boot methods
  * for BIOS: `grub` boot loader
  * for [EFI/UEFI](http://en.wikipedia.org/wiki/Unified_Extensible_Firmware_Interface): choose between `grub` or the `gummiboot` boot loader
* "One-switch" installation of a fully LVM-on-LUKS encrypted system (also to USB sticks!)
* `yaourt` installation to install [AUR packages](https://aur.archlinux.org/) right away
* Xorg installation
* Optionally install Ubuntu's font rendering (much smoother!)
* [Xfce](http://www.xfce.org/) installation, including the Numix theme and icons
* Graphical user login using LightDM
* Installation of individually configurable software package sets, already
including
  * [Chrome](https://www.google.de/chrome/browser/desktop/), [Firefox](https://www.mozilla.org/firefox/), [Thunderbird](https://www.mozilla.org/thunderbird/), [Skype](http://www.skype.com/), [Pidgin](https://www.pidgin.im/), [TeamViewer](https://www.teamviewer.com/)
  * [GIMP](http://www.gimp.org/), [gThumb](https://wiki.gnome.org/Apps/gthumb), [Shutter](http://shutter-project.org/), [Kazam](https://launchpad.net/kazam)
  * [Dropbox](https://www.dropbox.com/), [FileZilla](https://filezilla-project.org/), [gSTM](http://sourceforge.net/projects/gstm/), [Tor](https://www.torproject.org/)
  * [OpenJDK 8](http://openjdk.java.net/), [LibreOffice](https://www.libreoffice.org)
  * [VLC](http://www.videolan.org/), [Spotify](https://www.spotify.com/), [Banshee](http://banshee.fm/), [Audacity](http://web.audacityteam.org/), [MuseScore](https://musescore.org/)
  * [VirtualBox](https://www.virtualbox.org/)
  * [Ant](http://ant.apache.org/), [Maven](https://maven.apache.org/), [GCC](https://gcc.gnu.org/), [Code::Blocks](http://www.codeblocks.org/), [GCC](https://gcc.gnu.org/) for [AVR](http://www.atmel.com/products/microcontrollers/avr/), [Arduino](https://www.arduino.cc/en/Main/Software), [Fritzing](http://fritzing.org/)
  * [Apache](http://httpd.apache.org/), [MariaDB](https://mariadb.org/), [PHP](http://php.net/), [Composer](https://getcomposer.org/), [Node.js](https://nodejs.org/), [npm](https://www.npmjs.com/), [Google Protocol Buffers](https://developers.google.com/protocol-buffers/)
  * ...
* Optimization settings like `noatime`, swappiness and a better IO scheduler for SSDs

You should look into the configuration file `arch-install.conf` -- almost
everything is configurable...

## Quick Start

*(For a more detailed usage guide scroll down.)*

Boot the [Arch Linux ISO image](https://www.archlinux.org/download/) and type
in:

```
curl -L https://github.com/wrzlbrmft/arch-install/archive/master.tar.gz | tar zxvf -
arch-install-master/arch-install.sh
```

**CAUTION:** The installation will delete *all* existing data on the
installation device including all other partitions and operating systems on it.

After a while, `reboot` and enjoy!

## Usage Guide

Start by downloading(, burning) and booting the latest
[Arch Linux ISO image](https://www.archlinux.org/download/).

After the auto-login as `root`, you can load an alternative keyboard layout,
e.g. *German*:

```
loadkeys de-latin1
```

(on German keyboards: for `y` press `z`, for `-` press `ß`)

Make sure you have a working internet connection:

```
ping -c 3 8.8.8.8
```

To connect to a wireless network use:

```
wifi-menu
```

Next, download and unpack the `arch-install` repository:

```
curl -L https://github.com/wrzlbrmft/arch-install/archive/master.tar.gz | tar zxvf -
arch-install-master/arch-install.sh
```

You may want to change the default configuration:

```
nano -w arch-install-master/arch-install.conf
```

**NOTE:** If you are installing into a [VirtualBox](https://www.virtualbox.org/)
VM, make sure to set both `INSTALL_VIRTUALBOX_GUEST` and
`ENABLE_MODULES_VIRTUALBOX_GUEST` to `yes` and maybe
`ENABLE_MODULES_VIRTUALBOX_HOST` to `no`.

see also: *Configuration/Most Important Settings*

Finally, start the installation process:

```
arch-install-master/arch-install.sh
```

**CAUTION:** The installation will delete *all* existing data on the
installation device including all other partitions and operating systems on it.

**NOTE:** For both the `root` and main user, and also if you enabled the
LVM-on-LUKS encryption, you will have to type in some passwords during the
installation process.

Depending on your computer and internet connection speed, installing the
defaults takes about 60 minutes (downloading 1.8 GB) and uses 11.1 GB of the
installation device.

The installation is done, once you see

```
[arch-install] Wake up, Neo... The installation is done!
```

Finally, reboot your machine:

```
reboot
```

That's it!

## Configuration

*Eventually, I will add more comments to arch-install.conf soon...* :-)

### Most Important Settings

#### INSTALL_DEVICE

*Default:* `/dev/sda`

Definitely the most important setting: where to install
[Arch Linux](https://www.archlinux.org/).

**CAUTION:** The installation will delete *all* existing data on the
installation device including all other partitions and operating systems on it.

#### BOOT_METHOD

*Value:* `legacy` (default) or `efi`

Boot method to be used: `legacy` for BIOS boot, `efi` for
[EFI/UEFI](http://en.wikipedia.org/wiki/Unified_Extensible_Firmware_Interface)
boot. This affects the boot loader configuration.

#### LVM_ON_LUKS

*Value:* `yes` or `no` (default)

Whether to install an LVM-on-LUKS encrypted system. For more information, start
reading on Wikipedia about
[LUKS](http://en.wikipedia.org/wiki/Linux_Unified_Key_Setup) and
[dm-crypt](http://en.wikipedia.org/wiki/Dm-crypt).

#### ADD_MAIN_USER

*Value:* `yes` (default) or `no`

Whether to add a main user. If set to `yes`, have a look at the
`MAIN_USER_USERNAME` and `MAIN_USER_REALNAME` settings.

**CAUTION:** The installation process highly depends on the creation of a main
user (for basically everything being installed by `yaourt`). **Disable at your
own risk!**

#### MAIN_USER_USERNAME, MAIN_USER_REALNAME

If `ADD_MAIN_USER` is set to `yes`, a main user will be created. Use these two
settings to configure its username and the user's realname.

### Using an Alternative Configuration File

You can use an alternative configuration file by passing it to the installation
script:

```
arch-install-master/arch-install.sh -c my.conf
```

## License

This software is distributed under the terms of the
[GNU General Public License v3](https://www.gnu.org/licenses/gpl-3.0.en.html).

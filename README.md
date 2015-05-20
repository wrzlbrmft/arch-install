# arch-install

A highly configurable script installing
[Arch Linux](https://www.archlinux.org/).

*(work in progress)*

## Features

* ...

## Quick Start

*(For a more detailed usage guide scroll down.)*

Boot the [Arch Linux ISO image](https://www.archlinux.org/download/) and type
in:

```
pacman -Sy --noconfirm --needed git
git clone https://github.com/wrzlbrmft/arch-install.git
arch-install/arch-install.sh
```

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

Next, install `git` and checkout the `arch-install` repository:

```
pacman -Sy --noconfirm --needed git
git clone https://github.com/wrzlbrmft/arch-install.git
```

You may want to change the default configuration:

```
nano -w arch-install/arch-install.conf
```

see also: *Configuration/Most Important Settings*

Finally, start the installation process:

```
arch-install/arch-install.sh
```

**NOTE:** For both the `root` and main user, and also if you enabled the
LVM-on-LUKS encryption, you will have to type in some passwords during the
installation process.

Depending on your computer and internet connection speed, the installation takes
45-60 minutes (downloading approx. 1.2 GB).

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

*I will add comments to arch-install.conf soon...* :-)

### Most Important Settings

...

### Using an Alternative Configuration File

You can use an alternative configuration file by passing it to the installation
script:

```
arch-install/arch-install.sh -c my.conf
```

## License

This software is distributed under the terms of the
[GNU General Public License v3](https://www.gnu.org/licenses/gpl-3.0.en.html).

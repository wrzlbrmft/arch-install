#!/usr/bin/env bash
# usage: ./arch-install.sh [-h|--help|<conf>]

case "$1" in
	-h|--help)
		printf "usage: ./arch-install.sh [-h|--help|<conf>]\n"
		exit 0
		;;

	*)
		INSTALL_CONF="$1"
		;;
esac

INSTALL_HOME=$( cd "`dirname "${BASH_SOURCE[0]}"`" && pwd )
INSTALL_NAME="`basename "${BASH_SOURCE[0]}" | awk -F '.' '{ print $1 }'`"

if [ -z "$INSTALL_CONF" ]; then
	INSTALL_CONF="$INSTALL_HOME/$INSTALL_NAME.conf"
fi

if [ ! -f "$INSTALL_CONF" ]; then
	printf "ERROR: File not found ('$INSTALL_CONF')\n"
	exit 1
fi

. "$INSTALL_CONF"

printf "$INSTALL_DEVICE\n"

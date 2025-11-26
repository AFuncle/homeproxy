#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2022-2025 ImmortalWrt.org

NAME="homeproxy"

RESOURCES_DIR="/etc/$NAME/resources"
mkdir -p "$RESOURCES_DIR"

RUN_DIR="/var/run/$NAME"
LOG_PATH="$RUN_DIR/$NAME.log"
mkdir -p "$RUN_DIR"

log() {
	echo -e "$(date "+%Y-%m-%d %H:%M:%S") $*" >> "$LOG_PATH"
}

to_upper() {
	echo -e "$1" | tr "[a-z]" "[A-Z]"
}

check_geodata_update() {
	local type="$1"
	local pkg="$2"
	local lock="$RUN_DIR/update_resources-$type.lock"

	exec 200>"$lock"
	if ! flock -n 200 &> "/dev/null"; then
		log "[$(to_upper "$type")] A task is already running."
		return 2
	fi

	log "[$(to_upper "$type")] Checking for updates..."

	# Update package list
	opkg update > /dev/null 2>&1

	# Check if update available
	local installed_ver="$(opkg list-installed "$pkg" 2>/dev/null | awk '{print $3}')"
	local available_ver="$(opkg list "$pkg" 2>/dev/null | awk '{print $3}')"

	if [ -z "$installed_ver" ]; then
		log "[$(to_upper "$type")] Package not installed, installing..."
		if opkg install "$pkg" > /dev/null 2>&1; then
			log "[$(to_upper "$type")] Successfully installed."
			# Create symlink for Xray
			mkdir -p /usr/share/xray
			ln -sf "/usr/share/v2ray/${type}.dat" "/usr/share/xray/${type}.dat" 2>/dev/null
			return 0
		else
			log "[$(to_upper "$type")] Installation failed."
			return 1
		fi
	fi

	if [ "$installed_ver" = "$available_ver" ]; then
		log "[$(to_upper "$type")] Current version: $installed_ver"
		log "[$(to_upper "$type")] You're already at the latest version."
		return 3
	fi

	log "[$(to_upper "$type")] Local version: $installed_ver, latest version: $available_ver"

	if opkg upgrade "$pkg" > /dev/null 2>&1; then
		log "[$(to_upper "$type")] Successfully updated to $available_ver."
		return 0
	else
		log "[$(to_upper "$type")] Update failed."
		return 1
	fi
}

case "$1" in
"geoip")
	check_geodata_update "geoip" "v2ray-geoip"
	;;
"geosite")
	check_geodata_update "geosite" "v2ray-geosite"
	;;
*)
	echo -e "Usage: $0 <geoip / geosite>"
	exit 1
	;;
esac

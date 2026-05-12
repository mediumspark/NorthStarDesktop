#!/bin/sh
printf '\033c\033]0;%s\a' NorthStarDesktop
base_path="$(dirname "$(realpath "$0")")"
"$base_path/LinuxBuild.x86_64" "$@"

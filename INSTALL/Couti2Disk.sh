#!/bin/sh
# Public Couti entry point; preserve the existing installer implementation.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
exec sh "$script_dir/Ventoy2Disk.sh" "$@"

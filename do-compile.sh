#!/bin/bash

set -e

my_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


main () {
    local config_name="$1"

    compile_config "$config_name"
}


compile_config () {
    local config_name="$1"
    local config_path="$my_dir/configs/$config_name.config"
    local env_path="$my_dir/env/$config_name"

    . "$env_path"
    : "${ARCH:?ARCH must be set}"
    : "${CROSS_COMPILE:?CROSS_COMPILE must be set}"
    : "${CC:?CC must be set}"
    : "${SOURCE:?SOURCE must be set}"
    : "${JOBS:?JOBS must be set}"

    local tmpdir="$(mktemp --tmpdir -d penguinshake.$config_name.XXXXXX)"

    echo "Compiling config $config_name (ARCH=$ARCH)"
    echo "SOURCE=$SOURCE"
    echo "TMPDIR=$tmpdir"

    cp "$config_path" "$tmpdir/.config"

    pushd "$SOURCE"
        make -j "$JOBS" O="$tmpdir" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" CC="$CC" syncconfig
        time make -j "$JOBS" O="$tmpdir" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" CC="$CC"
    popd
}


main "$@"

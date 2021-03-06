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
    local install_prefix="$(mktemp --tmpdir -d penguinshakedist.$config_name.XXXXXX)"
    local install_path="$install_prefix/boot"
    local commit_hash="$(get_commit_hash "$SOURCE")"
    local dist_path="$my_dir/dist/$config_name.$commit_hash.tar.zst"

    echo "Compiling config $config_name (ARCH=$ARCH)"
    echo "SOURCE=$SOURCE (commit $commit_hash)"
    echo "TMPDIR=$tmpdir"
    echo "INSTALL_PREFIX=$install_prefix"

    cp "$config_path" "$tmpdir/.config"

    pushd "$SOURCE"
        # sync config and copy back if changed
        [[ "x$MENUCONFIG" != "x" ]] && make -j "$JOBS" O="$tmpdir" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" CC="$CC" menuconfig
        make -j "$JOBS" O="$tmpdir" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" CC="$CC" syncconfig
        cmp "$config_path" "$tmpdir/.config" || cp "$tmpdir/.config" "${config_path}.new"

        time make -j "$JOBS" O="$tmpdir" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" CC="$CC"

        # assemble dist root
        prepare_install_prefix "$install_prefix"

        # dist
        make -j "$JOBS" O="$tmpdir" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" CC="$CC" INSTALL_PATH="$install_path" INSTALL_MOD_PATH="$install_prefix" install modules_install
    popd

    # remove vmlinux if vmlinuz is found
    find "$install_path" -type f -name 'vmlinuz-*' > /dev/null && rm -f "$install_path/vmlinux-"*

    # package
    pushd "$install_prefix"
        tar -c -f "$dist_path" --zstd -v --owner root:0 --group root:0 .
    popd

    # cleanup
    rm -rf "$install_prefix"
    rm -rf "$tmpdir"
}

prepare_install_prefix () {
    local prefix="$1"

    chmod 0755 "$prefix"
    mkdir -p "$prefix/boot"
    mkdir -p "$prefix/lib/modules"
}

get_commit_hash () {
    local srcdir="$1"

    ( cd "$srcdir" && git rev-parse HEAD )
}

main "$@"

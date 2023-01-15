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
    : "${SOURCE:?SOURCE must be set}"
    : "${JOBS:?JOBS must be set}"

    if [[ -z $LLVM ]]; then
        : "${CROSS_COMPILE:?CROSS_COMPILE must be set}"
        : "${CC:?CC must be set}"
    fi

    local keep_sources=false
    [[ -n $KEEP_SOURCES ]] && keep_sources=true

    local merge_usr=false
    [[ -n $MERGE_USR ]] && merge_usr=true

    local tmpdir
    if ! "$keep_sources"; then
        tmpdir="$(mktemp --tmpdir -d penguinshake.$config_name.XXXXXX)"
    else
        tmpdir="/tmp/penguinshake.$config_name"
        [[ -d "$tmpdir" ]] || mkdir -p "$tmpdir"
    fi

    local install_prefix="$(mktemp --tmpdir -d penguinshakedist.$config_name.XXXXXX)"
    local install_path="$install_prefix/boot"
    local commit_hash="$(get_commit_hash "$SOURCE")"
    local dist_relpath="dist/$config_name.$commit_hash.tar.zst"
    local dist_path="$my_dir/$dist_relpath"
    local install_mod_path="$install_prefix"

    "$merge_usr" && install_mod_path="$install_mod_path/usr"

    local make_args=(
        -j "$JOBS"
        O="$tmpdir"
        ARCH="$ARCH"
    )

    [[ -n $LLVM ]] && make_args+=( LLVM="$LLVM" )
    [[ -n $CROSS_COMPILE ]] && make_args+=( CROSS_COMPILE="$CROSS_COMPILE" )
    [[ -n $CC ]] && make_args+=( CC="$CC" )

    echo "Compiling config $config_name (ARCH=$ARCH)"
    echo "SOURCE=$SOURCE (commit $commit_hash)"
    echo "TMPDIR=$tmpdir"
    echo "INSTALL_PREFIX=$install_prefix"
    echo "make args:" "${make_args[@]}"

    cp "$config_path" "$tmpdir/.config"

    pushd "$SOURCE"
        # sync config and copy back if changed
        [[ -n $MENUCONFIG ]] && make "${make_args[@]}" menuconfig
        make "${make_args[@]}" syncconfig
        cmp "$config_path" "$tmpdir/.config" || cp "$tmpdir/.config" "${config_path}.new"

        time make "${make_args[@]}"

        # assemble dist root
        prepare_install_prefix "$install_prefix" "$merge_usr"

        # dist
        make "${make_args[@]}" INSTALL_PATH="$install_path" INSTALL_MOD_PATH="$install_mod_path" install modules_install
    popd

    # remove vmlinux if vmlinuz is found
    local has_vmlinuz="$(find "$install_path" -type f -name 'vmlinuz-*' | wc -l)"
    if [[ "$has_vmlinuz" -ne 0 ]]; then
        rm -f "$install_path/vmlinux-"*
    fi

    # package
    pushd "$install_prefix"
        tar -c -f "$dist_path" --zstd -v --owner root:0 --group root:0 .
    popd

    # cleanup
    rm -rf "$install_prefix"
    "$keep_sources" || rm -rf "$tmpdir"

    echo
    echo "Successfully built $dist_relpath"
    echo
}

prepare_install_prefix () {
    local prefix="$1"
    local merge_usr="$2"

    chmod 0755 "$prefix"
    mkdir -p "$prefix/boot"
    if $merge_usr; then
        mkdir -p "$prefix/usr/lib/modules"
    else
        mkdir -p "$prefix/lib/modules"
    fi
}

get_commit_hash () {
    local srcdir="$1"

    ( cd "$srcdir" && git rev-parse HEAD )
}

main "$@"

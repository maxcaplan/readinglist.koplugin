#!/usr/bin/env bash
#
# Desc: Compress plugin files to zip archive for distribution.
# Version: 0.1
# Author: Max Caplan
# License: See LICENSE file.
#

# Set script usage function
usage() {
    printf '%s\n' "" \
        "Usage: $0 [-i FILE | FILE] [-o DIR | DIR] [-n NAME] [-v VERSION] [-f FILTER] [-h]" \
        "" \
        "Compress plugin files to zip archive for distribution" \
        "" \
        "Arguments:" \
        "   FILE    Plugin meta data file [default: .pluginmeta]" \
        "   DIR     Plugin release output directory [default: dist]" \
        "" \
        "Options:" \
        "   -h          Display this message" \
        "   -i FILE     Plugin meta data file" \
        "   -o DIR      Plugin release output directory" \
        "   -n NAME     Plugin name meta data" \
        "   -v VERSION  Plugin version meta data" \
        "   -f FILTER   Plugin release filter file [default: .releaseignore]" \
        ""
}

# Positional arguments
ARGS=()

# Plugin meta data file default value
PLUGIN_META_FILE_DEFAULT=.pluginmeta
# Release output directory default value
OUT_DIR_DEFAULT=dist

release_ignore=.releaseignore

# Get script arguments
while [ $# -gt 0 ]; do
    # Get option arguments
    while getopts "hn:v:i:o:f:" opt; do
        case $opt in
        h)
            usage
            exit 0
            ;;
        n) plugin_name="$OPTARG" ;;
        v) plugin_version="$OPTARG" ;;
        i) plugin_meta_file="$OPTARG" ;;
        o) out_dir="$OPTARG" ;;
        f) release_ignore="$OPTARG" ;;
        \?)
            usage
            exit 1
            ;;
        :)
            printf "Option -$OPTARG requires an argument." 1>&2
            exit 1
            ;;
        esac
    done
    [ $? -eq 0 ] || exit 1
    [ $OPTIND -gt $# ] && break # All arguments processed

    # Remove processed option arguments
    shift $(($OPTIND - 1))
    OPTIND=1

    # Get positional argument
    ARGS[${#ARGS[*]}]=$1

    # Remove processed positional argument
    shift
done

# Set plugin meta file to positional argument if unset
if [ -z "$plugin_meta_file" ]; then
    plugin_meta_file="${ARGS[0]}"
    ARGS=("${ARGS[@]:1}") # Remove first positional argument
fi

# Set release out dir to positional argument if unset
if [ -z "$out_dir" ]; then
    out_dir="${ARGS[0]}"
    ARGS=("${ARGS[@]:1}") # Remove first positional argument
fi

# Set plugin meta file to default value if unset
if [ -z "$plugin_meta_file" ]; then
    plugin_meta_file="$PLUGIN_META_FILE_DEFAULT"
fi

# Set release out dir to default value if unset
if [ -z "$out_dir" ]; then
    out_dir="$OUT_DIR_DEFAULT"
fi

printf "Creating release archive...\n\n"

# Create dist folder
mkdir -p "$out_dir"

# Get the value of the first key of a key value pair found in a file.
# Example: keyvalue file "KEY" "key" "Key"
function keyvalue() {
    local meta_file="${1}"
    shift
    local keys=("${@}")

    # Ensure meta file
    if [ ! -f "$plugin_meta_file" ]; then
        printf "Release failed: Plugin meta file not found: $plugin_meta_file\n" 1>&2
        exit 1
    fi

    for key in "${keys[@]}"; do
        local res=$(grep "^$key" $meta_file | cut -d'=' -f2-)
        if [ ! -z "$res" ]; then
            echo "$res"
            break
        fi
    done
}

if [ -z "$plugin_name" ] || [ -z "$plugin_version" ]; then
    printf "Getting plugin meta data from $plugin_meta_file\n"
fi

# Get plugin name from meta file if unset
if [ -z "$plugin_name" ]; then
    plugin_name=$(keyvalue "$plugin_meta_file" "NAME" "name" "Name") || exit "$?"
fi

# Get plugin version from meta file if unset
if [ -z "$plugin_version" ]; then
    plugin_version=$(keyvalue "$plugin_meta_file" "VERSION" "version" "Version") || exit "$?"
fi

# Ensure a plugin name is set
if [ -z "$plugin_name" ]; then
    printf "Release failed: Plugin name not set or found in $plugin_meta_file\n" 1>&2
    exit 1
fi

# Ensure a plugin version is set
if [ -z "$plugin_version" ]; then
    printf "Release failed: Plugin version not set or found in $plugin_meta_file" 1>&2
    exit 1
fi

# Create plugin folder and archive names
plugin_dir_name="$plugin_name.koplugin"
plugin_archive_name="$plugin_name-v${plugin_version//./-}.zip"

printf "Plugin meta data:\n"
printf "  Plugin Name: $plugin_name\n"
printf "  Plugin Version: $plugin_version\n\n"

printf "Plugin directory name: $plugin_dir_name\n"
printf "Release output: $out_dir/$plugin_archive_name\n\n"

# Remove any existing files for same plugin version
rm -rf "$out_dir/$plugin_dir_name"
rm -f "$out_dir/$plugin_archive_name"

printf "Copying plugin files to $out_dir/$plugin_dir_name:\n\n"

# Create temp plugin folder
mkdir -p "$out_dir/$plugin_dir_name"

# Copy release files to temp folder
rsync -av --filter="dir-merge,- .gitignore" --filter="dir-merge,- $release_ignore" . "$out_dir/$plugin_dir_name" | sed 's/^/  /'

printf "\nCreating release archive $plugin_archive_name:\n\n"

# Compress release files to zip archive
(
    HERE=$PWD
    cd "$out_dir" && zip -r9 "$HERE/$out_dir/$plugin_archive_name" . -i "$plugin_dir_name/*"
)

printf "\nRelease archive created: $out_dir/$plugin_archive_name\n"
printf "Cleaning up\n"

#remove temp plugin folder
rm -rf "$out_dir/$plugin_dir_name"

printf "Done!\n"

exit 0

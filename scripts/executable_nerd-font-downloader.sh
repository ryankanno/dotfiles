#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

declare distro extension font_choice version release_json workdir
declare -a fonts=()

DEPENDENCIES=("wget" "unzip" "tar" "fontconfig" "jq" "curl")

cleanup() {
  if [[ -n "${workdir:-}" && -d "$workdir" ]]; then
    rm -rf "$workdir"
  fi
}
trap cleanup EXIT

install_dependencies() {
  echo "Installing dependencies. Please wait..."

  case "$distro" in
    "debian" | "ubuntu")
      sudo apt-get update > /dev/null 2>&1
      sudo apt-get install -y "${DEPENDENCIES[@]}" > /dev/null 2>&1
      ;;
    "fedora")
      sudo dnf install -y "${DEPENDENCIES[@]}" > /dev/null 2>&1
      ;;
    "arch")
      sudo pacman -Sy --noconfirm "${DEPENDENCIES[@]}" > /dev/null 2>&1
      ;;
    "osx")
      yes | brew install "${DEPENDENCIES[@]}" > /dev/null 2>&1
      ;;
    *)
      echo "Unsupported distribution. Exiting."
      exit 1
      ;;
  esac
}

choose_distro() {
  echo "Select your base distribution:"
  echo "[1] - Debian/Ubuntu"
  echo "[2] - Fedora"
  echo "[3] - Arch Linux"
  echo "[4] - OSX"
  echo "We will install these necessary dependencies: ${DEPENDENCIES[*]}."
  read -rp "Enter the number of your base distribution: " distro_choice

  case "$distro_choice" in
    1) distro="debian";;
    2) distro="fedora";;
    3) distro="arch";;
    4) distro="osx";;
    *) echo "Invalid choice. Exiting."; exit 1 ;;
  esac
}

# One API call populates both the version tag and the font list from release assets.
choose_version() {
  read -rp "Enter the version (press Enter for the latest version): " version

  local url
  if [[ -z "$version" ]]; then
    url="https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"
  else
    url="https://api.github.com/repos/ryanoasis/nerd-fonts/releases/tags/${version}"
  fi

  release_json=$(curl -fsSL "$url") || { echo "Error: failed to fetch release info from GitHub."; exit 1; }

  version=$(echo "$release_json" | jq -r '.tag_name')
  if [[ -z "$version" || "$version" == "null" ]]; then
    echo "Error: could not resolve release tag."
    exit 1
  fi
  echo "Using Nerd Font version: $version"

  while IFS= read -r line; do
    fonts+=("$line")
  done < <(echo "$release_json" | jq -r '.assets[].name | select(endswith(".zip")) | rtrimstr(".zip")' | sort)

  if [[ ${#fonts[@]} -eq 0 ]]; then
    echo "Error: no font assets found for '$version'."
    exit 1
  fi
}

choose_extension() {
  echo "Choose the extension to install:"
  echo "[1] - .zip"
  echo "[2] - .tar.xz"
  read -rp "Enter the number of the desired extension: " extension_choice

  case "$extension_choice" in
    1) extension=".zip";;
    2) extension=".tar.xz";;
    *) echo "Invalid extension choice. Exiting."; exit 1 ;;
  esac
}

choose_font() {
  echo "Choose the font to install or select 'All' to download all fonts:"

  for i in "${!fonts[@]}"; do
    echo "[$((i+1))] - ${fonts[$i]}"
  done

  echo "[$((${#fonts[@]} + 1))] - All Fonts"
  read -rp "Enter your choice: " font_choice
}

download_and_install_font() {
  local selected_font="$1"
  local archive="${workdir}/${selected_font}${extension}"
  local download_url="https://github.com/ryanoasis/nerd-fonts/releases/download/${version}/${selected_font}${extension}"
  local font_dir

  case "$distro" in
    "osx") font_dir="/Library/Fonts";;
    *) font_dir="${HOME}/.local/share/fonts"; mkdir -p "$font_dir";;
  esac

  echo "Downloading and installing '$selected_font'..."

  wget --quiet "$download_url" -O "$archive" || { echo "Error: Unable to download '$selected_font'."; return 1; }

  if [[ "$extension" == ".zip" ]]; then
    unzip -q "$archive" -d "$font_dir" || { echo "Error: Unable to extract '$selected_font'."; return 1; }
  else
    tar -xf "$archive" -C "$font_dir" || { echo "Error: Unable to extract '$selected_font'."; return 1; }
  fi

  rm -f "$archive"
  echo "'$selected_font' installed successfully."
}

workdir=$(mktemp -d)

choose_distro
install_dependencies
choose_version
choose_extension
choose_font

if [[ "$font_choice" -eq "$((${#fonts[@]} + 1))" ]]; then
  for font in "${fonts[@]}"; do
    download_and_install_font "$font"
  done
else
  selected_font="${fonts[$((font_choice-1))]}"
  download_and_install_font "$selected_font"
fi

if command -v fc-cache &> /dev/null; then
  fc-cache -f > /dev/null || { echo "Error: Unable to update font cache. Exiting."; exit 1; }
  echo "Font cache updated."
else
  echo "Command 'fc-cache' not found. Make sure to have the necessary dependencies installed to update the font cache."
fi

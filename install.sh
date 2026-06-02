#!/usr/bin/env bash

set -euo pipefail

lsblk
echo ""

read -rp "Enter drive location (e.g., /dev/sda or /dev/nvme0n1): " DRIVE
read -rp "Enter Swap Partition Number: " SWAP_PART_NUM
read -rp "Enter EFI Partition Number: " BOOT_PART_NUM
read -rp "Enter Root Partition Number: " ROOT_PART_NUM
echo ""

if [[ "$DRIVE" =~ nvme|mmcblk|loop ]]; then
    PART_PREFIX="p"
else
    PART_PREFIX=""
fi

if [[ ! -b "$DRIVE" ]]; then
  echo "Error: $DRIVE is not a block device." >&2
  exit 1
fi

if [[ ! "$SWAP_PART_NUM" =~ ^[0-9]+$ ]] || \
   [[ ! "$BOOT_PART_NUM" =~ ^[0-9]+$ ]] || \
   [[ ! "$ROOT_PART_NUM" =~ ^[0-9]+$ ]]; then
  echo "Error: Partition numbers must be integers." >&2
  exit 1
fi

SWAP_PART="${DRIVE}${PART_PREFIX}${SWAP_PART_NUM}"
BOOT_PART="${DRIVE}${PART_PREFIX}${BOOT_PART_NUM}"
ROOT_PART="${DRIVE}${PART_PREFIX}${ROOT_PART_NUM}"

for PART in "$BOOT_PART" "$SWAP_PART" "$ROOT_PART"; do
  if [[ ! -b "$PART" ]]; then
    echo "Error: $PART is not a block device." >&2
    exit 1
  fi
done

echo "Will format: $BOOT_PART (FAT32), $SWAP_PART (swap), $ROOT_PART (ext4)"
read -rp "Proceed? This is destructive. [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 1

echo "Formatting filesystems: "
mkfs.fat -F 32 "${BOOT_PART}"
mkswap "${SWAP_PART}"
mkfs.ext4 -F "${ROOT_PART}"

echo ""
echo "Mounting filesystems.."
swapon "${SWAP_PART}"
mount "${ROOT_PART}" /mnt
mount --mkdir "${BOOT_PART}" /mnt/boot

echo "Installing Base System..."
pacstrap -K /mnt base base-devel linux linux-firmware linux-headers linux-lts linux-lts-headers nano networkmanager neovim sudo intel-ucode nvidia-dkms nvidia-utils nvidia-settings nvidia-prime ddcutil bluez bluez-utils wayland alacritty fish git adw-gtk-theme gtk4 inter-font man-db niri otf-monaspace pipewire pipewire-alsa pipewire-pulse pipewire-jack power-profiles-daemon qt5-wayland qt6-wayland sddm thunar wlsunset thunar-volman gvfs xdg-user-dirs xorg-xhost xorg-xwayland xwayland-satellite zathura zathura-pdf-mupdf ufw playerctl

echo ""
echo "Generating FSTAB..."
genfstab -U /mnt >> /mnt/etc/fstab

read -rp "Enter Hostname: " HOSTNAME
read -rsp "Enter Root Password: " ROOT_PASSWORD
echo ""
read -rp "Enter Username: " USERNAME
read -rsp "Enter User Password: " USER_PASSWORD
echo ""

read -rp "Enter Dotfiles GitHub URL: " DOTFILES_URL
echo ""

echo "Passing Variables to Chroot.."
mkdir -p /mnt/home
install -m 600 /dev/null /mnt/home/install_vars.sh
cat <<EOF >> /mnt/home/install_vars.sh
export HOSTNAME="${HOSTNAME}"
export ROOT_PASSWORD="${ROOT_PASSWORD}"
export USERNAME="${USERNAME}"
export USER_PASSWORD="${USER_PASSWORD}"
export DOTFILES_URL="${DOTFILES_URL}"
EOF

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install -m 700 "$SCRIPT_DIR/chroot_setup.sh" /mnt/home/chroot_setup.sh

echo "Executing Chroot Script.."
arch-chroot /mnt /home/chroot_setup.sh

echo "Safe to reboot..."

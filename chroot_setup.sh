#!/usr/bin/env bash

set -euo pipefail

source /home/install_vars.sh

ln -sf /usr/share/zoneinfo/America/Denver /etc/localtime
hwclock --systohc

echo "Configuring Locales.."
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "Configuring Network.."
echo "$HOSTNAME" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

echo "Setting Passwords and Users.."
printf '%s:%s\n' root "$ROOT_PASSWORD" | chpasswd

useradd -m -G wheel -s /bin/bash "$USERNAME"
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd


echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-installer
chmod 440 /etc/sudoers.d/10-installer

echo "Installing Bootloader.."
bootctl install

cat <<EOF > /boot/loader/loader.conf
default arch.conf
timeout 0
EOF

ROOT_UUID=$(blkid -s UUID -o value $(df / | tail -n 1 | awk '{print $1}'))

cat <<EOF > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=UUID=$ROOT_UUID quiet splash nvidia_drm.modeset=1 intel_iommu=on iommu=pt rw
EOF

cat <<EOF > /boot/loader/entries/arch-lts.conf
title   Arch Linux LTS
linux   /vmlinuz-linux-lts
initrd  /intel-ucode.img
initrd  /initramfs-linux-lts.img
options root=UUID=$ROOT_UUID quiet splash nvidia_drm.modeset=1 intel_iommu=on iommu=pt rw
EOF

echo "Configuring UFW Firewall Rules.."
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

echo "Enabling System Services.."
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable ufw
systemctl enable bluetooth

sudo -u "$USERNAME" bash -c "xdg-user-dirs-update"

echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-temp-nopasswd

echo "Installing Yay (AUR Helper).."
sudo -u "$USERNAME" bash -c "
  cd /home/$USERNAME
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
  cd ..
  rm -rf yay
"


echo "Installing Noctalia Shell..."
sudo -u "$USERNAME" bash -c "yay -S --noconfirm noctalia-shell"
sudo -u "$USERNAME" bash -c "yay -S --noconfirm brave-bin"

rm /etc/sudoers.d/99-temp-nopasswd

echo "Deploying Custom Dotfiles.."
if [ -n "$DOTFILES_URL" ]; then
  sudo -u "$USERNAME" bash -c "
    cd /home/$USERNAME
    git clone --bare \"$DOTFILES_URL\" \$HOME/.cfg
    function config {
       /usr/bin/git --git-dir=\$HOME/.cfg/ --work-tree=\$HOME \"\$@\"
    }
    mkdir -p .config-backup
    config checkout 2>&1 | grep -E '^\s+' | awk '{print \$1}' | xargs -I{} mv {} .config-backup/{}
    config checkout
    config config --local status.showUntrackedFiles no
  "
else
  echo "No Dotfiles URL provided; skipping config deployment."
fi

echo "Cleaning Up Configuration Scripts.."
rm /home/install_vars.sh
rm /home/chroot_setup.sh

exit

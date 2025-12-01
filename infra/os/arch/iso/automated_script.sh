#!/usr/bin/env bash
set -euxo pipefail

log() { echo "==> $*"; printf "==> %s\n" "$*" >> /root/installer.log; }
log "Starting automated Arch install at $(date)"

# --- Pacman keyring prep ---
rm -rf /etc/pacman.d/gnupg || true
mkdir -p /etc/pacman.d/gnupg
killall dirmngr gpg-agent 2>/dev/null || true
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm archlinux-keyring

# --- Pick target disk ---
pick_disk() {
  for d in /dev/vda /dev/sda /dev/nvme0n1; do
    [ -b "$d" ] && echo "$d" && return 0
  done
  log "No suitable disk found"; exit 1
}
DISK="$(pick_disk)"
log "Using disk: $DISK"

# --- Partition + filesystem ---
swapoff -a || true
umount -R /mnt || true
dd if=/dev/zero of="$DISK" bs=1M count=8 conv=fsync || true
blkdiscard "$DISK" || true
parted -s "$DISK" mklabel msdos
parted -s "$DISK" mkpart primary ext4 1MiB 100%
parted -s "$DISK" set 1 boot on
[[ "$DISK" =~ nvme ]] && PART="${DISK}p1" || PART="${DISK}1"
mkfs.ext4 -F "$PART"
mount "$PART" /mnt

# --- Base system into /mnt ---
pacstrap -K /mnt base linux linux-firmware grub openssh qemu-guest-agent sudo vi cloud-init cloud-guest-utils
genfstab -U /mnt >> /mnt/etc/fstab

# --- Configure inside target ---
arch-chroot /mnt /bin/bash -eux <<'CHROOT'
set -euxo pipefail

# Locale/time/hostname
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "arch-ci" > /etc/hostname

# Console keymap
printf "KEYMAP=us\nFONT=\nFONT_MAP=\n" > /etc/vconsole.conf

# SSH hardening
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# Cloud-init configuration
mkdir -p /etc/cloud/cloud.cfg.d
cat >/etc/cloud/cloud.cfg.d/90_pve.cfg <<'EOF_CFG'
datasource_list: [ NoCloud, ConfigDrive ]
EOF_CFG

# Define a default user so cloud-init creates it
cat >/etc/cloud/cloud.cfg.d/99_default_user.cfg <<'EOF_USER'
system_info:
  default_user:
    name: lab
    gecos: Lab User
    groups: [ wheel, users ]
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
EOF_USER

# --- Networking via systemd-networkd (DHCP on all common NICs) ---
mkdir -p /etc/systemd/network
cat >/etc/systemd/network/20-dhcp.network <<'EOF_NET'
[Match]
Name=en* eth* ens* enp*

[Network]
DHCP=yes
EOF_NET

ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true

# Enable services for FIRST BOOT (no --now inside chroot)
systemctl enable systemd-networkd.service systemd-resolved.service
systemctl enable sshd.service qemu-guest-agent.service
systemctl enable cloud-init-local.service cloud-init-main.service cloud-config.service cloud-final.service

# Install GRUB (BIOS mode)
if [[ -b /dev/vda ]]; then grub-install --target=i386-pc /dev/vda
elif [[ -b /dev/sda ]]; then grub-install --target=i386-pc /dev/sda
elif [[ -b /dev/nvme0n1 ]]; then grub-install --target=i386-pc /dev/nvme0n1
else echo "No disk for grub-install" >&2; exit 1; fi
grub-mkconfig -o /boot/grub/grub.cfg

# Regenerate initramfs
mkinitcpio -P

# Lock root (cloud-init will handle user + key)
passwd -l root || true
CHROOT

sync
log "Install complete; powering off"
sleep 2
systemctl poweroff -i

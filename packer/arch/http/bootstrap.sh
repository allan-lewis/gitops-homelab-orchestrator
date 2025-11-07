#!/usr/bin/env bash
#
# Unattended Arch install for Proxmox golden image (BIOS).
# - Partitions the first disk (MBR), single ext4 root
# - Installs base + linux + cloud-init + qemu-guest-agent + openssh
# - Enables services, basic SSH hardening, sets UTC, en_US.UTF-8
# - Powers off when done (Packer will convert to template)
#
set -euxo pipefail

echo "==> Starting bootstrap at $(date)"

# --- Pick the target disk (virtio, scsi, nvme) --------------------------------
pick_disk() {
  for d in /dev/vda /dev/sda /dev/nvme0n1; do
    [ -b "$d" ] && echo "$d" && return 0
  done
  echo "No suitable disk found" >&2
  exit 1
}
DISK="$(pick_disk)"
echo "==> Using disk: $DISK"

# --- Wipe and create 1 bootable MBR partition ---------------------------------
swapoff -a || true
umount -R /mnt || true

# Wipe first MiB & last 100MiB to avoid leftovers
dd if=/dev/zero of="$DISK" bs=1M count=8 conv=fsync || true
blkdiscard "$DISK" || true

parted -s "$DISK" mklabel msdos
# leave a little room at end; use 1MiB alignment
parted -s "$DISK" mkpart primary ext4 1MiB 100%
parted -s "$DISK" set 1 boot on

# Map the partition name across device types
if [[ "$DISK" =~ nvme ]]; then
  PART="${DISK}p1"
else
  PART="${DISK}1"
fi

# --- Filesystems & mount -------------------------------------------------------
mkfs.ext4 -F "$PART"
mount "$PART" /mnt

# --- Base system ---------------------------------------------------------------
# Refresh keyring in case ISO is old
pacman -Sy --noconfirm archlinux-keyring
# Minimal but cloud-ready base
pacstrap -K /mnt \
  base linux linux-firmware \
  openssh qemu-guest-agent cloud-init cloud-guest-utils sudo vi

genfstab -U /mnt >> /mnt/etc/fstab

# --- Chroot config -------------------------------------------------------------
arch-chroot /mnt /bin/bash -eux <<'CHROOT'
set -euxo pipefail

# Locale & timezone
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Hostname (cloud-init will override; set a sane default)
echo "arch-ci" > /etc/hostname

# Basic SSH hardening (cloud-init will add users/keys)
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# Ensure cloud-init uses the NoCloud datasource provided by Proxmox
mkdir -p /etc/cloud/cloud.cfg.d
cat >/etc/cloud/cloud.cfg.d/90_pve.cfg <<EOF
# Prefer NoCloud (Proxmox cloud-init drive)
datasource_list: [ NoCloud, ConfigDrive ]
EOF

# Enable required services
systemctl enable sshd.service
systemctl enable qemu-guest-agent.service
systemctl enable cloud-init-local.service cloud-init.service cloud-config.service cloud-final.service

# Bootloader (BIOS/MBR via GRUB)
pacman -Sy --noconfirm grub
# Install to the whole disk (not the partition)
if [[ -b /dev/vda ]]; then
  grub-install --target=i386-pc /dev/vda
elif [[ -b /dev/sda ]]; then
  grub-install --target=i386-pc /dev/sda
elif [[ -b /dev/nvme0n1 ]]; then
  grub-install --target=i386-pc /dev/nvme0n1
else
  echo "No disk for grub-install" >&2
  exit 1
fi
grub-mkconfig -o /boot/grub/grub.cfg

# Small quality-of-life: parallel downloads for pacman
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf

# Clean up
yes | pacman -Scc || true
rm -rf /var/cache/pacman/pkg/* || true
journalctl --rotate || true
journalctl --vacuum-time=1s || true

# Lock the root account (cloud-init will manage users)
passwd -l root || true
CHROOT

# --- Done ----------------------------------------------------------------------
sync
echo "==> Bootstrap done, powering off"
systemctl poweroff -i

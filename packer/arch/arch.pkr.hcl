packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.3"
    }
  }
}

source "proxmox-iso" "arch" {
  # --- Authentication & Proxmox connection ---
  proxmox_url  = var.proxmox_url
  username     = var.proxmox_username
  token        = var.proxmox_token
  node         = var.node

  communicator = "none"

  # --- VM identity & resources ---
  vm_name         = local.computed_template_name
  memory          = var.vm_memory_mb
  cores           = var.vm_cores
  scsi_controller = "virtio-scsi-pci"
  qemu_agent      = true
  os              = "l26"
  bios            = "seabios"

  # --- Disk configuration ---
  disks {
    type         = "scsi"
    disk_size    = "12G"
    storage_pool = var.storage_vm
    ssd          = true
    discard      = true
  }

  # --- RNG device ---
  rng0 {
    source    = "/dev/urandom"
    max_bytes = 1048576
  }

  # --- Network ---
  network_adapters {
    model  = "virtio"
    bridge = var.bridge
  }

  # --- Boot ISO (your custom Arch image) ---
  boot_iso {
    type     = "ide"
    iso_file = "local:iso/archlinux-2025.11.09-x86_64.iso"
    unmount  = true
  }

  # --- Delay shutdown so the auto-script can complete ---
  boot_wait   = "10s"
  boot_command = ["<wait3m>"]

  # --- Cloud-init for clones ---
  cloud_init              = true
  cloud_init_storage_pool = var.storage_vm

  # --- Template metadata ---
  template_name        = local.computed_template_name
  template_description = "Arch base (BIOS) with qemu-guest-agent, cloud-init; custom autorun ISO"
  tags                 = "arch;template"
}

build {
  name    = "arch"
  sources = ["source.proxmox-iso.arch"]

  post-processor "manifest" {
    output     = "artifacts/packer-manifest.json"
    strip_path = true
  }
}

packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.3"
    }
  }
}

locals {
  arch_iso_manifest = jsondecode(
    file("../../infra/os/arch/spec/iso-manifest-stable.json")
  )

  arch_iso_storage = local.arch_iso_manifest.proxmox_storage
  arch_iso_name    = local.arch_iso_manifest.iso_name
}

source "proxmox-iso" "arch" {
  # --- Authentication & Proxmox connection ---
  proxmox_url = var.proxmox_url
  username    = var.proxmox_username
  token       = var.proxmox_token
  node        = var.node

  # We still don't talk directly to the VM
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
    iso_file = "${local.arch_iso_storage}:iso/${local.arch_iso_name}"
    unmount  = true
  }

  # Let the ISO boot; no artificial 3-minute wait
  boot_wait = "10s"
  # No boot_command needed if your ISO self-starts the install.
  # If you ever need to send keys, you can add a real boot_command here.
  # boot_command = []
  
  # --- Cloud-init for clones ---
  cloud_init              = true
  cloud_init_storage_pool = var.storage_vm

  # --- Template metadata ---
  template_name        = local.computed_template_name
  template_description = "Arch base (BIOS) with qemu-guest-agent, cloud-init; custom autorun ISO"
  tags                 = "arch;orchestrator;template"
}

build {
  name    = "arch"
  sources = ["source.proxmox-iso.arch"]

  # This runs on the *runner*, not in the VM.
  # It waits until Proxmox reports that the VM has powered off by itself.
  provisioner "shell-local" {
    environment_vars = [
      "PROXMOX_URL=${var.proxmox_url}",
      "PROXMOX_USERNAME=${var.proxmox_username}",
      "PROXMOX_TOKEN=${var.proxmox_token}",
      "PROXMOX_NODE=${var.node}",
      "VM_NAME=${local.computed_template_name}",
    ]

    # Script path is relative to this .pkr.hcl file (packer/arch)
    script = "${path.root}/scripts/wait-for-vm-shutdown.sh"
  }

  post-processor "manifest" {
    output     = "artifacts/packer-manifest.json"
    strip_path = true
  }
}

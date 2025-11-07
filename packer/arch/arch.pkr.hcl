packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.3"
    }
  }
}

source "proxmox-iso" "arch" {
  # Auth / endpoint / node (wired via variables.pkr.hcl + Doppler env)
  proxmox_url  = var.proxmox_url
  username     = var.proxmox_username
  token        = var.proxmox_token
  node         = var.node

  communicator = "none"

  # Identity & resources
  vm_name         = local.computed_template_name
  memory          = var.vm_memory_mb
  cores           = var.vm_cores
  scsi_controller = "virtio-scsi-pci"
  qemu_agent      = true
  os              = "l26"

  # Disk (note: size string WITH units)
  disks {
    type         = "scsi"
    disk_size    = "12G"
    storage_pool = var.storage_vm
    ssd          = true
    discard      = true
  }

  # BIOS path (legacy BIOS for GRUB)
  bios = "seabios"

  # RNG
  rng0 {
    source    = "/dev/urandom"
    max_bytes = 1048576
  }

  # NIC (virtio on your bridge)
  network_adapters {
    model  = "virtio"
    bridge = var.bridge
  }

  # Serve our bootstrap/test script to the installer
  http_directory = "${path.root}/http"

  # Use a pre-uploaded Arch ISO (no URL upload)
  boot_iso {
    type     = "ide"
    iso_file = var.arch_iso_file
    unmount  = true
  }

  # --- Modern Arch ISO (GRUB) boot automation -------------------------------
  boot_wait = "5s"
  boot_key_interval = "100ms"
  boot_keygroup_interval = "1200ms"

  boot_command = [
    "<wait8>",
    "<esc><wait1>",

    # Type the Arch Syslinux label + our args at the 'boot:' prompt
    "arch ip=dhcp script=http://{{ .HTTPIP }}:{{ .HTTPPort }}/test.sh",
    "<enter>",

    # Give it time to boot the live env and run your script (which will poweroff)
    "<wait5m>"
  ]

  # Attach cloud-init disk to the template
  cloud_init              = true
  cloud_init_storage_pool = var.storage_vm

  template_name        = local.computed_template_name
  template_description = "Arch base (BIOS) with qemu-guest-agent, cloud-init, ISO via iso_file"
  tags                 = "arch;template"
}

build {
  sources = ["source.proxmox-iso.arch"]
}

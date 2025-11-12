terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
    }
  }
}

resource "proxmox_vm_qemu" "vm" {
  name        = var.name
  target_node = var.node
  clone       = var.clone
  full_clone  = true

  # --- Compute ---
  cores   = var.cores
  sockets = 1
  cpu     = "kvm64"
  memory  = var.memory_mb
  kvm     = true
  agent   = 1
  onboot  = true
  numa    = false
  balloon = 0 

  # --- Disk ---
  scsihw = var.scsihw
  disk {
    type    = "scsi"
    storage = var.storage
    size    = "${var.disk_gb}G"
    ssd     = 1
    discard = "on"
    cache   = "none"
  }

  # --- Network ---
  network {
    model  = "virtio"
    bridge = var.bridge
    tag    = 0           # IMPORTANT: force numeric VLAN tag to avoid provider panic
  }

  # --- Cloud-init (static IPs required) ---
  ipconfig0 = var.ipconfig0
  ciuser    = var.ci_user
  sshkeys   = join("\n", var.ssh_authorized_keys)

  # --- Metadata ---
  tags = join(",", var.tags)

  boot = "order=scsi0;net0"
}
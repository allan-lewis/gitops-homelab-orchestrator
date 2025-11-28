locals {
  # Parse "ip=10.0.0.21/24,gw=10.0.0.1" into a small map
  _kv_pairs     = [for kv in split(",", var.ipconfig0) : split("=", kv)]
  _kv_map       = { for p in local._kv_pairs : p[0] => p[1] if length(p) == 2 }
  ipv4_address  = try(local._kv_map["ip"], "")
  ipv4_gateway  = try(local._kv_map["gw"], "")
}

resource "proxmox_virtual_environment_vm" "vm" {
  # --- Identity / placement ---
  node_name = var.node
  name      = var.name
  tags      = var.tags

  # --- Clone from L1 template (bpg needs VMID) ---
  clone {
    vm_id = var.clone_vmid
    full  = true
  }

  # --- CPU / Memory / Agent ---
  cpu {
    cores   = var.cores
    type    = "kvm64"
    sockets = 1
  }

  memory {
    dedicated = var.memory_mb
  }

  agent {
    enabled = var.agent_enabled
  }

  on_boot = true
  # (no 'numa' attribute here; bpg exposes NUMA differently—omit for now)

  # --- Disk ---
  scsi_hardware = var.scsihw
  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = var.disk_gb
    ssd          = true
    discard      = "on"
    cache        = "none"
  }

  # --- Network ---
  network_device {
    bridge  = var.bridge
    model   = "virtio"
    vlan_id = 0
  }

  # --- Cloud-Init (static IPs) ---
  initialization {
    user_account {
      username = var.ci_user
      keys     = var.ssh_authorized_keys
    }

    ip_config {
      ipv4 {
        address = local.ipv4_address  # e.g. "10.0.0.21/24"
        gateway = local.ipv4_gateway  # e.g. "10.0.0.1"
      }
    }
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

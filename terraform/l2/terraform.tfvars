# TLS verification (you have a valid cert)
pm_tls_insecure = false

# Cloud-init defaults
ci_user = "lab"

# Proxmox defaults (override per-VM in vms if needed)
storage = "local-lvm"
scsihw  = "virtio-scsi-pci"
bridge  = "vmbr0"

# Arch VMs (STATIC IPs required via ipconfig0)
# ipconfig0 must be like: "ip=10.0.0.21/24,gw=10.0.0.1"
vms = {
  blaine = {
    node      = "polaris"
    cores     = 4
    memory_mb = 4096
    disk_gb   = 64
    tags      = ["arch", "l2", "vm"]
    ipconfig0 = "ip=192.168.86.99/24,gw=192.168.86.1"
  }
}

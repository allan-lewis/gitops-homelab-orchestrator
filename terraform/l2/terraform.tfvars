# TLS verification (you have a valid cert)
pm_tls_insecure = false

# Path to the L1 manifest JSON (relative to terraform/l2/)
# Make sure this file includes a VMID (flat or under .data.vmid)
l1_manifest_path = "../../artifacts/l1_images/qemu-102-config.json"

# Cloud-init defaults
ci_user = "lab"

# Proxmox defaults (override per-VM in vms if needed)
storage = "local-lvm"
scsihw  = "virtio-scsi-pci"
bridge  = "vmbr0"

# Arch VMs (STATIC IPs required via ipconfig0)
# ipconfig0 must be like: "ip=10.0.0.21/24,gw=10.0.0.1"
vms = {
  archie = {
    node      = "polaris"
    cores     = 2
    memory_mb = 2048
    disk_gb   = 20
    tags      = ["arch", "l2", "vm"]
    ipconfig0 = "ip=192.168.86.97/24,gw=192.168.86.1"
  }
}

# TLS verification (you have a valid cert)
pm_tls_insecure = false

# Cloud-init defaults
ci_user = "lab"

# Proxmox defaults (override per-VM in vms if needed)
storage = "local-lvm"
scsihw  = "virtio-scsi-pci"
bridge  = "vmbr0"

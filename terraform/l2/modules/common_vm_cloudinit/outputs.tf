# VMID from the created QEMU VM
output "vmid" {
  value = proxmox_vm_qemu.vm.vmid
}

# Extract static IP from ipconfig0 (e.g., "ip=10.0.0.21/24,gw=10.0.0.1")
# Returns empty string if it doesn't match.
output "ip" {
  value = try(regex("ip=([^/]+)/", var.ipconfig0), "")
}

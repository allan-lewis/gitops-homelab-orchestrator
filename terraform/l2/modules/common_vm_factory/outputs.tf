# Map of host → VMID (from common_vm_cloudinit)
output "vm_ids" {
  description = "Map of hostnames to Proxmox VM IDs"
  value = {
    for name, _ in local.vms :
    name => module.cloudinit[name].vm_id
  }
}

# Map of host → IPv4 address (from common_vm_cloudinit)
output "ip_addresses" {
  description = "Map of hostnames to assigned IPv4 addresses"
  value = {
    for name, _ in local.vms :
    name => module.cloudinit[name].ip_address
  }
}

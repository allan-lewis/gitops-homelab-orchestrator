# VMID (numeric ID assigned by Proxmox)
output "vm_id" {
  description = "Proxmox VM ID of the created virtual machine"
  value       = proxmox_virtual_environment_vm.vm.id
}

# IPv4 address (if available)
output "ip_address" {
  description = "Static IPv4 address assigned via cloud-init"
  value = try(
    proxmox_virtual_environment_vm.vm.initialization[0].ip_config[0].ipv4[0].address,
    ""
  )
}

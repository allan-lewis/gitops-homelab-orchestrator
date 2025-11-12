# Collect all VM IDs
output "arch_vm_vmids" {
  description = "VMIDs of created Arch VMs"
  value       = { for k, m in module.arch : k => m.vm_id }
}

# Collect assigned IPv4 addresses (from initialization)
output "arch_vm_ips" {
  description = "Static IPv4 addresses of created Arch VMs"
  value = {
    for k, m in module.arch :
    k => try(m.initialization[0].ip_config[0].ipv4[0].address, "")
  }
}

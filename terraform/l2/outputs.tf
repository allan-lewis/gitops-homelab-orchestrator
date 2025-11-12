# VMIDs from module outputs
output "arch_vm_vmids" {
  description = "VMIDs of created Arch VMs"
  value       = { for k, m in module.arch : k => m.vm_id }
}

# IPs from module outputs (not the raw resource tree)
output "arch_vm_ips" {
  description = "Static IPv4 addresses of created Arch VMs"
  value       = { for k, m in module.arch : k => m.ip_address }
}

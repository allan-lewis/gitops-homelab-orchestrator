# Per-VM IPs (derived from the static ipconfig0 you provide)
output "arch_vm_ips" {
  value = { for k, m in module.arch : k => m.ip }
}

# Per-VM VMIDs
output "arch_vm_vmids" {
  value = { for k, m in module.arch : k => m.vmid }
}

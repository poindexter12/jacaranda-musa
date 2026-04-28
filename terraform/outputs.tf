# ============================================================================
# Musa Module Outputs
# ============================================================================

# ============================================================================
# Instance Outputs
# ============================================================================

output "instances" {
  description = "Map of all Musa instances with details"
  value       = merge(module.lxc_app.instances, module.lxc_bak.instances)
}

output "mgmt_ips" {
  description = "Map of hostname to management IP (.5.x)"
  value       = merge(module.lxc_app.mgmt_ips, module.lxc_bak.mgmt_ips)
}

output "transfer_ips" {
  description = "Map of hostname to transfer IP (.11.x) for cluster traffic"
  value       = { for name, inst in var.instances : name => inst.transfer_ip }
}

output "ansible_inventory_path" {
  description = "Path to generated Ansible inventory file"
  value       = var.ansible_inventory_path != null ? local_file.ansible_inventory[0].filename : null
}

# ============================================================================
# DNS Entries Output (for centralized Pi-hole DNS)
# ============================================================================

output "dns_entries" {
  description = "DNS A record entries for Pi-hole (hostname.network => IP)"
  value       = merge(module.lxc_app.dns_entries, module.lxc_bak.dns_entries)
}

output "cname_entries" {
  description = "CNAME entries for Pi-hole (bare => .lan => .mgmt)"
  value = merge(
    # Instance CNAMEs from both LXC module calls (for SSH cert auth)
    module.lxc_app.cname_entries,
    module.lxc_bak.cname_entries,
    # Bare name convenience CNAMEs
    {
      for name, inst in var.instances :
      name => "${name}.lan"
    }
  )
}

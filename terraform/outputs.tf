# ============================================================================
# Musa Module Outputs
# ============================================================================

# ============================================================================
# Instance Outputs
# ============================================================================

output "instances" {
  description = "Map of all Musa instances with details"
  value       = module.lxc.instances
}

output "mgmt_ips" {
  description = "Map of hostname to management IP (.5.x)"
  value       = module.lxc.mgmt_ips
}

output "ansible_inventory_path" {
  description = "Path to generated Ansible inventory file"
  value       = module.lxc.ansible_inventory_path
}

# ============================================================================
# DNS Entries Output (for centralized Pi-hole DNS)
# ============================================================================

output "dns_entries" {
  description = "DNS A record entries for Pi-hole (hostname.network => IP)"
  value       = module.lxc.dns_entries
}

output "cname_entries" {
  description = "CNAME entries for Pi-hole (bare => .lan => .mgmt)"
  value = merge(
    # Instance CNAMEs from LXC module (for SSH cert auth)
    module.lxc.cname_entries,
    # Bare name convenience CNAMEs
    {
      for name, inst in var.instances :
      name => "${name}.lan"
    }
  )
}

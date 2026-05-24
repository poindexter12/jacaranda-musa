# ============================================================================
# Musa Module Outputs
# ============================================================================

# ============================================================================
# Instance Outputs
# ============================================================================

output "instances" {
  description = "Map of all Musa instances with details"
  value = {
    for name, ct in proxmox_virtual_environment_container.musa : name => {
      vmid        = ct.vm_id
      name        = name
      node        = ct.node_name
      mgmt_ip     = var.instances[name].mgmt_ip
      transfer_ip = var.instances[name].transfer_ip
    }
  }
}

output "mgmt_ips" {
  description = "Map of hostname to management IP (.5.x)"
  value = {
    for name, inst in var.instances : name => inst.mgmt_ip
  }
}

output "transfer_ips" {
  description = "Map of hostname to transfer IP (.11.x) for cluster traffic"
  value = {
    for name, inst in var.instances : name => inst.transfer_ip
  }
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
  value = merge(
    { for name, inst in var.instances : "${name}.mgmt" => inst.mgmt_ip },
    { for name, inst in var.instances : "${name}.transfer" => inst.transfer_ip }
  )
}

output "cname_entries" {
  description = "CNAME entries for Pi-hole (bare hostname => fully-qualified .mgmt.home.arpa)"
  value = {
    for name, inst in var.instances : name => "${name}.mgmt.home.arpa"
  }
}

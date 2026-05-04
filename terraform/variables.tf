# ============================================================================
# Musa LXC Module Variables
# ============================================================================

# ============================================================================
# Instance Configuration
# ============================================================================

variable "instances" {
  description = "Map of Musa instances to create"
  type = map(object({
    vmid        = number
    node        = string
    mgmt_ip     = string              # 192.168.5.x - SSH/management
    transfer_ip = string              # 192.168.11.x - cluster traffic (per D-05)
    node_role   = string              # "app" or "backup" (per D-15)
    cores       = optional(number)    # Override default cores (per D-13)
    memory      = optional(number)    # Override default memory
    disk_size   = optional(string)    # Override default disk size
  }))
}

variable "env" {
  description = "Environment name (test or prod)"
  type        = string
}

variable "ansible_inventory_path" {
  description = "Path to write Ansible inventory (null = don't generate)"
  type        = string
  default     = null
}

# ============================================================================
# Base Infrastructure (from terraform_remote_state)
# ============================================================================

variable "vlans" {
  description = "VLAN configuration map"
  type = map(object({
    id      = number
    bridge  = string
    network = string
    gateway = string
    domain  = string
    mtu     = number
  }))
}

variable "ssh_public_key" {
  description = "SSH public key for root access"
  type        = string
}

variable "dns_server" {
  description = "DNS server IP for bootstrap"
  type        = string
  default     = "1.1.1.1"
}

# ============================================================================
# LXC Resources
# ============================================================================

variable "ostemplate" {
  description = "LXC OS template (e.g., local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst)"
  type        = string
}

variable "storage" {
  description = "Storage pool for root filesystem"
  type        = string
  default     = "ceph-seymour"
}

variable "cores" {
  description = "Number of CPU cores per container (default for app nodes)"
  type        = number
  default     = 4
}

variable "memory" {
  description = "Memory in MB per container (default for app nodes)"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Root filesystem size (default for app nodes)"
  type        = string
  default     = "20G"
}

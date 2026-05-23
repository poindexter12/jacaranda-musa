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
    mgmt_ip     = string
    transfer_ip = string
    node_role   = string
    cores       = optional(number)
    memory      = optional(number)
    disk_size   = optional(string)
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
# Base Infrastructure
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

variable "ssh_user_ca_pubkey" {
  description = "SSH User CA public key for cert-based authentication (empty string skips CA provisioners)"
  type        = string
  default     = ""
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
  description = "Default CPU cores per container (overridden per-instance)"
  type        = number
  default     = 4
}

variable "memory" {
  description = "Default memory in MB per container (overridden per-instance)"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Default root filesystem size (overridden per-instance)"
  type        = string
  default     = "20G"
}

# ============================================================================
# SSH CA
# ============================================================================

variable "step_ca_host" {
  description = "step-ca hostname for SSH cert signing"
  type        = string
  default     = "step-ca.lan"
}

# ============================================================================
# HA Configuration
# ============================================================================

variable "ha_enabled" {
  description = "Enable Proxmox HA for containers (failover to any cluster node on host failure)"
  type        = bool
  default     = false
}

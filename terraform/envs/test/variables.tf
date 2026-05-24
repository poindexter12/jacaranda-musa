variable "ssh_public_key" {
  type        = string
  description = "SSH public key for LXC root access. Source: op://Homelab/musa-project-test/public key"
}

variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint URL. Set by test.just via TF_VAR_proxmox_endpoint."
}

variable "proxmox_api_token_secret" {
  type        = string
  sensitive   = true
  description = "Proxmox API token secret (UUID). Set by test.just via TF_VAR_proxmox_api_token_secret from op://Homelab/Jacaranda Proxmox Deploy/api token. Combined with infra.yaml proxmox.api_token_id as id=secret."
}

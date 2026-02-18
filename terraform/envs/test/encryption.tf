# OpenTofu State Encryption Configuration
# Copy this file to each terraform directory that needs state encryption
#
# Usage in Justfile:
#   encryption_passphrase := `op read 'op://Homelab/opentofu/password'`
#   tofu plan -var=encryption_passphrase=$encryption_passphrase
#
# Documentation: https://opentofu.org/docs/language/state/encryption/

terraform {
  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase = var.encryption_passphrase
    }

    method "aes_gcm" "default" {
      keys = key_provider.pbkdf2.passphrase
    }

    state {
      method   = method.aes_gcm.default
      enforced = true
    }
  }
}

variable "encryption_passphrase" {
  type        = string
  sensitive   = true
  description = "Passphrase for state encryption. Source: op://Homelab/opentofu/password"
}

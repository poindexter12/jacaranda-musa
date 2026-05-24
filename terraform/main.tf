# ============================================================================
# Musa LXC Module
# ============================================================================
# Creates Twenty CRM LXC container(s) on Proxmox via the bpg provider.
# Multi-instance via `instances` map; today we run a single instance and
# rely on Proxmox HA (see ha_enabled) for cross-node failover rather than
# application-level replication.

terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

# ============================================================================
# LXC Containers (bpg provider)
# ============================================================================

resource "proxmox_virtual_environment_container" "musa" {
  for_each = var.instances

  node_name     = each.value.node
  vm_id         = each.value.vmid
  unprivileged  = true
  start_on_boot = true
  started       = true

  description = "Musa Twenty CRM - ${each.value.node_role} node. Managed by Terraform."

  features {
    nesting = true
  }

  operating_system {
    template_file_id = var.ostemplate
    type             = "ubuntu"
  }

  initialization {
    hostname = each.key

    dns {
      servers = [var.dns_server]
      domain  = "lan"
    }

    # eth0: Management network (always present, has gateway)
    ip_config {
      ipv4 {
        address = "${each.value.mgmt_ip}/24"
        gateway = var.vlans["mgmt"].gateway
      }
    }

    # eth1: Transfer network (optional)
    dynamic "ip_config" {
      for_each = each.value.transfer_ip != null ? [1] : []
      content {
        ipv4 {
          address = "${each.value.transfer_ip}/24"
        }
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }
  }

  # eth0: Management
  network_interface {
    name   = "eth0"
    bridge = var.vlans["mgmt"].bridge
  }

  # eth1: Transfer (conditional)
  dynamic "network_interface" {
    for_each = each.value.transfer_ip != null ? [1] : []
    content {
      name   = "eth1"
      bridge = var.vlans["transfer"].bridge
    }
  }

  disk {
    datastore_id = var.storage
    size         = tonumber(trimsuffix(coalesce(each.value.disk_size, var.disk_size), "G"))
  }

  cpu {
    cores = coalesce(each.value.cores, var.cores)
  }

  memory {
    dedicated = coalesce(each.value.memory, var.memory)
  }

  tags = sort([var.env, "musa", each.value.node_role])

  lifecycle {
    ignore_changes = [
      operating_system,
      initialization[0].user_account,
    ]
  }
}

# ============================================================================
# SSH CA Host Certificate Signing
# ============================================================================
# Signs host cert after LXC creation using pct exec via Proxmox node.

resource "null_resource" "sign_host_cert" {
  for_each = var.ssh_user_ca_pubkey != "" ? var.instances : {}

  triggers = {
    container_id = proxmox_virtual_environment_container.musa[each.key].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      ${path.module}/../lib/infrastructure/terraform/modules/lxc/sign-host-cert.sh \
        "${each.key}" \
        "${each.value.node}" \
        "${each.value.vmid}" \
        "${var.step_ca_host}"
    EOT
  }

  depends_on = [proxmox_virtual_environment_container.musa]
}

# ============================================================================
# SSH CA Configuration
# ============================================================================

resource "null_resource" "configure_ssh_ca" {
  for_each = var.ssh_user_ca_pubkey != "" ? var.instances : {}

  triggers = {
    container_id = proxmox_virtual_environment_container.musa[each.key].id
    user_ca      = var.ssh_user_ca_pubkey
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      NODE="${each.value.node}.home.arpa"
      VMID="${each.value.vmid}"
      HOSTNAME="${each.key}"
      USER_CA='${var.ssh_user_ca_pubkey}'

      echo "=== Configuring SSH CA for $${HOSTNAME} (LXC $${VMID} on $${NODE}) ==="

      ssh root@$${NODE} "pct exec $${VMID} -- bash -c 'echo \"$${USER_CA}\" > /etc/ssh/user_ca.pub'"
      ssh root@$${NODE} "pct exec $${VMID} -- chmod 644 /etc/ssh/user_ca.pub"
      ssh root@$${NODE} "pct exec $${VMID} -- mkdir -p /etc/ssh/sshd_config.d"

      ssh root@$${NODE} "pct exec $${VMID} -- bash -c 'cat > /etc/ssh/sshd_config.d/99-ssh-ca.conf << EOF
# SSH Certificate Authentication - managed by Terraform
TrustedUserCAKeys /etc/ssh/user_ca.pub
HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub
EOF'"

      ssh root@$${NODE} "pct exec $${VMID} -- cat /etc/ssh/sshd_config.d/99-ssh-ca.conf"
      ssh root@$${NODE} "pct exec $${VMID} -- systemctl reload ssh 2>/dev/null || pct exec $${VMID} -- systemctl reload sshd 2>/dev/null"

      echo "=== SSH CA configured for $${HOSTNAME} ==="
    EOT
  }

  depends_on = [null_resource.sign_host_cert]
}

# ============================================================================
# SSH Verification
# ============================================================================

resource "null_resource" "verify_ssh" {
  for_each = var.ssh_user_ca_pubkey != "" ? var.instances : {}

  triggers = {
    container_id = proxmox_virtual_environment_container.musa[each.key].id
    user_ca      = var.ssh_user_ca_pubkey
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      NODE="${each.value.node}.home.arpa"
      VMID="${each.value.vmid}"
      HOSTNAME="${each.key}"

      echo "=== Verifying SSH CA config for $${HOSTNAME} (LXC $${VMID} on $${NODE}) ==="

      ssh -o BatchMode=yes "root@$${NODE}" "pct exec $${VMID} -- test -f /etc/ssh/user_ca.pub"
      ssh -o BatchMode=yes "root@$${NODE}" "pct exec $${VMID} -- test -f /etc/ssh/ssh_host_ed25519_key-cert.pub"
      ssh -o BatchMode=yes "root@$${NODE}" "pct exec $${VMID} -- sshd -T" 2>/dev/null | grep -q "trustedusercakeys /etc/ssh/user_ca.pub"

      echo "=== SSH CA verification passed for $${HOSTNAME} ==="
    EOT
  }

  depends_on = [null_resource.configure_ssh_ca]
}

# ============================================================================
# Proxmox HA Management
# ============================================================================
# Registers each LXC with the Proxmox HA stack via the bpg provider's native
# API resource — no SSH required. The provider talks to the Proxmox API using
# var.proxmox_endpoint + var.proxmox_api_token_secret already configured.

resource "proxmox_haresource" "musa" {
  for_each = var.ha_enabled ? var.instances : {}

  resource_id = "ct:${each.value.vmid}"
  type        = "ct"
  state       = "started"
  comment     = "Managed by Terraform (musa)"

  depends_on = [proxmox_virtual_environment_container.musa]

  # If the container is replaced (e.g. VMID or node changes), force-replace
  # the HA resource too. This makes terraform destroy the HA registration
  # BEFORE destroying the container — Proxmox refuses to delete an
  # HA-managed container without the purge flag.
  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_container.musa[each.key]]
  }
}

# ============================================================================
# Ansible Inventory
# ============================================================================

locals {
  inventory_hosts = {
    for name, inst in var.instances : name => {
      ansible_host = "${name}.mgmt.home.arpa"
      mgmt_ip      = inst.mgmt_ip
      transfer_ip  = inst.transfer_ip
      node_role    = inst.node_role
      vmid         = inst.vmid
    }
  }

  ansible_inventory = {
    all = {
      children = {
        musa = {
          hosts = local.inventory_hosts
        }
      }
      vars = {
        ansible_user = "root"
      }
    }
  }
}

resource "local_file" "ansible_inventory" {
  count = var.ansible_inventory_path != null ? 1 : 0

  filename        = var.ansible_inventory_path
  content         = "---\n# Auto-generated by Terraform - do not edit manually\n# Regenerate with: tofu apply\n\n${yamlencode(local.ansible_inventory)}"
  file_permission = "0644"
}

# ============================================================================
# Musa LXC Module (3-Node HA Cluster)
# ============================================================================
# Creates LXC containers for the Musa Project (Twenty CRM HA) using the bpg
# Proxmox provider directly (decoupled from shared LXC module).
#
# Per-instance resource overrides (cores, memory, disk_size) allow different
# tiers (app vs backup) without separate module calls.
#
# VMID Allocation: 1190-1192 (4-digit TSSS: 1xxx LXC + IP octet)
# IP Allocation:
#   test.app1.app.musa:     192.168.5.190 / 192.168.11.190 (VMID 1190, joseph)
#   test.app2.app.musa:     192.168.5.191 / 192.168.11.191 (VMID 1191, everette)
#   test.bak.backup.musa:   192.168.5.192 / 192.168.11.192 (VMID 1192, maxwell)

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

      NODE="${each.value.node}"
      VMID="${each.value.vmid}"
      HOSTNAME="${each.key}"
      USER_CA='${var.ssh_user_ca_pubkey}'

      echo "=== Configuring SSH CA for $${HOSTNAME} (LXC $${VMID} on $${NODE}) ==="

      ssh root@$${NODE}.lan "pct exec $${VMID} -- bash -c 'echo \"$${USER_CA}\" > /etc/ssh/user_ca.pub'"
      ssh root@$${NODE}.lan "pct exec $${VMID} -- chmod 644 /etc/ssh/user_ca.pub"
      ssh root@$${NODE}.lan "pct exec $${VMID} -- mkdir -p /etc/ssh/sshd_config.d"

      ssh root@$${NODE}.lan "pct exec $${VMID} -- bash -c 'cat > /etc/ssh/sshd_config.d/99-ssh-ca.conf << EOF
# SSH Certificate Authentication - managed by Terraform
TrustedUserCAKeys /etc/ssh/user_ca.pub
HostCertificate /etc/ssh/ssh_host_ed25519_key-cert.pub
EOF'"

      ssh root@$${NODE}.lan "pct exec $${VMID} -- cat /etc/ssh/sshd_config.d/99-ssh-ca.conf"
      ssh root@$${NODE}.lan "pct exec $${VMID} -- systemctl reload ssh 2>/dev/null || pct exec $${VMID} -- systemctl reload sshd 2>/dev/null"

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

      NODE="${each.value.node}"
      VMID="${each.value.vmid}"
      HOSTNAME="${each.key}"

      echo "=== Verifying SSH CA config for $${HOSTNAME} (LXC $${VMID} on $${NODE}) ==="

      ssh -o BatchMode=yes "root@$${NODE}.lan" "pct exec $${VMID} -- test -f /etc/ssh/user_ca.pub"
      ssh -o BatchMode=yes "root@$${NODE}.lan" "pct exec $${VMID} -- test -f /etc/ssh/ssh_host_ed25519_key-cert.pub"
      ssh -o BatchMode=yes "root@$${NODE}.lan" "pct exec $${VMID} -- sshd -T" 2>/dev/null | grep -q "trustedusercakeys /etc/ssh/user_ca.pub"

      echo "=== SSH CA verification passed for $${HOSTNAME} ==="
    EOT
  }

  depends_on = [null_resource.configure_ssh_ca]
}

# ============================================================================
# Proxmox HA Management
# ============================================================================

resource "null_resource" "ha_add" {
  for_each = var.ha_enabled ? var.instances : {}

  triggers = {
    container_id = proxmox_virtual_environment_container.musa[each.key].id
    node         = each.value.node
    vmid         = each.value.vmid
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "=== Adding ct:${each.value.vmid} to Proxmox HA ==="
      ssh root@${each.value.node}.lan "ha-manager add ct:${each.value.vmid} --state started 2>/dev/null || true"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      ssh root@${self.triggers.node}.lan "ha-manager remove ct:${self.triggers.vmid} 2>/dev/null || true"
    EOT
  }

  depends_on = [proxmox_virtual_environment_container.musa, null_resource.verify_ssh]
}

locals {
  ha_anti_affinity_rules = {
    for idx, group in var.ha_anti_affinity_groups : idx => {
      name = "musa-${idx}-anti-affinity"
      resources = join(",", [
        for instance_name in group : "ct:${var.instances[instance_name].vmid}"
      ])
    }
  }
}

resource "null_resource" "ha_anti_affinity" {
  for_each = var.ha_enabled && length(var.ha_anti_affinity_groups) > 0 ? local.ha_anti_affinity_rules : {}

  triggers = {
    rule_name = each.value.name
    resources = each.value.resources
    node      = var.instances[var.ha_anti_affinity_groups[each.key][0]].node
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "=== Creating anti-affinity rule: ${each.value.name} ==="

      if ssh root@${self.triggers.node}.lan "ha-manager rules status resource-affinity ${each.value.name}" >/dev/null 2>&1; then
        ssh root@${self.triggers.node}.lan "ha-manager rules set resource-affinity ${each.value.name} --resources ${each.value.resources}"
      else
        ssh root@${self.triggers.node}.lan "ha-manager rules add resource-affinity ${each.value.name} --affinity negative --resources ${each.value.resources}"
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      ssh root@${self.triggers.node}.lan "ha-manager rules remove resource-affinity ${self.triggers.rule_name} 2>/dev/null || true"
    EOT
  }

  depends_on = [null_resource.ha_add]
}

# ============================================================================
# Custom Multi-Group Ansible Inventory
# ============================================================================

locals {
  inventory_hosts = {
    for name, inst in var.instances : name => {
      ansible_host = "${name}.lan"
      mgmt_ip      = inst.mgmt_ip
      transfer_ip  = inst.transfer_ip
      node_role    = inst.node_role
      vmid         = inst.vmid
    }
  }

  app_host_names    = [for name, inst in var.instances : name if inst.node_role == "app"]
  backup_host_names = [for name, inst in var.instances : name if inst.node_role == "backup"]

  app_hosts = {
    for name in local.app_host_names : name => local.inventory_hosts[name]
  }
  backup_hosts = {
    for name in local.backup_host_names : name => local.inventory_hosts[name]
  }

  ansible_inventory = {
    all = {
      children = {
        musa = {
          hosts = local.inventory_hosts
        }
        etcd_nodes = {
          hosts = local.inventory_hosts
        }
        patroni_nodes = {
          hosts = local.inventory_hosts
        }
        app_nodes = {
          hosts = local.app_hosts
        }
        backup_nodes = {
          hosts = local.backup_hosts
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

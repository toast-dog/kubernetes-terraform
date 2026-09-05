# Config patches live in patches/ as plain YAML — same shape Talos's own docs and
# `talosctl --config-patch @file.yaml` use, so they're directly comparable/copy-pasteable.
# Per-node (disk/interface aren't guaranteed uniform), so both are maps keyed by hostname.
locals {
  vip_patches = {
    for name, n in local.controlplane_nodes : name => templatefile("${path.module}/patches/vip.yaml", {
      talos_vip       = var.talos_vip
      talos_interface = n.interface
    })
  }

  install_patches = {
    for name, n in var.talos_nodes : name => templatefile("${path.module}/patches/install-disk.yaml", {
      talos_image = var.talos_image
      talos_disk  = n.disk
    })
  }
}

data "talos_machine_configuration" "controlplane" {
  for_each = local.controlplane_nodes

  cluster_name       = var.talos_cluster_name
  cluster_endpoint   = "https://${var.talos_vip}:6443"
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = [local.vip_patches[each.key], local.install_patches[each.key]]
}

data "talos_machine_configuration" "worker" {
  for_each = local.worker_nodes

  cluster_name       = var.talos_cluster_name
  cluster_endpoint   = "https://${var.talos_vip}:6443"
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = [local.install_patches[each.key]]
}

# Generated locally from machine_secrets — no live call, no cycle risk. Used only for
# nodes in talos_joined_ips.
ephemeral "talos_cluster_kubeconfig" "for_drain" {
  cluster_name    = var.talos_cluster_name
  machine_secrets = talos_machine_secrets.cluster.machine_secrets
  endpoint        = "https://${local.controlplane_ip}:6443"
}

# image is always set (so a fresh install uses the right version, not the provider's own
# unrelated default) — only drain_on_upgrade/kubeconfig_wo are gated per-node on
# talos_joined_ips, since a node's first install has no live API to drain against.

# Applied first — workers' cert-signing needs a live control plane to dial (see cluster.tf).
resource "talos_machine" "controlplane" {
  for_each = local.controlplane_nodes

  node                             = each.value.ip
  client_configuration             = talos_machine_secrets.cluster.client_configuration
  machine_configuration            = data.talos_machine_configuration.controlplane[each.key].machine_configuration
  image                            = var.talos_image
  ignore_kubernetes_upgrade_drift  = true # talos_cluster.kubernetes_version stays the single source of truth for k8s upgrades

  drain_on_upgrade = contains(var.talos_joined_ips, each.value.ip)
  kubeconfig_wo    = contains(var.talos_joined_ips, each.value.ip) ? ephemeral.talos_cluster_kubeconfig.for_drain.kubeconfig_raw : null

  # Wipes and leaves etcd cleanly when a node is removed from the IP list.
  on_destroy = {
    reset    = true
    graceful = true
    reboot   = true
  }
}

# Waits for etcd bootstrap (cluster.tf) — before that, the VIP isn't up and worker
# cert-signing has nothing to dial.
resource "talos_machine" "workers" {
  for_each = local.worker_nodes

  node                             = each.value.ip
  client_configuration             = talos_machine_secrets.cluster.client_configuration
  machine_configuration            = data.talos_machine_configuration.worker[each.key].machine_configuration
  image                            = var.talos_image
  ignore_kubernetes_upgrade_drift  = true

  drain_on_upgrade = contains(var.talos_joined_ips, each.value.ip)
  kubeconfig_wo    = contains(var.talos_joined_ips, each.value.ip) ? ephemeral.talos_cluster_kubeconfig.for_drain.kubeconfig_raw : null

  depends_on = [talos_cluster.bootstrap]

  # Wipes and leaves etcd cleanly when a node is removed from the IP list.
  on_destroy = {
    reset    = true
    graceful = true
    reboot   = true
  }
}

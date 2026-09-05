locals {
  controlplane_nodes = { for name, n in var.talos_nodes : name => n if n.role == "controlplane" }
  worker_nodes       = { for name, n in var.talos_nodes : name => n if n.role == "worker" }

  controlplane_ips = [for n in local.controlplane_nodes : n.ip]
  worker_ips       = [for n in local.worker_nodes : n.ip]

  controlplane_ip = var.talos_nodes[var.talos_bootstrap_node].ip
}

# Bootstraps etcd (once) and manages the running Kubernetes version going forward — a
# version bump here drives a health-gated upgrade instead of a manual step.
resource "talos_cluster" "bootstrap" {
  node                 = local.controlplane_ip
  control_plane_nodes  = local.controlplane_ips
  client_configuration = talos_machine_secrets.cluster.client_configuration
  kubernetes_version   = var.kubernetes_version

  depends_on = [talos_machine.controlplane]
}

# node/endpoint deliberately point at a real node IP, not the VIP — VIP election depends
# on etcd already being up, so it isn't a safe target for these calls.
resource "talos_cluster_kubeconfig" "kubeconfig" {
  node                 = local.controlplane_ip
  client_configuration = talos_machine_secrets.cluster.client_configuration

  depends_on = [talos_cluster.bootstrap]
}

# For human/kubectl convenience only — other Terraform code should read the
# kubernetes_client_configuration output instead, not this file (see outputs.tf).
# Only created when kubeconfig_path is actually set — under CI, where it's never set,
# writing this file would just show as a spurious diff on every run (fresh filesystem
# each time, so Terraform always thinks the file needs recreating).
resource "local_file" "kubeconfig" {
  count = var.kubeconfig_path != null ? 1 : 0

  content         = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  filename        = pathexpand(var.kubeconfig_path)
  file_permission = "0600"
}

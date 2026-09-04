# Rendered locally from machine_secrets — no live call needed. For talosctl convenience only,
# same reasoning as local_file.kubeconfig in cluster.tf.
data "talos_client_configuration" "talosctl" {
  cluster_name          = var.talos_cluster_name
  client_configuration  = talos_machine_secrets.cluster.client_configuration
  nodes                 = concat(local.controlplane_ips, local.worker_ips)
  endpoints             = local.controlplane_ips
}

resource "local_file" "talosconfig" {
  count = var.talosconfig_path != null ? 1 : 0

  content         = data.talos_client_configuration.talosctl.talos_config
  filename        = pathexpand(var.talosconfig_path)
  file_permission = "0600"
}

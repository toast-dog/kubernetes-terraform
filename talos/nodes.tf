locals {
  controlplane_ips = var.talos_control_plane_ips
  controlplane_ip  = var.talos_control_plane_ips[0]
  worker_ips       = var.talos_worker_ips
}

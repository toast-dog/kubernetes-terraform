variable "talos_cluster_name" {
  description = "Name for the Talos cluster."
  type        = string
}

variable "talos_vip" {
  description = "Floating IP for the control-plane endpoint, shared across control-plane nodes via Talos's built-in VRRP-style election. Must be outside the DHCP pool and distinct from every node's own IP."
  type        = string
}

variable "talos_version" {
  description = "Talos version contract used to generate machine configs — should track the actual Talos image version used in proxmox-terraform."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to run — actively managed by talos_cluster, drives upgrade orchestration."
  type        = string
}

variable "talos_image" {
  description = "Installer image reference (factory.talos.dev/installer/<schematic-id>:<version>) — should track the same schematic ID and version as proxmox-terraform's Talos ISO download. Bump this to upgrade the running Talos OS."
  type        = string
}

variable "talos_control_plane_ips" {
  description = "IPs of the control-plane nodes — manually maintained so a node can be gracefully removed from the cluster before its VM is destroyed, and vice versa for adding one."
  type        = list(string)
}

variable "talos_worker_ips" {
  description = "IPs of the worker nodes — manually maintained, same reasoning as talos_control_plane_ips."
  type        = list(string)
}

variable "talosconfig_path" {
  description = "Path to write a local talosconfig to, for talosctl convenience (e.g. ~/.talos/config). Left unset by default — opt in locally via TF_VAR_talosconfig_path."
  type        = string
  default     = null
}

variable "talos_joined_ips" {
  description = "IPs of nodes already running in the cluster — add once joined to enable graceful drain on future upgrades."
  type        = list(string)
  default     = []
}

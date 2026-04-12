# Subset of root.hcl inputs used by this module — declared here so IDEs don't flag them as undeclared.
# root.hcl overwrites this file at runtime; add new shared vars there, not here.

variable "domain" {
  description = "Base domain for all services. Hostnames are derived as <service>.<domain> in locals.tf."
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "control_plane_ips" {
  description = "List of control plane node IPs — used in NetworkPolicy egress rules to allow API server access."
  type        = list(string)
}

variable "cluster_cidr" {
  description = "Pod CIDR for the cluster — used in webhook ingress rules."
  type        = string
}

# ---------------------------------------------------------------------------
# Shared — injected by root terragrunt.hcl
# ---------------------------------------------------------------------------

variable "domain" {
  description = "Base domain for all services (e.g. lab.toastdog.net). Hostnames are derived as <service>.<domain> in locals.tf."
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "control_plane_ips" {
  description = "List of control plane node IPs — used in NetworkPolicy egress rules to allow API server access"
  type        = list(string)
}

variable "cluster_cidr" {
  description = "Pod CIDR for the cluster — used in webhook ingress rules"
  type        = string
}

# ---------------------------------------------------------------------------
# ArgoCD
# ---------------------------------------------------------------------------

variable "argocd_version" {
  type = string
}

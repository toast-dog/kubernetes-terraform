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

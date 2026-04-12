# Subset of root.hcl inputs used by this module — declared here so IDEs don't flag them as undeclared.
# root.hcl overwrites this file at runtime; add new shared vars there, not here.

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

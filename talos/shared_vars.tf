# IDE-only snapshot of the shared_vars.tf that terragrunt generates for real at init/plan
# time — trimmed to what this module actually uses, since it gets overwritten on the next
# real run regardless. Update root.hcl if the real generated content changes.

variable "kubeconfig_path" {
  description = "Path to write a local kubeconfig to, for kubectl/talosctl convenience (e.g. ~/.kube/config). Left unset by default so nothing writes a file under CI, where it wouldn't persist to be useful anyway — opt in locally via TF_VAR_kubeconfig_path."
  type        = string
  default     = null
}

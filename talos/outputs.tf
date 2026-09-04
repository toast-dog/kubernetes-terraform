# Consumed by core's kubernetes/helm providers via a Terragrunt dependency block — not
# the raw kubeconfig file, which doesn't exist for a separate Terragrunt run to read
# under Atlantis/CI (no shared filesystem between runs).
output "kubernetes_client_configuration" {
  value     = talos_cluster_kubeconfig.kubeconfig.kubernetes_client_configuration
  sensitive = true
}

# Provider configurations only — required_providers versions are in the generated versions.tf
# (sourced from root terragrunt.hcl). Do not add required_providers blocks here.

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

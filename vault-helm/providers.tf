# helm + kubernetes only — no vault provider in this module.
# The vault provider lives in vault/, applied after Vault is initialized and unsealed.

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

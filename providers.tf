terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.1"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "vault" {
  address = "https://${var.vault_hostname}"
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

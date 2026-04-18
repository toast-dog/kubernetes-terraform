# vault-auth SA — ESO generates a TokenRequest for this SA; Vault's ACL template
# scopes access to secret/data/argocd/* based on the namespace in the JWT.
resource "kubernetes_service_account_v1" "vault_auth" {
  metadata {
    name      = "vault-auth"
    namespace = "argocd"
  }
}

resource "kubernetes_manifest" "argocd_admin_secret" {
  depends_on = [vault_kv_secret_v2.argocd]

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "argocd-admin-password"
      namespace = "argocd"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "argocd-secret"
        creationPolicy = "Merge"
      }
      data = [{
        secretKey = "admin.password"
        remoteRef = {
          key      = "argocd/config"
          property = "admin-password-hash"
        }
      }]
    }
  }
}

# Pre-requisite: create a Forgejo personal access token with repo read access and store it in Vault.
#   If absent, this ExternalSecret will be in SecretSyncedError and ArgoCD won't clone the repo —
#   Terraform itself won't error. ESO retries on refreshInterval once the secret exists.
#
#   CLI: vault kv put secret/argocd/forgejo username=<forgejo-username> token=<forgejo-pat>
#   UI:  Vault UI → Secrets → secret/ → Create secret → path "argocd/forgejo", add keys "username" and "token"
resource "kubernetes_manifest" "argocd_repo_forgejo" {
  depends_on = [kubernetes_service_account_v1.vault_auth]

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "argocd-repo-kubernetes-apps"
      namespace = "argocd"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "argocd-repo-kubernetes-apps"
        creationPolicy = "Owner"
        template = {
          metadata = {
            labels = {
              "argocd.argoproj.io/secret-type" = "repository"
            }
          }
          data = {
            type     = "git"
            url      = var.homelab_apps_repo_url
            username = "{{ .username }}"
            password = "{{ .token }}"
          }
        }
      }
      data = [
        {
          secretKey = "username"
          remoteRef = {
            key      = "argocd/forgejo"
            property = "username"
          }
        },
        {
          secretKey = "token"
          remoteRef = {
            key      = "argocd/forgejo"
            property = "token"
          }
        }
      ]
    }
  }
}

# Authentik OIDC client secret — written to Vault by tf-authentik/apps/argocd.
# ArgoCD reads this via the argocd-oidc Secret, referenced in the Helm values oidc.config.
resource "kubernetes_manifest" "argocd_oidc_secret" {
  depends_on     = [kubernetes_service_account_v1.vault_auth]
  computed_fields = ["spec.target.template.mergePolicy", "spec.target.template.engineVersion"]

  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "argocd-oidc"
      namespace = "argocd"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "argocd-oidc"
        creationPolicy = "Owner"
        template = {
          metadata = {
            labels = {
              "app.kubernetes.io/part-of" = "argocd"
            }
          }
        }
      }
      data = [{
        secretKey = "clientSecret"
        remoteRef = {
          key      = "argocd/oidc"
          property = "clientSecret"
        }
      }]
    }
  }
}

# Root app-of-apps — the only ArgoCD Application managed by Terraform.
# Everything in kubernetes-apps/apps/ is an Application manifest; ArgoCD
# picks them up automatically. Add a new app by creating a file in that directory.
resource "kubernetes_manifest" "argocd_root_app" {
  depends_on = [kubernetes_manifest.argocd_repo_forgejo]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.homelab_apps_repo_url
        targetRevision = "HEAD"
        path           = "apps"
      }
      destination = {
        server    = "https://kubernetes.default.svc" # built-in in-cluster API server address — means "this cluster"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}

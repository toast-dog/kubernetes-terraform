# KV v2 secrets engine — all secrets stored under secret/
resource "vault_mount" "kv" {
  path = "secret"
  type = "kv-v2"
}

# Kubernetes auth method — allows pods to authenticate using their service account tokens
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

# Kubernetes API host for token validation — CA cert is auto-discovered from the pod's mounted service account
resource "vault_kubernetes_auth_backend_config" "default" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = "https://kubernetes.default.svc.cluster.local:443"
}

# Per-namespace Vault policies — each grants read access only to that namespace's secret path.
# Driven by var.vault_secret_stores; add a namespace there to provision it automatically.
resource "vault_policy" "secret_store" {
  for_each = toset(var.vault_secret_stores)
  name     = "secret-store-${each.key}"
  policy   = <<-EOT
    path "secret/data/${each.key}/*" {
      capabilities = ["read"]
    }
    path "secret/metadata/${each.key}/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

# Per-namespace Vault auth roles — each binds to the vault-auth service account
# in the app namespace. ESO uses the TokenRequest API to generate short-lived
# tokens for that SA, so the central ESO service account never touches Vault directly.
resource "vault_kubernetes_auth_backend_role" "secret_store" {
  for_each                         = toset(var.vault_secret_stores)
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "secret-store-${each.key}"
  bound_service_account_names      = ["vault-auth"]
  bound_service_account_namespaces = [each.key]
  token_policies                   = [vault_policy.secret_store[each.key].name]
  token_ttl                        = 3600
}

resource "helm_release" "vault" {
  depends_on = [helm_release.longhorn]

  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = var.vault_version
  namespace        = "vault"
  create_namespace = true
  wait             = false # HA pods start sealed (readiness probe fails) — wait=true would hang

  values = [file("${path.module}/config/vault-values.yaml")]
}

# Vault UI IngressRoute — no Authentik, Vault manages its own authentication
resource "kubernetes_manifest" "vault_ingressroute" {
  depends_on = [helm_release.vault, helm_release.traefik]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "vault"
      namespace = "vault"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind     = "Rule"
        match    = "Host(`${var.vault_hostname}`)"
        priority = 10
        services = [{
          name = "vault"
          port = 8200
        }]
      }]
    }
  }
}

# CronJob that checks seal status every minute and unseals all pods if needed.
# Keys are read from the vault-unseal-keys Secret (created manually after init).
# Security note: unseal keys live in etcd — acceptable for homelab, not for production.
resource "kubernetes_manifest" "vault_unseal_cronjob" {
  depends_on = [helm_release.vault]

  manifest = {
    apiVersion = "batch/v1"
    kind       = "CronJob"
    metadata = {
      name      = "vault-unseal"
      namespace = "vault"
    }
    spec = {
      schedule                   = "* * * * *"
      concurrencyPolicy          = "Forbid"
      successfulJobsHistoryLimit = 1
      failedJobsHistoryLimit     = 1
      jobTemplate = {
        spec = {
          template = {
            spec = {
              restartPolicy = "OnFailure"
              securityContext = {
                runAsNonRoot = true               # reject pod at admission if image runs as uid 0
                seccompProfile = {
                  type = "RuntimeDefault"         # apply runtime's default syscall allowlist (blocks ptrace, mount, etc.)
                }
              }
              containers = [{
                name  = "vault-unseal"
                image = "hashicorp/vault:${var.vault_image_tag}"
                securityContext = {
                  allowPrivilegeEscalation = false # prevent gaining privileges beyond the parent process
                  readOnlyRootFilesystem   = true  # safe here — vault CLI only makes HTTP calls, no disk writes needed
                  runAsNonRoot             = true  # enforced by runAsUser below
                  runAsUser                = 100   # vault user (uid 100) — image default is root, must be explicit
                  capabilities = {
                    drop = ["ALL"]                 # vault operator unseal needs no Linux capabilities
                  }
                }
                command = ["/bin/sh", "-c", <<-EOT
                  for pod in vault-0.vault-internal vault-1.vault-internal vault-2.vault-internal; do
                    export VAULT_ADDR="http://$${pod}:8200"
                    vault status -format=json 2>/dev/null | grep -q '"sealed": true' || continue
                    vault operator unseal $UNSEAL_KEY_1
                    vault operator unseal $UNSEAL_KEY_2
                    vault operator unseal $UNSEAL_KEY_3
                  done
                EOT
                ]
                env = [
                  { name = "UNSEAL_KEY_1", valueFrom = { secretKeyRef = { name = "vault-unseal-keys", key = "key1" } } },
                  { name = "UNSEAL_KEY_2", valueFrom = { secretKeyRef = { name = "vault-unseal-keys", key = "key2" } } },
                  { name = "UNSEAL_KEY_3", valueFrom = { secretKeyRef = { name = "vault-unseal-keys", key = "key3" } } },
                ]
              }]
            }
          }
        }
      }
    }
  }
}

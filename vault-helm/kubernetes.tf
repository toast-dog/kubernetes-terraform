# Plain Kubernetes resources for Vault — no vault provider needed.

# Vault UI IngressRoute — no Authentik, Vault manages its own authentication
resource "kubernetes_manifest" "vault_ingressroute" {
  depends_on = [helm_release.vault]

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
        match    = "Host(`${local.vault_hostname}`)"
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
                  readOnlyRootFilesystem   = true  # vault CLI only makes HTTP calls, no disk writes needed
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

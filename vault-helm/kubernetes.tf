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
        services = [merge(
          { name = "vault", port = 8200 },
          # serversTransport tells Traefik to connect to the backend over HTTPS and
          # trust the vault-internal-ca cert. Created by vault/vault_pki.tf (Apply 2).
          var.bootstrap_mode ? {} : { serversTransport = "vault-https" }
        )]
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
              # vault-tls is mounted when TLS is enabled so the unseal script can
              # verify Vault's cert via VAULT_CACERT. Omitted during bootstrap.
              volumes = var.bootstrap_mode ? null : [{
                name   = "vault-tls"
                secret = { secretName = "vault-tls" }
              }]
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
                    export VAULT_ADDR="${var.bootstrap_mode ? "http" : "https"}://$${pod}:8200"
                    vault status -format=json 2>/dev/null | grep -q '"sealed": true' || continue
                    vault operator unseal $UNSEAL_KEY_1
                    vault operator unseal $UNSEAL_KEY_2
                    vault operator unseal $UNSEAL_KEY_3
                  done
                EOT
                ]
                env = concat(
                  [
                    { name = "UNSEAL_KEY_1", valueFrom = { secretKeyRef = { name = "vault-unseal-keys", key = "key1" } } },
                    { name = "UNSEAL_KEY_2", valueFrom = { secretKeyRef = { name = "vault-unseal-keys", key = "key2" } } },
                    { name = "UNSEAL_KEY_3", valueFrom = { secretKeyRef = { name = "vault-unseal-keys", key = "key3" } } },
                  ],
                  var.bootstrap_mode ? [] : [
                    # ca.crt from vault-tls contains the issuer chain — used to verify Vault's TLS cert
                    { name = "VAULT_CACERT", value = "/vault/userconfig/vault-tls/ca.crt" }
                  ]
                )
                volumeMounts = var.bootstrap_mode ? null : [{
                  mountPath = "/vault/userconfig/vault-tls"
                  name      = "vault-tls"
                  readOnly  = true
                }]
              }]
            }
          }
        }
      }
    }
  }
}

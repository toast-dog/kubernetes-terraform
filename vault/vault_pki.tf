# ---------------------------------------------------------------------------
# Vault PKI — Phases 1-3 + 5.1 (CA secrets) + 5.3 (ServersTransport)
#
# Apply order:
#   Apply 1 (bootstrap_mode = true OR established cluster):
#     - All vault_* resources below succeed because Vault is already running.
#     - ClusterIssuer points to Vault via HTTP (bootstrap_mode = true).
#     - vault-tls Certificate is created; cert-manager issues it via HTTP.
#     - Wait ~30s for vault-tls Secret to appear in the vault namespace.
#
#   Apply 2 (bootstrap_mode = false, default):
#     - ClusterIssuer switches to HTTPS + caBundle.
#     - CA secrets created in each namespace for ESO caProvider.
#     - ServersTransport created in vault namespace.
#     - vault-helm/ apply updates Vault listener, ESO, CronJob, IngressRoute.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Phase 1 — PKI secrets engine
# ---------------------------------------------------------------------------

# Root CA mount — 10-year lifetime because rotating the root requires
# re-importing the cert on every device that trusts the homelab CA.
resource "vault_mount" "pki_root" {
  path                  = "pki"
  type                  = "pki"
  max_lease_ttl_seconds = 315360000 # 10 years
  description           = "Homelab Root CA"
}

# Root CA certificate — type = "internal" keeps the private key inside Vault.
# 4096-bit RSA is appropriate for a long-lived trust anchor.
resource "vault_pki_secret_backend_root_cert" "root" {
  backend     = vault_mount.pki_root.path
  type        = "internal"
  common_name = "homelab Root CA"
  issuer_name = "homelab-root"
  ttl         = "315360000"
  key_bits    = 4096
  key_type    = "rsa"
}

# AIA extensions on root-issued certs — clients use these to locate the CA
# cert and CRL without hardcoded paths.
resource "vault_pki_secret_backend_config_urls" "root_urls" {
  backend                 = vault_mount.pki_root.path
  issuing_certificates    = ["https://${local.vault_hostname}/v1/pki/ca"]
  crl_distribution_points = ["https://${local.vault_hostname}/v1/pki/crl"]
}

# Intermediate CA mount — 5-year lifetime. Signing leaf certs through the
# intermediate means if it were compromised, you revoke and reissue it without
# touching the root or any device trust stores.
resource "vault_mount" "pki_int" {
  path                  = "pki_int"
  type                  = "pki"
  max_lease_ttl_seconds = 157680000 # 5 years
  description           = "Homelab Intermediate CA"

  # Required for ACME clients — these headers must be present in ACME challenge
  # responses. Managed here rather than via vault_generic_endpoint to avoid
  # Terraform seeing drift every plan from the mount reading them back.
  allowed_response_headers    = ["Last-Modified", "Location", "Replay-Nonce", "Link"]
  passthrough_request_headers = ["If-Modified-Since"]
}

# Intermediate CSR — type = "internal" keeps the intermediate key in Vault.
resource "vault_pki_secret_backend_intermediate_cert_request" "intermediate" {
  backend     = vault_mount.pki_int.path
  type        = "internal"
  common_name = "homelab Intermediate CA"
  key_bits    = 4096
  key_type    = "rsa"
}

# Root signs the intermediate CSR — establishes the chain of trust.
# depends_on is explicit because Terraform sees no attribute reference between
# the CSR and the root cert (they are on different mounts).
resource "vault_pki_secret_backend_root_sign_intermediate" "intermediate" {
  depends_on = [
    vault_pki_secret_backend_root_cert.root,
    vault_pki_secret_backend_intermediate_cert_request.intermediate,
  ]
  backend     = vault_mount.pki_root.path
  csr         = vault_pki_secret_backend_intermediate_cert_request.intermediate.csr
  common_name = "homelab Intermediate CA"
  issuer_ref  = vault_pki_secret_backend_root_cert.root.issuer_id
  ttl         = "157680000"
  format      = "pem_bundle"
}

# Import the signed intermediate cert back into pki_int to activate it.
resource "vault_pki_secret_backend_intermediate_set_signed" "intermediate" {
  depends_on  = [vault_pki_secret_backend_root_sign_intermediate.intermediate]
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.intermediate.certificate
}

# AIA extensions for intermediate-issued certs.
resource "vault_pki_secret_backend_config_urls" "int_urls" {
  depends_on              = [vault_pki_secret_backend_intermediate_set_signed.intermediate]
  backend                 = vault_mount.pki_int.path
  issuing_certificates    = ["https://${local.vault_hostname}/v1/pki_int/ca"]
  crl_distribution_points = ["https://${local.vault_hostname}/v1/pki_int/crl"]
}

# ACME directory base URL — advertised to ACME clients in the directory
# response. Vault is reachable at the external hostname via Traefik (which
# terminates TLS with the Let's Encrypt wildcard cert), so this URL works
# even before Vault's own TLS listener is enabled.
resource "vault_generic_endpoint" "pki_int_cluster" {
  depends_on           = [vault_mount.pki_int]
  path                 = "${vault_mount.pki_int.path}/config/cluster"
  ignore_absent_fields = true
  disable_delete       = true

  data_json = jsonencode({
    path     = "https://${local.vault_hostname}/v1/${vault_mount.pki_int.path}"
    aia_path = "https://${local.vault_hostname}/v1/${vault_mount.pki_int.path}"
  })
}

# PKI role — constrains what the intermediate CA will sign.
# allow_ip_sans = true is needed for 127.0.0.1 in Vault's own TLS cert
# (Vault health checks connect to localhost).
# no_store = false is required for ACME cert-status polling to work.
# 90-day leaf TTL; cert-manager renews at 2/3 TTL (~60 days).
resource "vault_pki_secret_backend_role" "internal" {
  depends_on = [vault_pki_secret_backend_intermediate_set_signed.intermediate]

  backend    = vault_mount.pki_int.path
  name       = "internal"
  issuer_ref = vault_pki_secret_backend_intermediate_set_signed.intermediate.imported_issuers[0]

  allowed_domains = [
    var.domain,               # e.g. lab.toastdog.net — all lab services
    "vault-internal",         # Vault pod DNS (vault-0.vault-internal, etc.)
    "vault.svc.cluster.local", # Vault k8s service DNS
    "svc.cluster.local",      # catch-all for other internal k8s service names
  ]
  allow_subdomains   = true
  allow_bare_domains = false
  allow_ip_sans      = true

  max_ttl  = "7776000" # 90 days
  key_type = "rsa"
  key_bits = 2048      # 2048 is sufficient for short-lived leaf certs
  no_store = false     # required for ACME cert-status polling
}

# ACME protocol on pki_int — must be enabled after tuning + cluster path.
# default_directory_policy binds ACME requests to the internal role so ACME
# clients are subject to the same domain restrictions as direct cert requests.
# EAB disabled because Vault is only reachable within the homelab network.
resource "vault_generic_endpoint" "pki_int_acme" {
  depends_on = [
    vault_pki_secret_backend_role.internal,
    vault_generic_endpoint.pki_int_cluster,
  ]
  path                 = "${vault_mount.pki_int.path}/config/acme"
  ignore_absent_fields = true
  disable_delete       = true

  data_json = jsonencode({
    enabled                  = true
    default_directory_policy = "role:${vault_pki_secret_backend_role.internal.name}"
  })
}

# cert-manager Vault policy — grants sign/issue on pki_int only.
resource "vault_policy" "cert_manager_pki" {
  name = "cert-manager-pki"
  policy = <<-EOT
    path "pki_int/sign/internal" {
      capabilities = ["create", "update"]
    }
    path "pki_int/issue/internal" {
      capabilities = ["create", "update"]
    }
  EOT
}

# cert-manager k8s auth role — binds the cert-manager SA (cert-manager ns)
# to the cert-manager-pki policy. Short TTL (10 min) per cert-manager docs;
# cert-manager re-auths for each certificate request.
resource "vault_kubernetes_auth_backend_role" "cert_manager_pki" {
  depends_on = [
    vault_auth_backend.kubernetes,
    vault_policy.cert_manager_pki,
  ]
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "cert-manager-pki"
  bound_service_account_names      = ["cert-manager"]
  bound_service_account_namespaces = ["cert-manager"]
  token_policies                   = [vault_policy.cert_manager_pki.name]
  token_ttl                        = 600 # 10 minutes
}

# ---------------------------------------------------------------------------
# Phase 2 — cert-manager Vault ClusterIssuer
# ---------------------------------------------------------------------------

# vault-internal ClusterIssuer — used exclusively for internal infrastructure
# certs (Vault listener TLS, future Raft peer certs). Let's Encrypt issuers
# in core/ remain unchanged for all public-facing certs.
#
# bootstrap_mode = true:  points to Vault HTTP (TLS not yet enabled on Vault)
# bootstrap_mode = false: switches to HTTPS + caBundle (Apply 2)
resource "kubernetes_manifest" "clusterissuer_vault_internal" {
  depends_on = [
    vault_pki_secret_backend_role.internal,
    vault_kubernetes_auth_backend_role.cert_manager_pki,
    vault_generic_endpoint.pki_int_acme,
  ]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata   = { name = "vault-internal" }
    spec = {
      vault = {
        server   = var.bootstrap_mode ? "http://vault.vault.svc.cluster.local:8200" : "https://vault.vault.svc.cluster.local:8200"
        path     = "pki_int/sign/internal"
        caBundle = var.bootstrap_mode ? null : base64encode(vault_pki_secret_backend_root_cert.root.certificate)
        auth = {
          kubernetes = {
            role      = vault_kubernetes_auth_backend_role.cert_manager_pki.role_name
            mountPath = "/v1/auth/kubernetes"
            serviceAccountRef = { name = "cert-manager" }
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Phase 3 — vault-tls Certificate
# ---------------------------------------------------------------------------

# SANs are kept minimal — only what each client actually resolves to:
# - vault.vault.svc.cluster.local: the FQDN used by ESO SecretStores, the ClusterIssuer, and the unseal CronJob
# - *.vault-internal: wildcard covers all pod DNS names for Raft (vault-0, vault-1, vault-2, and any future pods)
# - 127.0.0.1: Vault readiness probe connects to localhost
# External hostname (vault.lab.toastdog.net) is omitted — Traefik's ServersTransport validates
# against vault.vault.svc.cluster.local (set via serverName), not the external hostname.
resource "kubernetes_manifest" "vault_tls_cert" {
  depends_on = [kubernetes_manifest.clusterissuer_vault_internal]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata   = { name = "vault-tls", namespace = "vault" }
    spec = {
      secretName  = "vault-tls"
      duration    = "2160h"   # 90 days
      renewBefore = "720h"    # renew 30 days before expiry
      issuerRef = {
        name = "vault-internal"
        kind = "ClusterIssuer"
      }
      commonName = "vault.vault.svc.cluster.local"
      dnsNames = [
        "vault.vault.svc.cluster.local", # k8s service FQDN — used by ESO, ClusterIssuer, CronJob
        "*.vault-internal",              # Vault pod DNS for Raft (vault-0.vault-internal, etc.)
      ]
      ipAddresses = ["127.0.0.1"] # Vault readiness probe connects to localhost
    }
  }
}

# ---------------------------------------------------------------------------
# Phase 5.1 — Root CA secrets for ESO SecretStores and ServersTransport
# ---------------------------------------------------------------------------

# One secret per namespace that needs to verify Vault's TLS cert.
# ESO SecretStores reference this via caProvider; ServersTransport in the
# vault namespace references it via rootCAsSecrets.
# Created in Apply 1 (alongside the PKI) so the ServersTransport exists before
# vault-helm Apply 2 adds the IngressRoute serversTransport reference.
resource "kubernetes_secret_v1" "vault_internal_ca" {
  for_each   = toset(concat(var.vault_secret_stores, ["vault"]))
  depends_on = [vault_pki_secret_backend_root_cert.root]

  metadata {
    name      = "vault-internal-ca"
    namespace = each.key
  }
  data = {
    "ca.crt" = vault_pki_secret_backend_root_cert.root.certificate
  }
}

# ---------------------------------------------------------------------------
# Phase 5.3 — ServersTransport so Traefik can proxy HTTPS to Vault
# ---------------------------------------------------------------------------

# ServersTransport lives in the vault namespace so the vault IngressRoute
# (also in vault namespace) can reference it simply as "vault-https".
# rootCAsSecrets references the vault-internal-ca secret in the same namespace.
# serverName sets the TLS SNI for Traefik's backend connection to match
# the SAN in the vault-tls cert.
# Created unconditionally in Apply 1 so it exists before vault-helm Apply 2
# adds the serversTransport reference to the IngressRoute.
resource "kubernetes_manifest" "vault_servers_transport" {
  depends_on = [kubernetes_secret_v1.vault_internal_ca]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "ServersTransport"
    metadata   = { name = "vault-https", namespace = "vault" }
    spec = {
      serverName     = "vault.vault.svc.cluster.local"
      rootCAsSecrets = ["vault-internal-ca"]
    }
  }
}

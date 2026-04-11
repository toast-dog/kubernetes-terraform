resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = var.vault_version
  namespace        = "vault"
  create_namespace = true
  wait             = false # HA pods start sealed (readiness probe fails) — wait=true would hang

  values = [templatefile("${path.module}/config/vault-values.yaml", {
    tls_enabled = !var.bootstrap_mode
  })]
}

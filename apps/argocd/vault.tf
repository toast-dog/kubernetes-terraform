resource "random_password" "argocd_admin" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "argocd" {
  mount     = "secret"
  name      = "argocd/config"
  data_json = jsonencode({
    admin-password      = random_password.argocd_admin.result
    admin-password-hash = bcrypt(random_password.argocd_admin.result)
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

resource "random_password" "argocd_webhook" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "argocd_webhook" {
  mount     = "secret"
  name      = "argocd/webhook"
  data_json = jsonencode({
    secret = random_password.argocd_webhook.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

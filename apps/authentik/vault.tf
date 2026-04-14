resource "random_password" "authentik_secret_key" {
  length  = 50
  special = false
}

# Bootstrap-only password for the authentik database user. CNPG sets this during
# initdb. Once tf-kube-post-deploy/authentik runs, the Vault database engine static
# role takes ownership and rotates it immediately — this value becomes irrelevant.
resource "random_password" "authentik_db_user_bootstrap_password" {
  length  = 32
  special = false
}

# Permanent superuser password for the postgres user. Used by the Vault database
# engine as its management connection to rotate the authentik user's password.
# Never used by Authentik directly.
resource "random_password" "authentik_db_superuser_password" {
  length  = 32
  special = false
}

resource "vault_kv_secret_v2" "authentik" {
  mount     = "secret"
  name      = "authentik/config"
  data_json = jsonencode({
    secret-key                   = random_password.authentik_secret_key.result
    db-user-bootstrap-password   = random_password.authentik_db_user_bootstrap_password.result
    db-superuser-password        = random_password.authentik_db_superuser_password.result
    # Populated manually after Authentik is deployed — see tf-authentik bootstrap steps
    terraform-api-token          = ""
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

vault_version   = "0.32.0"  # renovate: datasource=helm registryUrl=https://helm.releases.hashicorp.com depName=vault
vault_image_tag = "1.21.4"  # renovate: datasource=docker depName=hashicorp/vault

external_secrets_version = "2.2.0"  # renovate: datasource=helm registryUrl=https://charts.external-secrets.io depName=external-secrets

# Add a namespace here to provision it with a vault-auth service account and SecretStore.
vault_secret_stores = []

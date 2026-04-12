include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "apps" {
  path = find_in_parent_folders("common.hcl")
}

# argocd/ must be applied first — the argocd namespace and argocd-secret must
# exist before ESO can merge the admin password hash into argocd-secret.
dependencies {
  paths = ["../../argocd"]
}

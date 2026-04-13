include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "apps" {
  path = find_in_parent_folders("common.hcl")
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

# First unit in the chain — nothing needs to exist before this one.

# Prevents concurrent node upgrades — for_each instances have no ordering otherwise.
terraform {
  extra_arguments "serial_apply" {
    commands  = ["plan", "apply"]
    arguments = ["-parallelism=1"]
  }
}

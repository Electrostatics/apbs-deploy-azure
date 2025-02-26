# Backend Deployment
For deploying this, we use workspaces. In `main.tf` we have the following:
```hcl
locals {
  # Workspace specific config
  workspace_config = {
    default = {
      resource_group_name          = "apbs-backend"
      app_name                     = "apbs-app"
      storage_account_name         = "apbsblobs"
      backend_role_definition_name = "APBS Backend Data Access"
      cpu                          = 4.0
      memory                       = "8Gi"
      image_tag                    = "latest"
      github_info = {
        repository    = "apbs-web-testing-fork"
        branch        = "aws-release"
        secret_prefix = "AZURE"
      }
      storage_policy = {
        inputs = {
          cool_after    = 14
          archive_after = 30
          delete_after  = 60
        }
        outputs = {
          cool_after    = 14
          archive_after = 30
          delete_after  = 60
        }
      }
    }
    dev = {
      resource_group_name          = "apbs-backend-dev"
      app_name                     = "apbs-app-dev"
      storage_account_name         = "apbsblobsdev"
      backend_role_definition_name = "APBS Backend Data Access Dev"
      cpu                          = 2.0
      memory                       = "4Gi"
      image_tag                    = "latest"
      github_info = {
        repository    = "apbs-web-testing-fork"
        branch        = "aws-release"
        secret_prefix = "AZURE_DEV"
      }
      storage_policy = {
        inputs = {
          cool_after    = null
          archive_after = null
          delete_after  = 7
        }
        outputs = {
          cool_after    = null
          archive_after = null
          delete_after  = 7
        }
      }
    }
  }
  env_config = lookup(local.workspace_config, terraform.workspace, local.workspace_config.dev)
  blobs      = ["inputs", "outputs"]
}
```

This allows us to have different configurations for different workspaces.
For example, in the `default` workspace, we have a `resource_group_name` of `apbs-backend` and an `app_name` of `apbs-app`.
In the `dev` workspace, we have a `resource_group_name` of `apbs-backend-dev` and an `app_name` of `apbs-app-dev`.
This setup allows for us to maintain a single file for both configurations and allows for easy switching between the two if needed.
Note the `env_config` variable. This attempts to look up the current workspace in the `workspace_config` map.
If it doesn't find it, it defaults to the `dev` configuration.

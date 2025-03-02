variable AzureEnvironment {
  default = "AZUREPUBLICCLOUD"
}

# variable KeyVaultSuffix {
#   default = "vault.azure.net"
# }

# variable BlobStorageSuffix {
#   default = "blob.core.windows.net"
# }

variable CreatedBy {
  default = ""
}

variable tenant_id {
  type = string
  description = "The azure tenant id the user is logged in"
  default = ""
}

variable logged_user_objectId {
  type = string
  description = "The azure user logged object id"
  default = "55d09668-f5c7-47f8-9f6a-2aeea3fd0c96"
}

variable "secret_user_object_ids" {
  type        = list(string)
  description = "List of object IDs to be assigned the Key Vault Secrets User role"
  default = ["55d09668-f5c7-47f8-9f6a-2aeea3fd0c96"]
}

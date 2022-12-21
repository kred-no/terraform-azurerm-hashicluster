# BASIC EXAMPLE

# Requirements

Azure credentials.

```hcl
# File (e.g. 'credentials.auto.tfvars')
tenant_id       = "<your-tenant-id>"
subscription_id = "<your-subscription-id>"
```

```bash
# Environment variables
export ARM_SUBSCRIPTION_ID="<your-tenant-id>"
export ARM_TENANT_ID="<your-subscription-id>"
```

## Resources:

  * 1 x Resource Group (outside of module)
  * 1 x Virtual Network (outside of module)
  * 1 x Subnet
  * 1 x Network Securit Group assigned to NIC (no rules)
  * 1 x Application Securit Group
  * 1 x Network Interface
  * 2 x Linux Virtual Machine


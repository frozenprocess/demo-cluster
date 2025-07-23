# GCP to Azure Conversion Notes

This document outlines the key changes made when converting the GCP Terraform configuration to Azure.

## Provider Changes

### GCP Provider → Azure Provider
```hcl
# GCP
provider "google" {
  project = var.project
  region  = var.region
}

# Azure
provider "azurerm" {
  features {}
}
```

## Resource Mapping

### 1. Networking
| GCP Resource | Azure Resource | Notes |
|--------------|----------------|-------|
| `google_compute_network` | `azurerm_virtual_network` | VNet with address space 10.0.0.0/16 |
| `google_compute_firewall` | `azurerm_network_security_group` | NSG with rules for SSH, K8s API, internal traffic |
| N/A | `azurerm_subnet` | Explicit subnet creation required in Azure |
| N/A | `azurerm_subnet_network_security_group_association` | Associates NSG with subnet |

### 2. Compute Resources
| GCP Resource | Azure Resource | Notes |
|--------------|----------------|-------|
| `google_compute_instance` | `azurerm_linux_virtual_machine` | Linux VM with Ubuntu 22.04 LTS |
| N/A | `azurerm_public_ip` | Explicit public IP creation required |
| N/A | `azurerm_network_interface` | Explicit NIC creation required |

### 3. Identity and Access Management
| GCP Resource | Azure Resource | Notes |
|--------------|----------------|-------|
| `google_service_account` | `azurerm_user_assigned_identity` | Managed identity for authentication |
| `google_project_iam_custom_role` | `azurerm_role_assignment` | Built-in Contributor role |
| `google_project_iam_member` | N/A | Role assignment handled by azurerm_role_assignment |

### 4. Storage and Keys
| GCP Resource | Azure Resource | Notes |
|--------------|----------------|-------|
| `tls_private_key` | `tls_private_key` | Same - SSH key generation |
| `local_file` | `local_file` | Same - Local file storage |

## Variable Changes

### Renamed Variables
- `region` → `location` (Azure terminology)
- `project` → Removed (not needed in Azure)
- `image_id` → Removed (using source_image_reference instead)

### Updated Default Values
- `cp_instance_type`: `n1-standard-4` → `Standard_D4s_v3`
- `worker_instance_type`: `n1-standard-2` → `Standard_D2s_v3`
- `cluster_domain`: `gcp.local` → `azure.local`
- `availability_zone_names`: GCP zones → Azure zones (1, 2, 3)

### Removed Variables
- `image_id` (replaced with source_image_reference in VM resource)
- `project` (not applicable in Azure)
- `enable_nested_virtualization` (not supported in Azure VMs)

## Key Architectural Differences

### 1. Resource Group
Azure requires all resources to be organized within a Resource Group, which doesn't exist in GCP.

### 2. Network Interface
Azure requires explicit creation of Network Interfaces, while GCP handles this automatically.

### 3. Public IP Addresses
Azure requires explicit creation of Public IP resources, while GCP creates them automatically with access_config.

### 4. Identity Management
- **GCP**: Uses service accounts with IAM roles and custom permissions
- **Azure**: Uses managed identities with built-in roles (Contributor)

### 5. Image Management
- **GCP**: Uses image family/name strings
- **Azure**: Uses publisher/offer/sku/version reference

## Security Differences

### Firewall Rules
- **GCP**: Firewall rules with tags and source ranges
- **Azure**: Network Security Group rules with priorities and address prefixes

### Authentication
- **GCP**: Service account keys and IAM
- **Azure**: Managed identity with role-based access control

## Cloud Provider Configuration

### GCP Cloud Config
```ini
[Global]
project-id=<project>
network-name=<network>
node-tags=<tags>
```

### Azure Cloud Config
```ini
[Global]
resource-group=<rg-name>
vnet-name=<vnet-name>
subnet-name=<subnet-name>
location=<location>
use-managed-identity-extension=true
use-instance-metadata=true
```

## Output Changes

### Updated Outputs
- `instance_1_public_ip`: Now references Azure public IP resource
- `instance_1_private_ip`: Now references Azure NIC private IP
- `workers_ip`: Updated to use Azure resource references

### New Outputs
- `resource_group_name`: Azure-specific resource group name
- `virtual_network_name`: Azure VNet name
- `subnet_name`: Azure subnet name

## Files Added

1. `files/azure/azure-controller.yaml` - Azure cloud controller manager configuration
2. `README.md` - Azure-specific documentation
3. `CONVERSION_NOTES.md` - This conversion documentation

## Usage Differences

### Authentication
```bash
# GCP
gcloud auth application-default login

# Azure
az login
az account set --subscription <subscription-id>
```

### Resource Management
- **GCP**: Resources are organized by project
- **Azure**: Resources are organized by resource group and subscription

## Cost Considerations

### Instance Pricing
- Azure D-series VMs are generally comparable to GCP n1-standard instances
- Pricing varies by region and availability
- Consider using Azure Reserved Instances for cost optimization

### Network Costs
- Azure charges for data transfer between regions
- Public IP addresses have associated costs
- Network Security Groups are free

## Migration Notes

When migrating from GCP to Azure:
1. Update authentication method
2. Adjust instance types to Azure equivalents
3. Review and update network security rules
4. Update cloud provider configurations
5. Test thoroughly in Azure environment before production use 
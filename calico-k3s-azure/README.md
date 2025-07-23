# Calico K3s Demo - Azure

This Terraform configuration deploys a K3s cluster with Calico networking on Microsoft Azure.

## Prerequisites

1. **Azure CLI** installed and authenticated
2. **Terraform** (version >= 1.0)
3. **Azure Subscription** with sufficient permissions

## Authentication

Before running this Terraform configuration, ensure you're authenticated with Azure:

```bash
az login
az account set --subscription <your-subscription-id>
```

## Key Differences from GCP Version

### Resource Mapping

| GCP Resource | Azure Equivalent |
|--------------|------------------|
| `google_compute_network` | `azurerm_virtual_network` |
| `google_compute_firewall` | `azurerm_network_security_group` |
| `google_compute_instance` | `azurerm_linux_virtual_machine` |
| `google_service_account` | `azurerm_user_assigned_identity` |
| `google_project_iam_custom_role` | `azurerm_role_assignment` |

### Instance Types

- **Control Plane**: `Standard_D4s_v3` (equivalent to GCP's `n1-standard-4`)
- **Worker Nodes**: `Standard_D2s_v3` (equivalent to GCP's `n1-standard-2`)

### Networking

- **VNet**: `10.0.0.0/16` with subnet `10.0.1.0/24`
- **Network Security Group**: Configured with rules for SSH (22), Kubernetes API (6443), and internal traffic
- **Public IPs**: Static allocation for all nodes

### Identity and Access Management

- Uses **User-Assigned Managed Identity** instead of service accounts
- **Contributor** role assigned to the managed identity for resource management
- No need for service account keys or IAM custom roles

## Configuration

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars-example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your specific values:
   - `location`: Azure region (e.g., "East US", "West Europe")
   - `cp_instance_type`: Control plane VM size
   - `worker_instance_type`: Worker node VM size
   - `worker_count`: Number of worker nodes

## Usage

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```

2. **Plan the deployment**:
   ```bash
   terraform plan
   ```

3. **Apply the configuration**:
   ```bash
   terraform apply
   ```

4. **Connect to the cluster**:
   ```bash
   ssh -i calico-demo.pem ubuntu@<control-plane-public-ip>
   ```

5. **Verify the cluster**:
   ```bash
   sudo k3s kubectl get nodes
   sudo k3s kubectl get pods -A
   ```

## Cleanup

To destroy all created resources:
```bash
terraform destroy
```

## Cloud Provider Integration

The Azure cloud provider is configured to:
- Use managed identity for authentication
- Configure load balancers and network resources
- Handle node management and scaling
- Provide cloud-native networking features

## Troubleshooting

### Common Issues

1. **Authentication Errors**: Ensure Azure CLI is logged in and has proper permissions
2. **Resource Quotas**: Check Azure subscription limits for VM instances and other resources
3. **Network Connectivity**: Verify NSG rules allow required traffic
4. **Managed Identity**: Ensure the managed identity has proper role assignments

### Logs and Debugging

- Check K3s logs: `sudo journalctl -u k3s -f`
- Check cloud controller logs: `sudo k3s kubectl logs -n kube-system deployment/azure-cloud-controller-manager`
- Check Calico logs: `sudo k3s kubectl logs -n kube-system -l k8s-app=calico-node`

## Security Considerations

- SSH keys are generated automatically and stored locally
- Network Security Groups restrict access to necessary ports only
- Managed Identity provides secure authentication without stored credentials
- All VMs use Ubuntu 22.04 LTS with latest security updates 
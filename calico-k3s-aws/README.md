# Calico K3s Demo - AWS

This Terraform configuration deploys a K3s cluster with Calico networking on Amazon Web Services (AWS).

## Prerequisites

1. **AWS CLI** installed and configured
2. **Terraform** (version >= 1.0)
3. **AWS Account** with sufficient permissions
4. **AWS Credentials** configured (via AWS CLI or environment variables)

## Authentication

Before running this Terraform configuration, ensure you're authenticated with AWS:

```bash
aws configure
# or
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-west-2"
```

## Key Features

### Recent Updates (Based on GCP Version)
- **GPU Support**: Added support for GPU-enabled worker nodes using AWS GPU instance types
- **Cloud Provider Integration**: Enhanced AWS cloud controller manager configuration
- **Improved Variables**: Better type definitions and descriptions
- **Enhanced Outputs**: Additional outputs for VPC, subnet, and security group information
- **Consistent Configuration**: Aligned with GCP version structure and features

### Instance Types
- **Control Plane**: `t3.medium` (2 vCPU, 4 GB RAM)
- **Worker Nodes**: `t3.small` (2 vCPU, 2 GB RAM)
- **GPU Workers**: `g4dn.xlarge` (4 vCPU, 16 GB RAM, 1 GPU) when enabled

### Networking
- **VPC**: `172.16.0.0/16` with two subnets across different availability zones
- **Security Group**: Configured with rules for SSH (22), Kubernetes API (6443), and internal traffic
- **Internet Gateway**: Provides internet access for all instances
- **Route Tables**: Proper routing configuration for internet connectivity

## Configuration

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars-example terraform.tfvars
   ```

2. Edit `terraform.tfvars` with your specific values:
   - `region`: AWS region (e.g., "us-west-2", "us-east-1")
   - `cp_instance_type`: Control plane instance type
   - `worker_instance_type`: Worker node instance type
   - `worker_count`: Number of worker nodes
   - `worker_enable_gpu`: Whether to use GPU instances for workers
   - `worker_gpu_type`: GPU instance type (e.g., "g4dn.xlarge")

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

## GPU Support

To enable GPU support for worker nodes:

1. Set `worker_enable_gpu = true` in your `terraform.tfvars`
2. Choose an appropriate GPU instance type in `worker_gpu_type`
3. Ensure your AWS account has access to GPU instances in the selected region

### Available GPU Instance Types
- `g4dn.xlarge`: 1 GPU, 4 vCPU, 16 GB RAM
- `g4dn.2xlarge`: 1 GPU, 8 vCPU, 32 GB RAM
- `g5.xlarge`: 1 GPU, 4 vCPU, 16 GB RAM
- `p3.2xlarge`: 1 GPU, 8 vCPU, 61 GB RAM

## Cloud Provider Integration

The AWS cloud provider is configured to:
- Use AWS IAM roles for authentication
- Configure load balancers and network resources
- Handle node management and scaling
- Provide cloud-native networking features

## Cleanup

To destroy all created resources:
```bash
terraform destroy
```

## Troubleshooting

### Common Issues

1. **Authentication Errors**: Ensure AWS credentials are properly configured
2. **Resource Quotas**: Check AWS account limits for EC2 instances and other resources
3. **Network Connectivity**: Verify security group rules allow required traffic
4. **GPU Instance Availability**: Ensure GPU instances are available in your region

### Logs and Debugging

- Check K3s logs: `sudo journalctl -u k3s -f`
- Check cloud controller logs: `sudo k3s kubectl logs -n kube-system deployment/aws-cloud-controller-manager`
- Check Calico logs: `sudo k3s kubectl logs -n kube-system -l k8s-app=calico-node`

## Security Considerations

- SSH keys are generated automatically and stored locally
- Security Groups restrict access to necessary ports only
- IAM roles provide secure authentication without stored credentials
- All instances use Ubuntu 22.04 LTS with latest security updates
- VPC isolation provides network-level security

## Cost Optimization

- Use Spot Instances for worker nodes to reduce costs
- Consider using AWS Savings Plans for long-term deployments
- Monitor resource usage with AWS CloudWatch
- Use appropriate instance types for your workload requirements

## Differences from GCP Version

| Feature | AWS | GCP |
|---------|-----|-----|
| Instance Types | t3.medium/small | n1-standard-4/2 |
| GPU Instances | g4dn.xlarge | n1-standard-4 with GPU |
| Networking | VPC + Security Groups | VPC + Firewall Rules |
| Authentication | IAM Roles | Service Accounts |
| Cloud Provider | AWS Cloud Controller | GCP Cloud Controller |
| Nested Virtualization | Not Supported | Supported | 
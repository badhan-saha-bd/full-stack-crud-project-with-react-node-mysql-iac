📦 Terraform Project: THREE-TIER-FULL-STACK-APP
📝 Overview
This Terraform project provisions a three-tier full stack application infrastructure on AWS, consisting of:

A VPC with public and private subnets

An EC2 instance for application tiers

A managed RDS database instance

The infrastructure is designed using Terraform best practices.

🔧 Prerequisites
Make sure you have the following installed and configured:

✅ Terraform Latest Version

✅ AWS CLI (with credentials configured via ~/.aws/credentials)

✅ SSH key pairs generated and stored locally

Naming convention for SSH keys:

🔑 Public Key: id_ed25519.pub

🔒 Private Key: id_ed25519

## 🚀 Usage

Follow these steps to deploy the infrastructure:

### 1. Clone the terraform repository

```bash
git clone https://github.com/your-org/full-stack-crud-project-with-react-node-mysql-iac.git
cd full-stack-crud-project-with-react-node-mysql-iac
```

### 2. Prepare the configuration

- Update the `profile` value in the `provider` block inside `provider.tf`
- Place your generated SSH key pairs into the `ssh-keys/` directory

### 3. Initialize the project

```bash
terraform init
```

### 4. Apply the configuration

```bash
terraform apply
```

> ✅ Confirm the apply step when prompted to create the resources.
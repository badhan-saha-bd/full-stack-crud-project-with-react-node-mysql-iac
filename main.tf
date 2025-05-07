data "aws_availability_zones" "available" {}

locals {
  arn = module.rds.db_instance_master_user_secret_arn
}

data "aws_secretsmanager_secret" "db_secret" {
  arn = local.arn
}

data "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id = data.aws_secretsmanager_secret.db_secret.id
}


locals {
  db_credentials = jsondecode(data.aws_secretsmanager_secret_version.db_secret_version.secret_string)
}


data "aws_ami" "ubuntu_latest" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (official Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  tags = {
    Project     = "three-tier-platform"
    Environment = "prod"
  }
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = "three-tier-platform-vpc"
  cidr = "10.0.0.0/16"

  azs                          = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets              = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets               = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  create_database_subnet_group = true
  enable_nat_gateway           = true
  single_nat_gateway           = true
  one_nat_gateway_per_az       = false

  tags = local.tags
}


module "ec2-security-group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"

  name        = "three-tier-platform-app-vm-sg"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for application vm"
  ingress_with_cidr_blocks = [
    {
      from_port   = 5000
      to_port     = 5000
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow access to frontend app"
    },
    {
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow access to backend app"
    },
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow SSH"
    },
  ]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}



resource "aws_key_pair" "local_key" {
  key_name   = "three-tier-platform-vm-access-key"
  public_key = file("${path.module}/ssh-keys/id_ed25519.pub")
}


module "ec2-instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.8.0"

  ami                    = data.aws_ami.ubuntu_latest.id
  name                   = "three-tier-app-vm"
  instance_type          = "t3.micro"
  monitoring             = true
  key_name               = aws_key_pair.local_key.key_name
  vpc_security_group_ids = [module.ec2-security-group.security_group_id]
  subnet_id              = element(module.vpc.public_subnets, 0)
  create_eip             = true

  root_block_device = [
    {
      encrypted   = true
      volume_type = "gp3"
      throughput  = 200
      volume_size = 50
    },
  ]

}


resource "null_resource" "provision_ec2" {
  depends_on = [module.ec2-instance, module.rds]

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "sudo apt update && sudo apt upgrade -y",
      "curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -",
      "sudo apt install -y nodejs git",
      "sudo npm install pm2@latest -g",

      "git clone https://github.com/amir-projects/full-stack-crud-project-with-react-node-mysql",
      "cd full-stack-crud-project-with-react-node-mysql/server",
      "npm install",
      "cp .env.example .env",
      "sed -i 's/^DB_HOST=.*/DB_HOST=${module.rds.db_instance_address}/' .env",
      "sed -i 's/^DB_USER=.*/DB_USER=admin/' .env",
      "sed -i 's/^DB_PASSWORD=.*/DB_PASSWORD=${local.db_credentials.password}/' .env",
      "sed -i 's/^DB_DATABASE=.*/DB_DATABASE=crud_operations/' .env",
      "PORT=3000 pm2 start index.js --name api-server --watch",

      "cd ../frontend",
      "npm install",
      "cp .env.example .env",
      "if grep -q '^VITE_API_URL=' .env; then sed -i 's|^VITE_API_URL=.*|VITE_API_URL=http://${module.ec2-instance.public_ip}:3000|' .env; else echo 'VITE_API_URL=http://${module.ec2-instance.public_ip}:3000' >> .env; fi",
      "pm2 start \"npm run dev -- --host 0.0.0.0\" --name react-app"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("${path.module}/ssh-keys/id_ed25519")
      host        = module.ec2-instance.public_ip
    }
  }
}


module "rds-security-group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"

  name        = "three-tier-platform-database-sg"
  description = "Security group for database"
  vpc_id      = module.vpc.vpc_id
  tags        = local.tags

  ingress_with_cidr_blocks = [
    {
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      cidr_blocks = module.vpc.vpc_cidr_block
      description = "Allow MySQL Connectivity from within VPC"
    }
  ]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}


module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.12.0"

  identifier                  = "three-tier-platform-database"
  engine                      = "mysql"
  engine_version              = "8.0"
  family                      = "mysql8.0"
  major_engine_version        = "8.0"
  instance_class              = "db.t3.micro"
  create_db_parameter_group   = false
  allocated_storage           = 10
  max_allocated_storage       = 100
  db_name                     = "crud_operations"
  username                    = "admin"
  # password                    = "User12345random25!"
  port                        = 3306
  multi_az                    = false
  deletion_protection         = false
  # manage_master_user_password = false
  create_db_subnet_group      = true
  subnet_ids                  = module.vpc.private_subnets
  skip_final_snapshot         = true
  vpc_security_group_ids      = [module.rds-security-group.security_group_id]
}




packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.2.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

variable "ami_parameter_store_name" {
  type        = string
  description = "Parameter Store name to store the AMI ID"
  default     = "/ami-factory/github-actions-linux-ami-id"
}

variable "aws_region" {
  type        = string
  description = "AWS region for building the AMI"
  default     = "ap-south-1"
}

source "amazon-ebs" "linux" {
  region            = var.aws_region
  source_ami        = "ami-0d351f1b760a30161"
  instance_type     = "t3.micro"
  ssh_username      = "ec2-user"
  ami_name          = "github-actions-linux-{{timestamp}}"
  tags = {
    CreatedBy = "GitHubActions"
    BuildTime = "{{timestamp}}"
  }
}

build {
  sources = [
    "source.amazon-ebs.linux"
  ]

  # Keep a small shell provisioner to ensure the instance is up-to-date
  # and has Python3 available for Ansible if necessary.
  provisioner "shell" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y python3"
    ]
  }

  # Run the Ansible playbook to install git, wget, and Java (ansible/playbook.yml).
  # This requires that the machine running Packer has Ansible installed when using
  # the "ansible" provisioner. If you'd rather run Ansible on the instance itself,
  # switch to the "ansible-local" provisioner and ensure Ansible is installed there.
  provisioner "ansible" {
    playbook_file = "../ansible/playbook.yml"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }

  post-processor "shell-local" {
    inline = [
      "ami_id=$(jq -r '.builds[0].artifact_id' manifest.json | cut -d ':' -f2)",
      "echo \"Uploading AMI ID to Parameter Store: $ami_id\"",
      "aws ssm put-parameter --name ${var.ami_parameter_store_name} --value $ami_id --type String --overwrite --region ${var.aws_region}"
    ]
  }
}

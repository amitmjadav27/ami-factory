packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.2.0"
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
  source_ami        = "ami-0685bcc683dadb6b9"
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

  provisioner "shell" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y git",
      "sudo yum install -y wget"
    ]
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

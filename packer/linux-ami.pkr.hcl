packer {

  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.2.0"
    }
  }
}

source "amazon-ebs" "linux" {

  region = "ap-south-1"
  source_ami = "ami-0685bcc683dadb6b9"
  instance_type = "t3.micro"
  ssh_username = "ec2-user"
  ami_name = "github-actions-linux-{{timestamp}}"
}

build {
  sources = [
    "source.amazon-ebs.linux"
  ]

  provisioner "ansible" {
    playbook_file = "../ansible/playbook.yml"
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}
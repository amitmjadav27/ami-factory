# AWS AMI Factory using GitHub Actions and Packer

## Overview

This project demonstrates how to create a custom Amazon Machine Image (AMI) using:

* GitHub Actions
* HashiCorp Packer
* AWS EC2

The pipeline launches a temporary EC2 instance from a base AMI, performs software installation using Packer provisioners, creates a new AMI, and outputs the generated AMI ID.


---

## Architecture

```text
GitHub Actions
      │
      ▼
Checkout Repository
      │
      ▼
Configure AWS Credentials
      │
      ▼
Packer Build
      │
      ▼
Launch Temporary EC2 Builder
      │
      ▼
Install Software
      │
      ▼
Create New AMI
      │
      ▼
Terminate Builder Instance
      │
      ▼
Output New AMI ID
```

---

## Repository Structure

```text
.
├── .github
│   └── workflows
│       └── build-ami.yml
│
├── packer
│   └── linux-ami.pkr.hcl
│
├── ansible
│   └── playbook.yml
│
└── README.md
```

---

## Prerequisites

### AWS

Create an IAM User or IAM Role with permissions to:

* Launch EC2 Instances
* Create AMIs
* Create Security Groups
* Read AMIs
* Terminate EC2 Instances

Example permissions:

* AmazonEC2FullAccess

For production environments, use least-privilege policies.

---

### GitHub Secrets

Configure the following repository secrets:

| Secret Name           | Description           |
| --------------------- | --------------------- |
| AWS_ACCESS_KEY_ID     | AWS Access Key        |
| AWS_SECRET_ACCESS_KEY | AWS Secret Access Key |

Repository Settings → Secrets and Variables → Actions

---

## Packer Configuration

Current implementation uses:

* Amazon EBS Builder
* Amazon Linux Base AMI
* Shell Provisioner

Example software installed:

* Git
* Wget

Future versions will use:

* Ansible Provisioner
* Environment-specific Playbooks
* Enterprise Configuration Management

---

## GitHub Actions Workflow

The workflow can be triggered manually.

### Trigger Workflow

Navigate to:

Actions → Build Linux AMI → Run Workflow

---

## Workflow Steps

1. Checkout Source Code
2. Configure AWS Credentials
3. Install Packer
4. Validate Packer Template
5. Launch Temporary Builder Instance
6. Install Software
7. Create AMI
8. Generate Manifest File
9. Display New AMI ID

---

## Packer Build Process

```text
Base AMI
    │
    ▼
Temporary EC2 Builder
    │
    ▼
Install Packages
    │
    ▼
Create New AMI
    │
    ▼
Terminate Builder Instance
```

---

## Output

At the end of the workflow, the AMI ID is displayed in GitHub Actions logs.

Example:

```text
NEW AMI ID = ami-0123456789abcdef0
```

---

## Future Enhancements

Planned enhancements include:

* Ansible Integration
* Environment Configuration (NPE / PROD)
* build.yml Support
* AWS Systems Manager Parameter Store
* AWS CDK Integration
* CloudFormation Deployment
* Cross-Account AMI Sharing
* KMS Encryption
* Windows AMI Support
* WinRM Configuration
* Jenkins to GitHub Actions Full Migration

---

## Troubleshooting

### Packer Validate Fails

Verify:

* Base AMI ID exists
* AWS credentials are valid
* Required plugins are installed

### AMI Build Fails

Verify:

* Security Group rules
* IAM permissions
* Base AMI accessibility

### Authentication Issues

Verify GitHub Secrets:

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

---

## Learning Objectives

This project demonstrates:

* Infrastructure Automation
* AWS AMI Creation
* GitHub Actions CI/CD
* Packer Fundamentals
* AWS Authentication
* DevOps Pipeline Migration Concepts

---

## Author

Amit Jadav

AWS Cloud | DevOps | Infrastructure Automation | GitHub Actions | Packer

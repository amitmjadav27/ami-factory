# Jenkins to GitHub Actions Pipeline Migration - Pre-requisite Document

## Document Purpose

This document outlines all prerequisites, technical requirements, and configuration steps needed to successfully migrate from an existing Jenkins-based AMI build pipeline to the GitHub Actions-based pipeline in this repository.

---

## Table of Contents

1. [Assessment & Planning](#assessment--planning)
2. [AWS Infrastructure Requirements](#aws-infrastructure-requirements)
3. [GitHub Configuration](#github-configuration)
4. [IAM User Setup](#iam-user-setup)
5. [Repository Configuration](#repository-configuration)
6. [Pipeline Variables & Secrets](#pipeline-variables--secrets)
7. [Testing & Validation](#testing--validation)
8. [Migration Checklist](#migration-checklist)
9. [Rollback & Contingency Plan](#rollback--contingency-plan)

---

## Assessment & Planning

### 1. Current Jenkins Pipeline Analysis

Before migration, document the following from your existing Jenkins pipeline:

| Item | Details | Notes |
|------|---------|-------|
| **Jenkins Server Details** | Address, version, plugins | |
| **Build Triggers** | Schedule, webhook, manual | |
| **Build Stages** | Each step in pipeline | |
| **Environment Variables** | All variables used | |
| **Credentials** | AWS keys, tokens, certificates | |
| **Source Control** | Repository, branch strategy | |
| **Build Artifacts** | Outputs, locations | |
| **Notifications** | Email, Slack, Teams | |
| **Build Duration** | Average time | |
| **Success/Failure Rate** | Historical metrics | |

### 2. Packer Configuration Review

Examine your current Packer template:

- Base AMI ID(s) being used
- Instance types for building
- Provisioning tools (Shell, Ansible, Chef, Puppet)
- Post-processors (manifest, EBS snapshots, encryption)
- Variable definitions and defaults
- AWS regions for deployment

### 3. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|-----------|
| Build failures during cutover | High | High | Run parallel pipelines for 1-2 weeks |
| AWS credential exposure | Medium | Critical | Use GitHub environment secrets + GitHub OIDC |
| Longer build times | Medium | Low | Optimize runner size if needed |
| Loss of build history | Low | Medium | Export Jenkins build logs before migration |
| Network/VPC access issues | Low | High | Pre-validate runner connectivity to AWS |

---

## AWS Infrastructure Requirements

### 1. AWS Account Setup

Verify you have access to the following:

- [ ] AWS Account with admin or delegated permissions
- [ ] AWS CLI v2 installed locally
- [ ] Appropriate AWS region(s) selected
- [ ] VPC and subnets for EC2 builder instances
- [ ] Internet Gateway for builder instance connectivity

### 2. AWS Networking

Ensure the following network setup:

```
GitHub Actions Runner (Public)
        │
        ├─── NAT Gateway / Public IP
        │
        ▼
AWS EC2 Builder Instance (Private/Public)
        │
        ├─── VPC Subnet
        ├─── Security Group (Allow SSH for Packer)
        │
        ▼
EC2 Services
│
├─── DescribeRegions
├─── DescribeImages
├─── DescribeInstances
├─── RunInstances
├─── TerminateInstances
├─── CreateImage
└─── CreateTags
```

### 3. Base AMI Verification

- [ ] Confirm base AMI ID(s) available in target AWS region
- [ ] Verify base AMI OS version (Amazon Linux 2, Ubuntu, etc.)
- [ ] Check base AMI is not deprecated
- [ ] Document base AMI details:
  - AMI ID: `_____________`
  - OS: `_____________`
  - Architecture: `_____________`
  - Region(s): `_____________`

### 4. Security Group Configuration

Create a dedicated security group for Packer builder instances:

```json
{
  "GroupName": "packer-builder-sg",
  "GroupDescription": "Security group for Packer AMI builders",
  "Ingress": [
    {
      "IpProtocol": "tcp",
      "FromPort": 22,
      "ToPort": 22,
      "IpRanges": [
        {
          "CidrIp": "0.0.0.0/0",
          "Description": "SSH from anywhere (restrict to GitHub Actions runner IPs if possible)"
        }
      ]
    }
  ],
  "Egress": [
    {
      "IpProtocol": "-1",
      "CidrIp": "0.0.0.0/0",
      "Description": "Allow all outbound"
    }
  ]
}
```

### 5. AWS Systems Manager (SSM) Parameter Store Setup

If storing AMI IDs in Parameter Store (as per current config):

- [ ] Create SSM parameters for each environment:
  - `/ami-factory/github-actions-linux-ami-id` (Production)
  - `/ami-factory/staging-linux-ami-id` (Staging - if applicable)

Example AWS CLI command:

```bash
aws ssm create-parameter \
  --name /ami-factory/github-actions-linux-ami-id \
  --type String \
  --value "ami-placeholder" \
  --region ap-south-1
```

---

## GitHub Configuration

### 1. Repository Settings

Navigate to: **Settings → General**

- [ ] Set repository visibility (Public/Private)
- [ ] Enable GitHub Actions
- [ ] Configure branch protection if needed:
  - Require status checks to pass
  - Require code reviews (if applicable)

### 2. GitHub Actions Permissions

Navigate to: **Settings → Actions → General**

- [ ] Ensure "Allow all actions and reusable workflows" is enabled
- [ ] Set workflow permissions:
  - `Read and write permissions` for workflows
  - `Allow GitHub Actions to create and approve pull requests`

### 3. Repository Secrets Configuration

Navigate to: **Settings → Secrets and variables → Actions**

These secrets are **NOT** in this repository yet and must be added:

```
Secret Name                | Value                          | Required
---------------------------|--------------------------------|----------
AWS_ACCESS_KEY_ID          | Your AWS Access Key ID         | ✓ Yes
AWS_SECRET_ACCESS_KEY      | Your AWS Secret Access Key     | ✓ Yes
AWS_REGION                 | ap-south-1 (or your region)    | ✓ Yes
AWS_VPC_SUBNET_ID          | vpc-xxxxx                      | Optional*
AWS_SECURITY_GROUP_ID      | sg-xxxxx                       | Optional*
SLACK_WEBHOOK_URL          | https://hooks.slack.com/...    | Optional
GITHUB_TOKEN               | Auto-provided by GitHub Actions| Auto
```

**Optional* : Required if your EC2 builder needs to launch in a specific VPC/subnet

---

## IAM User Setup

### 1. Create Dedicated IAM User

Create a service account specifically for CI/CD:

```bash
aws iam create-user --user-name ami-create-user --region ap-south-1
```

### 2. Generate Access Keys

```bash
aws iam create-access-key --user-name ami-create-user
```

**Output includes:**
- `AccessKeyId` → Store in GitHub as `AWS_ACCESS_KEY_ID`
- `SecretAccessKey` → Store in GitHub as `AWS_SECRET_ACCESS_KEY`

### 3. Attach Least-Privilege IAM Policy

**Option A: Maximum Security (Recommended)**

Create an inline policy with minimal required permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2BuilderPermissions",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeRegions",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSnapshots",
        "ec2:DescribeSubnets",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVpcs",
        "ec2:DescribeNetworkInterfaces",
        "ec2:CreateTags",
        "ec2:CreateImage",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:GetPasswordData",
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMParameterStorePermissions",
      "Effect": "Allow",
      "Action": [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": [
        "arn:aws:ssm:ap-south-1:471112572415:parameter/ami-factory/*"
      ]
    }
  ]
}
```

Attach the policy:

```bash
aws iam put-user-policy \
  --user-name ami-create-user \
  --policy-name ami-factory-policy \
  --policy-document file://ami-factory-policy.json
```

**Option B: Permissive (Development Only)**

```bash
aws iam attach-user-policy \
  --user-name ami-create-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
```

### 4. Optional: Use GitHub OIDC (Enhanced Security)

Instead of long-lived access keys, use temporary credentials via OIDC:

1. Create OIDC Provider in AWS IAM
2. Create IAM Role for GitHub Actions
3. Configure role trust policy
4. Update workflow to use `aws-actions/configure-aws-credentials` with OIDC

See AWS documentation: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect

---

## Repository Configuration

### 1. Verify Repository Structure

Ensure the following exists in your repository:

```
.
├── .github/
│   └── workflows/
│       └── build-ami.yml
├── packer/
│   └── linux-ami.pkr.hcl
├── ansible/
│   └── playbook.yml
└── README.md
```

- [ ] Workflows directory exists
- [ ] Packer templates copied/updated
- [ ] Ansible playbooks copied/updated
- [ ] Documentation updated

### 2. Update Packer Configuration

Review and update `packer/linux-ami.pkr.hcl`:

- [ ] Update `source_ami` to match your base image
- [ ] Update `ami_name` naming convention if needed
- [ ] Update `aws_region` to match your target region
- [ ] Update `instance_type` (t3.micro may not be suitable for complex builds)
- [ ] Update `ssh_username` based on base AMI OS:
  - Amazon Linux 2: `ec2-user`
  - Ubuntu: `ubuntu`
  - Windows: `Administrator`
- [ ] Update provisioning scripts (shell/Ansible commands)
- [ ] Update tags for tracking and compliance

### 3. Update GitHub Actions Workflow

Review and update `.github/workflows/build-ami.yml`:

- [ ] Update `aws-region` to match your AWS region
- [ ] Add additional build triggers:
  - Schedule (cron): `on: schedule: - cron: '0 2 * * SUN'`
  - Push to branch: `on: push: branches: [main]`
  - Pull requests: `on: pull_request:`
- [ ] Add environment variables if needed
- [ ] Configure runner size if t3.micro builder is too small
- [ ] Add notification steps (Slack, Teams, email)

---

## Pipeline Variables & Secrets

### 1. GitHub Secrets (Sensitive Data)

Must be stored as encrypted secrets (never in code):

```yaml
AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
AWS_REGION: ${{ secrets.AWS_REGION }}
```

### 2. GitHub Variables (Non-Sensitive Data)

Can be stored as repository/environment variables:

```yaml
AMI_PREFIX: "github-actions"
INSTANCE_TYPE: "t3.micro"
BASE_AMI_ID: "ami-0d351f1b760a30161"
PARAMETER_STORE_NAME: "/ami-factory/github-actions-linux-ami-id"
```

### 3. Environment-Specific Configuration

For multiple environments (DEV/STAGING/PROD):

```yaml
# .github/workflows/build-ami.yml
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment'
        required: true
        type: choice
        options:
          - dev
          - staging
          - production

env:
  ENVIRONMENT: ${{ github.event.inputs.environment }}

jobs:
  build:
    environment: ${{ github.event.inputs.environment }}
    runs-on: ubuntu-latest
```

Each environment can have its own secrets:
- `Settings → Environments → dev/staging/production → Environment secrets`

---

## Testing & Validation

### 1. Pre-Migration Validation

Before running production migrations, validate:

- [ ] **IAM Permissions Test**: Run Packer validate step
- [ ] **AWS Connectivity Test**: EC2 API calls from GitHub runner
- [ ] **Credential Rotation Test**: Update and test new AWS credentials
- [ ] **Network Test**: Verify runner can reach AWS endpoints

### 2. Dry-Run Build

Execute a test build to verify:

```bash
# Step 1: Validate Packer template
packer validate packer/linux-ami.pkr.hcl

# Step 2: Format check
packer fmt -check packer/

# Step 3: Inspect Packer configuration
packer inspect packer/linux-ami.pkr.hcl
```

### 3. Manual Build Test

Before running GitHub Actions workflow, test locally:

```bash
# Prerequisites
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="ap-south-1"

# Initialize Packer
cd packer
packer init .

# Validate
packer validate linux-ami.pkr.hcl

# Build (this creates a real AMI)
packer build linux-ami.pkr.hcl
```

### 4. GitHub Actions Workflow Test

Once manual build succeeds:

1. Push code to GitHub
2. Navigate to **Actions → Build Linux AMI**
3. Click **Run workflow**
4. Monitor logs for errors

### 5. Output Validation

Verify build artifacts:

- [ ] `manifest.json` file created
- [ ] AMI ID extracted correctly
- [ ] AMI visible in AWS EC2 console
- [ ] AMI tags applied correctly
- [ ] SSM Parameter Store updated with AMI ID

---

## Migration Checklist

### Phase 1: Planning & Assessment (Week 1)

- [ ] Document current Jenkins pipeline configuration
- [ ] Identify all environment variables and credentials
- [ ] Review Packer/Ansible templates
- [ ] Risk assessment completed
- [ ] Stakeholder approval obtained

### Phase 2: AWS Preparation (Week 1-2)

- [ ] AWS account verified and access confirmed
- [ ] Base AMI ID confirmed in target region
- [ ] Security group created for builder instances
- [ ] VPC/Subnet configuration verified
- [ ] SSM Parameter Store paths created
- [ ] IAM user `ami-create-user` created
- [ ] IAM policy attached with correct permissions
- [ ] Access keys generated and securely stored

### Phase 3: GitHub Configuration (Week 2)

- [ ] Repository cloned/forked
- [ ] Packer templates updated with current configuration
- [ ] Ansible playbooks updated if needed
- [ ] GitHub repository secrets created:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_REGION`
- [ ] GitHub Actions permissions configured
- [ ] Workflow file reviewed and updated

### Phase 4: Testing & Validation (Week 2-3)

- [ ] Local Packer validation successful
- [ ] Manual build test completed
- [ ] GitHub Actions workflow first run successful
- [ ] Output AMI verified in AWS console
- [ ] SSM Parameter Store updated correctly
- [ ] Build times compared to Jenkins baseline
- [ ] Notifications configured (Slack/Email/Teams)

### Phase 5: Migration & Cutover (Week 3-4)

- [ ] Parallel pipeline runs: GitHub Actions vs Jenkins (1-2 weeks)
- [ ] Success rate comparison
- [ ] Build time comparison
- [ ] Jenkins pipeline disabled (after validation period)
- [ ] Documentation updated
- [ ] Team training completed
- [ ] Rollback plan reviewed

### Phase 6: Monitoring & Optimization (Ongoing)

- [ ] Monitor GitHub Actions workflow runs
- [ ] Alert configuration for failed builds
- [ ] Regular access key rotation schedule
- [ ] Performance optimization if needed
- [ ] Security audit quarterly

---

## Rollback & Contingency Plan

### Rollback Scenario 1: GitHub Actions Workflow Failures

**If GitHub Actions builds consistently fail:**

1. **Immediate Action**
   - Revert workflow file to known good state
   - Check GitHub Actions status page
   - Verify IAM credentials haven't expired

2. **Investigation**
   - Review workflow logs in Actions tab
   - Test IAM permissions manually
   - Validate Packer template locally

3. **Keep Jenkins Running**
   - Don't disable Jenkins pipeline until >90% GitHub Actions success rate
   - Maintain Jenkins pipeline in standby mode for 2 weeks

### Rollback Scenario 2: AWS Credential Compromise

**If AWS keys are exposed:**

1. **Immediate Action**
   ```bash
   # Deactivate compromised keys
   aws iam delete-access-key \
     --user-name ami-create-user \
     --access-key-id AKIAIOSFODNN7EXAMPLE
   ```

2. **Generate New Keys**
   ```bash
   aws iam create-access-key --user-name ami-create-user
   ```

3. **Update GitHub Secrets**
   - Update `AWS_ACCESS_KEY_ID` in GitHub
   - Update `AWS_SECRET_ACCESS_KEY` in GitHub

4. **Monitor**
   - Check AWS CloudTrail for unauthorized access
   - Review EC2 instances for unexpected launches

### Rollback Scenario 3: Performance Degradation

**If GitHub Actions builds are significantly slower than Jenkins:**

1. **Analyze**
   - Compare build logs (Jenkins vs GitHub Actions)
   - Check GitHub runner resource utilization
   - Identify bottlenecks (network, storage, compute)

2. **Optimize**
   - Upgrade runner instance type
   - Use self-hosted runners for faster builds
   - Optimize provisioning scripts

3. **Options**
   - Scale GitHub Actions runner resources
   - Use GitHub Actions + self-hosted runner hybrid
   - Keep Jenkins for critical builds while optimizing

### Emergency Contacts & Escalation

| Role | Name | Contact | Escalation |
|------|------|---------|-----------|
| Cloud Admin | | | |
| DevOps Lead | | | |
| Security Officer | | | |
| AWS Support | | | |

---

## Success Criteria

### Build 1: Manual Local Validation

✓ Packer validate passes  
✓ Manual `packer build` creates AMI without errors  
✓ New AMI appears in AWS EC2 console  

### Build 2: First GitHub Actions Run

✓ Workflow completes without errors  
✓ AMI ID extracted correctly  
✓ SSM Parameter Store updated  
✓ Build time within 10% of Jenkins baseline  

### Build 3: Production Equivalent

✓ Successful 5 consecutive builds  
✓ All tags applied correctly  
✓ No IAM permission errors  
✓ Notifications working (Slack/Email)  

### Cutover Decision Criteria

Before disabling Jenkins:

- ✓ 10+ successful GitHub Actions builds
- ✓ 2-week parallel pipeline validation
- ✓ Team trained on new workflow
- ✓ Documentation complete
- ✓ Support team prepared
- ✓ Rollback plan tested

---

## Additional Resources

### Documentation
- [GitHub Actions Official Docs](https://docs.github.com/en/actions)
- [HashiCorp Packer Docs](https://www.packer.io/docs)
- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

### AWS CLI Commands Cheat Sheet

```bash
# List IAM users
aws iam list-users

# Create IAM user
aws iam create-user --user-name ami-create-user

# Create access keys
aws iam create-access-key --user-name ami-create-user

# Attach policy
aws iam put-user-policy --user-name ami-create-user \
  --policy-name ami-factory-policy \
  --policy-document file://policy.json

# List AMIs
aws ec2 describe-images --owners self --region ap-south-1

# List SSM parameters
aws ssm describe-parameters --region ap-south-1

# Get parameter value
aws ssm get-parameter --name /ami-factory/github-actions-linux-ami-id --region ap-south-1
```

### GitHub Actions Useful Commands

```bash
# Test GitHub Actions locally (using act)
act workflow_dispatch -j build

# View workflow file syntax
yq eval .github/workflows/build-ami.yml

# Debug: Print all environment variables
- run: env | sort
```

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Migration Lead | | | |
| Cloud/DevOps Manager | | | |
| Security Lead | | | |
| Project Manager | | | |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-07-01 | Amit Jadav | Initial migration prerequisites document |

---

**Last Updated:** 2026-07-01  
**Document Classification:** Internal Use  
**Next Review Date:** Upon first GitHub Actions production deployment

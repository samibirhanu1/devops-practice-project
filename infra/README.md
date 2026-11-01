# Terraform (`infra/`)

Creates the AWS environment for the Task Tracker app: a VPC with one public subnet, an internet gateway and route table, a security group (SSH from one IP, HTTP from anywhere, all outbound allowed), an SSH key pair, and one Ubuntu 24.04 EC2 instance. The instance configures itself on first boot by running `scripts/init-server.sh`, which is passed in as `user_data`. The public IP is printed as an output.

## What has and has not been tested

| Check | Status |
|---|---|
| `terraform fmt` | Done, no changes needed |
| `terraform init` (AWS provider v6.71.0) | Done |
| `terraform validate` | Passed |
| `terraform plan` / `apply` against real AWS | **Not run** (no AWS account used yet) |
| Run against an emulator | **Not run** (the `use_emulator` switch exists but is untested) |
| `user_data` script running on a real instance | **Not tested** |

Before writing these files I practiced the `init`, `plan`, `apply` and `destroy` workflow, including re-running `apply` to see "No changes", in a throwaway project that used the `local` provider (it only created a text file). That practice project is not part of this repository.

## Usage

```
cd infra
copy terraform.tfvars.example terraform.tfvars   (then edit the values)
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output public_ip
terraform destroy
```

AWS credentials come from the environment or the AWS CLI profile and are never stored in this repository. `terraform.tfvars` and the state file are git-ignored.

## Known limitations

- SSH (port 22) is limited to one IP address, so a GitHub-hosted runner cannot reach it. The pipeline's deploy stage needs a decision: open SSH, use a self-hosted runner, or use AWS Systems Manager.
- HTTP only. There is no HTTPS yet.
- State is local. A team would use a remote backend with locking.
- The Docker install, firewall and systemd parts of `init-server.sh` can only be verified on a real VM.

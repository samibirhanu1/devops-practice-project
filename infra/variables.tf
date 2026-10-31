variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.micro"
}

variable "ssh_allowed_cidr" {
  description = "Your public IP in CIDR form, for example 203.0.113.7/32. Only this address may use SSH."
  type        = string

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid CIDR block, for example 203.0.113.7/32."
  }
}

variable "deployer_public_key" {
  description = "Contents of the SSH PUBLIC key (the .pub file) allowed to log in as deployer"
  type        = string
}

variable "ami_id" {
  description = "Optional image override. Leave empty to look up the latest Ubuntu 24.04."
  type        = string
  default     = ""
}

variable "use_emulator" {
  description = "Point the AWS provider at a local emulator instead of real AWS"
  type        = bool
  default     = false
}

variable "emulator_endpoint" {
  description = "Emulator address, used only when use_emulator is true"
  type        = string
  default     = "http://localhost:4566"
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "travelmemory"
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI ID for the selected AWS region"
  type        = string
}

variable "admin_cidr" {
  description = "SSH source CIDR; 0.0.0.0/0 allows SSH from anywhere"
  type        = string
}

variable "public_key_path" {
  type    = string
  default = "~/.ssh/travelmemory.pub"
}


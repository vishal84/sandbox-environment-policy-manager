# 1. Variables
variable "project_id" {
  default = "mongo-experiments"
}

variable "region" {
  default = "us-central1"
}

variable "zone" {
  default = "us-central1-f"
}

variable "instance_duration_hours" {
  type    = number
  default = 6
}

locals {
  total_seconds = floor(var.instance_duration_hours * 3600)
}

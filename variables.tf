# 1. Variables
variable "project_id" {
  default = "gemini-ent-agent-demos"
}

variable "region" {
  default = "us-east4"
}

variable "zone" {
  default = "us-east4-a"
}

variable "instance_duration_hours" {
  type    = number
  default = 2.5
}

locals {
  total_seconds = floor(var.instance_duration_hours * 3600)
}

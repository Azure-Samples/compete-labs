variable "ssh_public_key" {
  description = "value for ssh public key"
  type        = string
}

variable "owner" {
  description = "user running this lab"
  type        = string
}

variable "region" {
  description = "region to deploy resources"
  type        = string
}

variable "zone_suffix" {
  description = "zone suffix"
  type        = string
}

variable "capacity_reservation_id" {
  description = "capacity reservation id"
  type        = string
}

variable "run_id" {
  description = "unique id for this run"
  type        = string
}
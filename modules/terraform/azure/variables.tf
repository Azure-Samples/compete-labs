variable "ssh_public_key" {
  description = "value for ssh public key"
  type        = string
}

variable "owner" {
  description = "user running this lab"
  type        = string
}

variable "run_id" {
  description = "unique id for this run"
  type        = string
}

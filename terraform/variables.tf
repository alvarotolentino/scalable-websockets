variable "project_name" {
  description = "Name of the Latitude.sh project"
  type        = string
  default     = "scalable-websockets"
}

variable "environment" {
  description = "Project environment"
  type        = string
  default     = "Development"
}

variable "server_plan" {
  description = "Server machine plan (bare-metal SKU)"
  type        = string
  default     = "c3-large-x86"
}

variable "client_plan" {
  description = "Client machine plan (bare-metal SKU)"
  type        = string
  default     = "c2-small-x86"
}

variable "client_count" {
  description = "Number of load-test client machines"
  type        = number
  default     = 4
}

variable "site" {
  description = "Latitude.sh site/region"
  type        = string
  default     = "DAL2"
}

variable "os" {
  description = "Operating system slug"
  type        = string
  default     = "ubuntu_24_04_x64_lts"
}

variable "ssh_public_key" {
  description = "SSH public key content for deploy access"
  type        = string
  sensitive   = false
}

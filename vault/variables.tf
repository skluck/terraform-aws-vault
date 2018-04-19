variable "prefix" {}

variable "vpc_id" {}

variable "subnet_ids" {
  type = "list"
}

variable "alb_subnet_ids" {
  type = "list"
}

variable "zone_name" {}

variable "ami_id" {
  description = "The ID of the AMI to run in the cluster. This should be an AMI built from the Packer template under examples/vault-consul-ami/vault-consul.json."
}

variable "ssh_key_name" {}

variable "s3_bucket_prefix" {}

variable "force_destroy_s3_bucket" {
  description = "Enable or disable ability to destroy non-empty S3 buckets"
}

variable "allowed_inbound_security_group_ids" {
  type = "list"
}

# ---------------------------------------------------------------------------------------------------------------------
# vault
# ---------------------------------------------------------------------------------------------------------------------

variable "vault_cluster_name" {}
variable "vault_cluster_size" {}
variable "vault_instance_type" {}

variable "vault_asg_extra_tags" {
  type = "list"
}

# ---------------------------------------------------------------------------------------------------------------------
# consul
# ---------------------------------------------------------------------------------------------------------------------

variable "consul_cluster_tag_key" {}
variable "consul_cluster_name" {}
variable "consul_cluster_size" {}
variable "consul_instance_type" {}

variable "consul_asg_extra_tags" {
  type = "list"
}

# ---------------------------------------------------------------------------------------------------------------------
# private certificate (cluster traffic)
# ---------------------------------------------------------------------------------------------------------------------

variable "organization_name" {
  description = "The name of the organization to associate with the certificates (e.g. Acme Co)."
}

variable "ca_common_name" {
  description = "The common name to use in the subject of the CA certificate (e.g. acme.co cert)."
}

variable "common_name" {
  description = "The common name to use in the subject of the certificate (e.g. acme.co cert)."
}

# ---------------------------------------------------------------------------------------------------------------------
# installation
# ---------------------------------------------------------------------------------------------------------------------

variable "vault_version" {}
variable "consul_version" {}

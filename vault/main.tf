locals {
  vault_lb_port = 80
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CLUSTERS IN THE DEFAULT VPC AND AVAILABILITY ZONES
# ---------------------------------------------------------------------------------------------------------------------

data "aws_region" "current" {}

data "aws_vpc" "selected" {
  id = "${var.vpc_id}"
}

data "aws_route53_zone" "hosted_zone" {
  name = "${var.zone_name}."
}

# ---------------------------------------------------------------------------------------------------------------------
# GENERATE PRIVATE TLS CERTS
# ---------------------------------------------------------------------------------------------------------------------

module "tls_certs" {
  source  = "git::https://github.com/skluck/tls-cert-self-signed-tf.git?ref=master"

  organization_name = "${var.organization_name}"
  ca_common_name    = "${var.ca_common_name}"
  common_name       = "${var.common_name}"

  dns_names = [
    "vault.service.consul"
  ]

  ip_addresses = [
    "127.0.0.1"
  ]

  validity_period_hours = 175200
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH VAULT SERVER WHEN IT'S BOOTING
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_vault_cluster" {
  template = "${file("${path.module}/templates/user-data-vault.sh")}"

  vars {
    vault_version  = "${var.vault_version}"
    consul_version = "${var.consul_version}"

    ca_cert_pem    = "${module.tls_certs.ca_public_key_file}"
    vault_cert_pem = "${module.tls_certs.public_key_file}"
    vault_key_pem  = "${module.tls_certs.private_key_file}"

    aws_region           = "${data.aws_region.current.name}"
    s3_vault_bucket_name = "${var.s3_bucket_prefix}-vault"

    consul_cluster_tag_key   = "${var.consul_cluster_tag_key}"
    consul_cluster_tag_value = "${var.consul_cluster_name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE VAULT SERVER CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "vault_cluster" {
  source  = "hashicorp/vault/aws//modules/vault-cluster"
  version = "0.5.1"

  cluster_name = "${var.vault_cluster_name}"
  cluster_size = "${var.vault_cluster_size}"

  instance_type    = "${var.vault_instance_type}"
  root_volume_type = "gp2"

  ami_id    = "${var.ami_id}"
  user_data = "${data.template_file.user_data_vault_cluster.rendered}"

  enable_s3_backend       = true
  s3_bucket_name          = "${var.s3_bucket_prefix}-vault"
  force_destroy_s3_bucket = "${var.force_destroy_s3_bucket}"

  vpc_id     = "${data.aws_vpc.selected.id}"
  subnet_ids = "${var.subnet_ids}"

  allowed_inbound_cidr_blocks        = []
  allowed_ssh_security_group_ids     = ["${var.allowed_inbound_security_group_ids}"]
  allowed_inbound_security_group_ids = []

  cluster_extra_tags = ["${var.vault_asg_extra_tags}"]

  ssh_key_name = "${var.ssh_key_name}"
}

module "vault_elb" {
  source  = "hashicorp/vault/aws//modules/vault-elb"
  version = "0.5.1"

  name           = "${var.prefix}-vault"
  vault_asg_name = "${module.vault_cluster.asg_name}"

  vpc_id     = "${data.aws_vpc.selected.id}"
  subnet_ids = ["${var.alb_subnet_ids}"]

  create_dns_entry = true
  hosted_zone_id   = "${data.aws_route53_zone.hosted_zone.zone_id}"
  domain_name      = "${var.prefix}-vault.${data.aws_route53_zone.hosted_zone.name}"

  allowed_inbound_cidr_blocks = ["${data.aws_vpc.selected.cidr_block}"]

  internal = true
  lb_port  = "${local.vault_lb_port}"
  health_check_protocol = "HTTP"
}

resource "aws_security_group_rule" "allow_elb_to_vault_instances" {
  type        = "ingress"
  from_port   = 8200
  to_port     = 8200
  protocol    = "tcp"

  source_security_group_id = "${module.vault_elb.load_balancer_security_group_id}"
  security_group_id        = "${module.vault_cluster.security_group_id}"
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH IAM POLICIES FOR CONSUL
# To allow our Vault servers to automatically discover the Consul servers, we need to give them the IAM permissions from
# the Consul AWS Module's consul-iam-policies module.
# ---------------------------------------------------------------------------------------------------------------------

module "consul_iam_policies_servers" {
  source  = "hashicorp/consul/aws//modules/consul-iam-policies"
  version = "0.3.1"

  iam_role_id = "${module.vault_cluster.iam_role_id}"
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH CONSUL SERVER WHEN IT'S BOOTING
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_consul" {
  template = "${file("${path.module}/templates/user-data-consul.sh")}"

  vars {
    vault_version  = "${var.vault_version}"
    consul_version = "${var.consul_version}"

    ca_cert_pem    = "${module.tls_certs.ca_public_key_file}"
    vault_cert_pem = "${module.tls_certs.public_key_file}"
    vault_key_pem  = "${module.tls_certs.private_key_file}"

    consul_cluster_tag_key   = "${var.consul_cluster_tag_key}"
    consul_cluster_tag_value = "${var.consul_cluster_name}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CONSUL SERVER CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "consul_cluster" {
  source  = "hashicorp/consul/aws//modules/consul-cluster"
  version = "0.3.1"

  cluster_name = "${var.consul_cluster_name}"
  cluster_size = "${var.consul_cluster_size}"

  instance_type    = "${var.consul_instance_type}"
  root_volume_type = "gp2"

  # The EC2 Instances will use these tags to automatically discover each other and form a cluster
  cluster_tag_key   = "${var.consul_cluster_tag_key}"
  cluster_tag_value = "${var.consul_cluster_name}"

  ami_id    = "${var.ami_id}"
  user_data = "${data.template_file.user_data_consul.rendered}"

  vpc_id     = "${data.aws_vpc.selected.id}"
  subnet_ids = "${var.subnet_ids}"

  allowed_inbound_cidr_blocks        = ["${data.aws_vpc.selected.cidr_block}"]
  allowed_ssh_security_group_ids     = ["${var.allowed_inbound_security_group_ids}"]
  allowed_inbound_security_group_ids = []

  tags = ["${var.consul_asg_extra_tags}"]

  ssh_key_name = "${var.ssh_key_name}"
}

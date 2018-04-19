#!/bin/bash
set -e
set -x

# This script is meant to be run in the User Data of each EC2 Instance while it's booting. The script uses the
# run-consul script to configure and start Consul in server mode. Note that this script assumes it's running in an AMI
# built from the Packer template in examples/vault-consul-ami/vault-consul.json.

# Send the log output from this script to user-data.log, syslog, and the console
# From: https://alestic.com/2010/12/ec2-user-data-output/
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

readonly VAULT_TLS_CA_CERT_FILE="/opt/vault/tls/ca.crt.pem"
readonly VAULT_TLS_CERT_FILE="/opt/vault/tls/vault.crt.pem"
readonly VAULT_TLS_KEY_FILE="/opt/vault/tls/vault.key.pem"

echo "--------------------------------------"
echo "      Downloading Hashicorp Setup     "
echo "--------------------------------------"

apt-get update && apt-get install -y \
    zip unzip \
    curl \
    git \
    python-pip && \
    pip install awscli

# todo - fix this back to use hashi official repos
git clone "https://github.com/skluck/terraform-consul-vault-combined" "/tmp/tf-install" && \
    mkdir "/tmp/vault-installation" && \
    mv "/tmp/tf-install/terraform-aws-consul/modules/install-consul"          "/tmp/vault-installation/install-consul" && \
    mv "/tmp/tf-install/terraform-aws-consul/modules/install-dnsmasq"         "/tmp/vault-installation/install-dnsmasq" && \
    mv "/tmp/tf-install/terraform-aws-consul/modules/run-consul"              "/tmp/vault-installation/run-consul" && \
    mv "/tmp/tf-install/terraform-aws-vault/modules/update-certificate-store" "/tmp/vault-installation/update-certificate-store" && \
    mv "/tmp/tf-install/terraform-aws-vault/modules/install-vault"            "/tmp/vault-installation/install-vault" && \
    mv "/tmp/tf-install/terraform-aws-vault/modules/run-vault"                "/tmp/vault-installation/run-vault"

echo "--------------------------------------"
echo "       Installing Vault/Consul        "
echo "--------------------------------------"

/tmp/vault-installation/install-vault/install-vault --version "${vault_version}"
/tmp/vault-installation/install-consul/install-consul --version "${consul_version}"
/tmp/vault-installation/install-dnsmasq/install-dnsmasq

echo "--------------------------------------"
echo "        Installing CA Cert            "
echo "--------------------------------------"

cat - > $VAULT_TLS_CA_CERT_FILE <<'EOF'
${ca_cert_pem}
EOF

cat - > $VAULT_TLS_CERT_FILE <<'EOF'
${vault_cert_pem}
EOF

cat - > $VAULT_TLS_KEY_FILE <<'EOF'
${vault_key_pem}
EOF

chown -R vault:vault /opt/vault/tls/
chmod -R 600 /opt/vault/tls
chmod 700 /opt/vault/tls
/tmp/vault-installation/update-certificate-store/update-certificate-store --cert-file-path $VAULT_TLS_CA_CERT_FILE

echo "--------------------------------------"
echo "        Running Vault/Consul          "
echo "--------------------------------------"

/opt/consul/bin/run-consul \
    --server \
    --cluster-tag-key "${consul_cluster_tag_key}" \
    --cluster-tag-value "${consul_cluster_tag_value}"

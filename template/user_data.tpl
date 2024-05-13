#!/bin/bash
set +H
apt-get -y update && apt-get install -y awscli mysql-client libmysqlclient-dev jq
export AWS_REGION=${AWS_REGION}
export AWS_DEFAULT_REGION=${AWS_REGION}

DB_CREDS="$(aws secretsmanager get-secret-value --secret-id ${DB_SECRETS} | jq --raw-output '.SecretString')"
OPENVPN_CREDS="$(aws secretsmanager get-secret-value --secret-id ${OPENVPN_ADMIN_SECRETS} | jq --raw-output '.SecretString')"

DB_USER="$(echo $DB_CREDS | jq -r .username)"
DB_PASSWORD="$(echo $DB_CREDS | jq -r .password)"
OPENVPN_USERNAME="$(echo $OPENVPN_CREDS | jq -r .username)"
OPENVPN_PASSWORD="$(echo $OPENVPN_CREDS | jq -r .password)"

cat <<EOF > /usr/local/openvpn_as/tmp/as.conf
# OpenVPN AS configuration file
#
# NOTE:  The ~ symbol used below expands to the directory that
# the configuration file is saved in

# remove for production
# DEBUG=false

# temporary directory
tmp_dir=~/tmp

lic.dir=~/licenses

# run_start retries
run_start_retry.give_up=60
run_start_retry.resample=10

# enable client gateway
sa.show_c2s_routes=true

# certificates database
certs_db=mysql://$DB_USER:$DB_PASSWORD@${DB_HOST}:${DB_PORT}/as_certs

# user properties DB
user_prop_db=mysql://$DB_USER:$DB_PASSWORD@${DB_HOST}:${DB_PORT}/as_userprop

# configuration DB
config_db=mysql://$DB_USER:$DB_PASSWORD@${DB_HOST}:${DB_PORT}/as_config

# Local configuration DB - this must remain a SQLite type database
config_db_local=sqlite:///~/db/config_local.db

# cluster DB
cluster_db=mysql://$DB_USER:$DB_PASSWORD@${DB_HOST}:${DB_PORT}/as_cluster

# notification DB
notification_db=mysql://$DB_USER:$DB_PASSWORD@${DB_HOST}:${DB_PORT}/as_notification

# log DB
# If log_db line is deleted or commented out, logging to DB will be disabled
# Note that disabling logging to DB will not disable logging to file, syslog or stdout.
log_db=sqlite:///~/db/log.db

# wait this many seconds between failed retries
db_retry.interval=1

# how many retries to attempt before failing
db_retry.n_attempts=6

# On startup, wait up to n seconds for DB files to become
# available if they do not yet exist.  This is generally
# only useful on secondary nodes used for standby purposes.
# db_startup_wait=

# Node type: PRIMARY|SECONDARY.  Defaults to PRIMARY.
# node_type=


# User for web service with PAM authentication
boot_pam_service=openvpnas

# System users that are allowed to access the server agent XML API.
# The user that the web server will run as should be in this list.
system_users_local.0=root
system_users_local.1=openvpn_as

# The host name for the openvpn server

host.name=${HOSTNAME}

# The user/group that the web server will run as
cs.user=openvpn_as
cs.group=openvpn_as

# socket directory
general.sock_dir=~/sock

# path to linux openvpn executable
# if undefined, find openvpn on the PATH
#general.openvpn_exe_path=

# source directory for OpenVPN Windows executable
# (Must have been built with MultiFileExtract)
sa.win_exe_dir=~/exe

# The company name will be shown in the UI
# sa.company_name=Access Server

# server agent socket
sa.sock=~/sock/sagent

# If enabled, automatically generate a client configuration
# when a client logs into the site and successfully authenticates
cs.auto_generate=true

# files for web server (PEM format)
cs.ca_bundle=~/web-ssl/ca.crt
cs.priv_key=~/web-ssl/server.key
cs.cert=~/web-ssl/server.crt
# The CA key is only needed when AS should try to
# autorenew the self-signed web certificate
cs.ca_key=~/web-ssl/ca.key

# web server will use three consecutive ports starting at this
# address, for use with the OpenVPN port share feature
cs.dynamic_port_base=870

# which service groups should be started during
# server agent initialization
sa.initial_run_groups.0=web_group
sa.initial_run_groups.1=openvpn_group

# The unit number of this particular AS configuration.
# Normally set to 0.  If you have multiple, independent AS instances
# running on the same machine, each should have a unique unit number.
sa.unit=0

# If true, open up web ports on the firewall using iptables
iptables.web=true

vpn.server.user=openvpn_as
vpn.server.group=openvpn_as
EOF

cat <<EOF > /tmp/client-route.txt
route 10.0.0.0 255.255.255.0 nat_gateway
EOF

cat <<EOF > /tmp/openvpnas-helper.sh

DB_USER="$(echo $DB_CREDS | jq -r .username)"
DB_PASSWORD="$(echo $DB_CREDS | jq -r .password)"
OPENVPN_USERNAME="$(echo $OPENVPN_CREDS | jq -r .username)"
OPENVPN_PASSWORD="$(echo $OPENVPN_CREDS | jq -r .password)"

systemctl stop openvpnas
sleep 10

cp /usr/local/openvpn_as/tmp/as.conf /usr/local/openvpn_as/etc/as.conf
DB_FQND="${DB_HOST}"

for ITEM in certs userprop config log; do
  echo  "...  preparing \$${ITEM} database and config"

  MYSQL_DB_NAME="as_\$${ITEM}"
  LOCAL_DB_NAME="\$${ITEM}"
  LOCAL_DB_FILE="/usr/local/openvpn_as/etc/db/\$${LOCAL_DB_NAME}.db"
  DB_KEY="\$${ITEM}_db"
  DBCVT_ITEM="\$${ITEM}"

  if [ "\$${DBCVT_ITEM}" = "userprop" ]; then
    DBCVT_ITEM="user_prop"
  fi

  #- create MySql DB
  mysql -h \$${DB_FQND} -u \$${DB_USER} -p\$${DB_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS \$${MYSQL_DB_NAME};"

  #- import local DB schema into MySql if no tables exist
  mysql -h \$${DB_FQND} -u \$${DB_USER} -p\$${DB_PASSWORD} --silent --skip-column-names \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '\$${MYSQL_DB_NAME}';" \
  | grep -e ^0 -q \
  && ./usr/local/openvpn_as/scripts/dbcvt -t \$${DBCVT_ITEM} -s sqlite:///\$${LOCAL_DB_FILE} -d mysql://\$${DB_USER}:\$${DB_PASSWORD}@\$${DB_FQND}/\$${MYSQL_DB_NAME}
done

mysql -h \$${DB_FQND} -u \$${DB_USER} -p\$${DB_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS as_cluster;"
mysql -h \$${DB_FQND} -u \$${DB_USER} -p\$${DB_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS as_notification;"

systemctl restart openvpnas
sleep 10
/usr/local/openvpn_as/scripts/sacli --user "\$${OPENVPN_USERNAME}" --key "prop_superuser" --value "true" UserPropPut
/usr/local/openvpn_as/scripts/sacli --user "\$${OPENVPN_USERNAME}" --key "user_auth_type" --value "local" UserPropPut
/usr/local/openvpn_as/scripts/sacli --user "\$${OPENVPN_USERNAME}" --new_pass=\$${OPENVPN_PASSWORD} SetLocalPassword

/usr/local/openvpn_as/scripts/sacli --key "vpn.client.config_text" --value_file=/tmp/client-route.txt ConfigPut

/usr/local/openvpn_as/scripts/sacli start
sleep 10

cluster=\$(/usr/local/openvpn_as/scripts/sacli ClusterQuery)

if [ "\$cluster" == "" ]; then
  /usr/local/openvpn_as/scripts/sacli --mysql_str="mysql://\$${DB_USER}:\$${DB_PASSWORD}@${DB_HOST}:${DB_PORT}" --rr_update_node --rr_dns_new_nodes --rr_dns_hostname=${HOSTNAME} --convert_db --prof Default ClusterNew
else
  /usr/local/openvpn_as/scripts/sacli --mysql_str=mysql://\$${DB_USER}:\$${DB_PASSSWORD}@${DB_HOST}:${DB_PORT}" ClusterJoin
fi

EOF

chmod +x /tmp/openvpnas-helper.sh

cat <<EOF > /lib/systemd/system/openvpnas-helper.service
[Unit]
Description=OpenVPN helper
After=openvpnas.service

[Service]
ExecStartPre=/bin/sleep 30
ExecStart=bash /tmp/openvpnas-helper.sh
StandardOutput=append:/tmp/openvpnas-helper.log
StandardError=append:/tmp/openvpnas-helper.log

[Install]
WantedBy=multi-user.target
EOF

systemctl start openvpnas-helper
systemctl enable openvpnas-helper
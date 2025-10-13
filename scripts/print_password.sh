#! /bin/bash
SECRETS_DIR=$(pwd)/secrets
PASSWORDS_FILE=${SECRETS_DIR}/passwords.txt
. ${PASSWORDS_FILE}

echo  "password elastic= ${ELASTIC_PASSWORD}"
echo  "password kibana= ${KIBANA_PASSWORD}"
echo  "password beats_system= ${BEATS_PASSWORD}"
echo  "password apm_system=  ${BEATS_PASSWORD}"
echo  "password remote_monitoring_user= ${MONITORING_PASSWORD}"
echo  "token fleet= ${FLEET_TOKEN}"
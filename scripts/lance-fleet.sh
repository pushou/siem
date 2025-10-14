#! /bin/bash
# variables
CLUSTER_NAME="HandOnPackets"
PARENT_DIR=$(pwd)
TEMPLATE_DIR=$PARENT_DIR/templates
TEMP_DIR=$PARENT_DIR/temp
CA_FILE=${TEMP_DIR}/ca.crt
SECRETS_DIR=$PARENT_DIR/secrets
CONFIG_DIR=$PARENT_DIR/config
CONFIG_FILEBEAT_DIR=$PARENT_DIR/config.filebeat
PASSWORDS_FILE=${SECRETS_DIR}/passwords.txt
ENV_FILE=$(pwd)/.env
ETC_DIR=$PARENT_DIR/etc
LOGS_DIR=$PARENT_DIR/logs
LIB_SURICATA_DIR=$PARENT_DIR/lib
IP_HOST=$(ip route get 8.8.8.8 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}')
VERSION=9.1.5


#CERTS_DIR=/usr/share/elasticsearch/config/certificates


echo "récupération des mots de passes dans les variables depuis passwords.txt"
source ${PASSWORDS_FILE}
make pass 

echo "TEMP_DIR $TEMP_DIR"
echo "CA_FILE $CA_FILE"
echo "SECRETS_DIR $SECRETS_DIR"
echo "CONFIG_DIR $CONFIG_DIR"
echo "ETC_DIR $ETC_DIR"
echo "LOGS_DIR $LOGS_DIR"
echo "PASSWORDS_FILE $PASSWORDS_FILE"
echo "IP_HOST $IP_HOST"
echo "ELASTIC_PASSWORD ${ELASTIC_PASSWORD}"

# prepare fleet on kibana
curl  --cacert $CA_FILE -k -XPOST https:///${IP_HOST}:5601/api/fleet/setup --header 'kbn-xsrf: true'  -K-  <<< "--user elastic:$ELASTIC_PASSWORD"

# create fleet server polic
curl --cacert $CA_FILE -k  -X POST "https://${IP_HOST}:5601/api/fleet/agent_policies?sys_monitoring=true" --header 'kbn-xsrf: true' --header 'Content-Type: application/json'  --data-raw '{"id":"fleet-server-policy-jmp","name":"Fleet Server policy jmp","description":"","namespace":"default","monitoring_enabled":["logs","metrics"],"has_fleet_server":true}'  -K-  <<< "--user elastic:$ELASTIC_PASSWORD" 

# update fleet server url 
curl --cacert $CA_FILE -k  -XPUT "https://${IP_HOST}:5601/api/fleet/settings" --header 'kbn-xsrf: true' --header 'Content-Type: application/json' --data-raw '{"fleet_server_hosts":["https://${IP_HOST}:8220","https://${IP_HOST}:8220"]}' -K-  <<< "--user elastic:$ELASTIC_PASSWORD"

# Avec la syntaxe -K- qui fonctionne pour vous
FLEET_TOKEN=$(curl -k --cacert $CA_FILE -X POST "https://${IP_HOST}:5601/api/fleet/service_tokens" -H "kbn-xsrf: true" -H "Content-Type: application/json" -K- <<< "--user elastic:$ELASTIC_PASSWORD" | jq -r .value)
echo "FLEET_TOKEN ${FLEET_TOKEN}"
printf "FLEET_TOKEN=%q\n" "${FLEET_TOKEN}" >> "${ENV_FILE}"
printf "FLEET_TOKEN=%q\n" "${FLEET_TOKEN}" >> "${PASSWORDS_FILE}"

echo "lancement de fleet"
#docker run --rm -d --publish=${IP_HOST}:8220:8220  --name fleet --network=elasticsearch --volume='certs:/usr/share/fleet/config/certs'  --env FLEET_SERVER_ENABLE=true --env FLEET_SERVER_ELASTICSEARCH_HOST=https://${IP_HOST}:9200 --env FLEET_SERVER_ELASTICSEARCH_CA=/usr/share/fleet/config/certs/ca/ca.crt --env FLEET_URL=https://${IP_HOST}:8220 --env FLEET_CA=/usr/share/fleet/config/certs/ca/ca.crt --env FLEET_SERVER_CERT=/usr/share/fleet/config/certs/fleet/fleet.crt --env FLEET_SERVER_CERT_KEY=/usr/share/fleet/config/certs/fleet/fleet.key --env CERTIFICATE_AUTHORITIES=/usr/share/fleet/config/certs/ca/ca.crt --env FLEET_SERVER_SERVICE_TOKEN=${FLEET_TOKEN} --env ELASTICSEARCH_USERNAME=elastic --env ELASTICSEARCH_PASSWORD=${ELASTIC_PASSWORD} --env KIBANA_FLEET_SETUP=1 --env KIBANA_HOST=https://${IP_HOST}:5601 --env KIBANA_CA=/usr/share/fleet/config/certs/ca/ca.crt --env KIBANA_USERNAME=elastic --env KIBANA_PASSWORD=${ELASTIC_PASSWORD} --env FLEET_SERVER_POLICY=fleet-server-policy-jmp  docker.elastic.co/beats/elastic-agent:${VERSION}

#docker run --rm -d --publish=${IP_HOST}:8220:8220  --name fleet --network=elasticsearch --volume='certs:/usr/share/fleet/config/certs'  --env FLEET_SERVER_ENABLE=true --env FLEET_SERVER_ELASTICSEARCH_HOST=https://${IP_HOST}:9200 --env FLEET_SERVER_ELASTICSEARCH_CA=/usr/share/fleet/config/certs/ca/ca.crt --env FLEET_URL=https://${IP_HOST}:8220 --env FLEET_CA=/usr/share/fleet/config/certs/ca/ca.crt --env FLEET_SERVER_CERT=/usr/share/fleet/config/certs/fleet/fleet.crt --env FLEET_SERVER_CERT_KEY=/usr/share/fleet/config/certs/fleet/fleet.key --env CERTIFICATE_AUTHORITIES=/usr/share/fleet/config/certs/ca/ca.crt --env FLEET_SERVER_SERVICE_TOKEN=${FLEET_TOKEN}  --env FLEET_SERVER_POLICY=fleet-server-policy-jmp  docker.elastic.co/elastic-agent/elastic-agent:${VERSION}
docker run -d --publish=${IP_HOST}:8220:8220  --name fleet --network=elasticsearch --volume='certs:/usr/share/fleet/config/certs'  --env FLEET_SERVER_ENABLE=true --env FLEET_SERVER_ELASTICSEARCH_HOST=https://${IP_HOST}:9200 --env FLEET_SERVER_ELASTICSEARCH_CA=/usr/share/fleet/config/certs/ca/ca.crt --env FLEET_URL=https://${IP_HOST}:8220 --env FLEET_CA=/usr/share/fleet/config/certs/ca/ca.crt --env FLEET_SERVER_CERT=/usr/share/fleet/config/certs/fleet/fleet.crt --env FLEET_SERVER_CERT_KEY=/usr/share/fleet/config/certs/fleet/fleet.key --env CERTIFICATE_AUTHORITIES=/usr/share/fleet/config/certs/ca/ca.crt --env FLEET_SERVER_SERVICE_TOKEN=${FLEET_TOKEN}  --env FLEET_SERVER_POLICY=fleet-server-policy-jmp  docker.elastic.co/elastic-agent/elastic-agent:${VERSION}

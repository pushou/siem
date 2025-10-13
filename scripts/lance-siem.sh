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
ETC_DIR=$PARENT_DIR/etc
LOGS_DIR=$PARENT_DIR/logs
LIB_SURICATA_DIR=$PARENT_DIR/lib
IP_HOST=$(ip route get 8.8.8.8 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}')
VERSION=9.1.5

echo "TEMP_DIR $TEMP_DIR"
echo "CA_FILE $CA_FILE"
echo "SECRETS_DIR $SECRETS_DIR"
echo "CONFIG_DIR $CONFIG_DIR"
echo "ETC_DIR $ETC_DIR"
echo "LOGS_DIR $LOGS_DIR"
echo "PASSWORDS_FILE $PASSWORDS_FILE"


#CERTS_DIR=/usr/share/elasticsearch/config/certificates

if [[ ! -d "$CONFIG_FILEBEAT_DIR" ]]; then
   mkdir -p $CONFIG_FILEBEAT_DIR
fi



make cleansiem

echo "récupération des mots de passes dans les variables depuis passwords.txt"
source ${PASSWORDS_FILE}
cd .. && make pass && cd -

####################################################################################################
echo "run de l'image suricata (Alma 8 redhat like) voir https://github.com/jasonish/docker-suricata"
####################################################################################################
# recup des interfaces de la machine
SURICATA_OPTIONS=$(find /sys/class/net -mindepth 1 -maxdepth 1 -lname '*virtual*' -prune -o -printf '-i %f ')-vvv
echo "suricata va écouter sur les interfaces $SURICATA_OPTIONS"

docker run  -d --name suricata --env SURICATA_OPTIONS="${SURICATA_OPTIONS}" -e PUID=$(id -u)  -e PGID=$(id -g) \
    -it --net=host \
    --cap-add=net_admin --cap-add=net_raw --cap-add=sys_nice \
    -v ${LOGS_DIR}:/var/log/suricata \
    -v ${ETC_DIR}:/etc/suricata \
    -v ${LIB_SURICATA_DIR}:/var/lib/suricata \
    jasonish/suricata:latest

# Rajout de packages de bases dans l'image

docker exec -it suricata bash -c 'dnf -y update && dnf -y install git vim wget jq less GeoIP-GeoLite-data-extra sudo initscripts'
#on utilise un container filebeat donc pas utile  
#docker exec -it suricata bash -c 'curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.0.0-x86_64.rpm && rpm -vi filebeat-8.0.0-x86_64.rpm'

echo "activation des repos de règles"
docker exec suricata bash -c '
suricata-update list-sources
suricata-update enable-source oisf/trafficid
suricata-update enable-source etnetera/aggressive
suricata-update enable-source sslbl/ssl-fp-blacklist
suricata-update enable-source et/open
suricata-update enable-source tgreen/hunting
suricata-update enable-source sslbl/ja3-fingerprints
suricata-update enable-source ptresearch/attackdetection
suricata-update &
'
###################################################################
echo "création d'une instance de Evebox voir https://evebox.org/ elle va indexer dans ES tout les _index=logstash*"
echo "evebox ne supporte pas les entrées ES provenant de filebeat"
###################################################################
sed "s/ELASTIC_PASSWORD/${ELASTIC_PASSWORD}/g" ${TEMPLATE_DIR}/evebox.yaml.template > ${CONFIG_DIR}/evebox.yaml

docker run --name evebox -d -v ${CONFIG_DIR}/evebox.yaml:/evebox.yaml --net elasticsearch --publish=127.0.0.1:5636:5636 -it jasonish/evebox:latest --config evebox.yaml

###################################################################
echo "lancement de Kibana" 
###################################################################
KIBANA_CONFIG_FILE=${CONFIG_DIR}/kibana.yml
KIBANA_CONFIG_TEMPLATE=${TEMPLATE_DIR}/kibana.yml.template
cp $KIBANA_CONFIG_TEMPLATE $KIBANA_CONFIG_FILE
printf "%s\n" "kibana file:  ${KIBANA_CONFIG_FILE}"

## Pour kibana il faut aussi renseigner le fichier de config avec le nouveau mot de passe
echo "elasticsearch.password: ${KIBANA_PASSWORD}" >> ${KIBANA_CONFIG_FILE}

# supression d'un ^M dans le fichier config de Kibana
sed -i 's/\r//g' ${KIBANA_CONFIG_FILE}


docker run   -d --name kibana --network=elasticsearch --volume='certs:/usr/share/kibana/config/certs' -v ${CONFIG_DIR}:/usr/share/kibana/config --publish=${IP_HOST}:5601:5601 --env ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=/usr/share/kibana/config/certs/ca/ca.crt --env ELASTICSEARCH_HOSTS='https://es01:9200' --env ELASTICSEARCH_USERNAME=kibana_system  docker.elastic.co/kibana/kibana:${VERSION}

#docker run -d \
#        --name kibana \
#	--network=elasticsearch \
#	--mount 'type=volume,source=certs,target=/usr/share/kibana/config/certs' \
#	-v ${CONFIG_DIR}:/usr/share/kibana/config \
#	--publish=0.0.0.0:5601:5601 \
#       	--env ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=/usr/share/kibana/config/certs/ca/ca.crt \
#	--env ELASTICSEARCH_HOSTS='https://es01:9200' \
#       	--env ELASTICSEARCH_USERNAME=kibana_system \
#        --env SERVER_SSL_ENABLED=true \
#        --env SERVER_SSL_KEY==/usr/share/kibana/config/certs/kibana/kibana.key \
#	--env SERVER_SSL_CERTIFICATE=/usr/share/kibana/config/certs/kibana/kibana.crt \
#	--env SERVER_SSL_CERTIFICATEAUTHORITIES=/usr/share/kibana/config/certs/ca/ca.crt \
#       	  docker.elastic.co/kibana/kibana:${VERSION}

echo "Attente Kibana up...";
until curl -k -s -XGET https://${IP_HOST}:5601/status -I 2>&1 | grep -qv "init"; do sleep 10; done;
sleep 60


###################################################################
echo "lancement de logstash" 
###################################################################

# ajout du pass pour logstash.conf
sed "s/ELASTIC_PASSWORD/${ELASTIC_PASSWORD}/g" ${TEMPLATE_DIR}/logstash.conf.template > ${CONFIG_DIR}/pipeline/logstash.conf

sed -i 's/\r//g' ${CONFIG_DIR}/pipeline/logstash.conf



docker run -d --rm --name logstash -e PUID=$(id -u)  -e PGID=$(id -g) --env ELASTIC_USERNAME=logstash_system --env ELASTIC_PASSWORD=${LOGSTASH_PASSWORD}   -e XPACK_MONITORING_ENABLED=false -it --rm --net=elasticsearch  --volume="${LOGS_DIR}:/var/log/suricata" -v${TEMP_DIR}/ca.crt:/usr/share/logstash/config/ca.crt -v ${CONFIG_DIR}/pipeline/:/usr/share/logstash/pipeline/ docker.elastic.co/logstash/logstash:${VERSION} 

#docker cp ${TEMP_DIR}/ca.crt logstash:/usr/share/logstash/config/ca.crt

###################################################################
echo "lancement de filebeats" 
###################################################################

# ajout du pass pour filebeat.yml on copie tel quel le template pour suricata
sudo cp ${TEMPLATE_DIR}/suricata.yml.template ${CONFIG_FILEBEAT_DIR}/suricata.yml 
sudo sed "s/ELASTIC_PASSWORD/${ELASTIC_PASSWORD}/g" ${TEMPLATE_DIR}/filebeat.yml.template > ${CONFIG_FILEBEAT_DIR}/filebeat.yml
sudo sed -i 's/\r//g' ${CONFIG_FILEBEAT_DIR}/filebeat.yml 
sudo chown root.root ${CONFIG_FILEBEAT_DIR}/*.yml 
sudo chmod go-w ${CONFIG_FILEBEAT_DIR}/*.yml

# d'abord setup
docker run --rm --user=root --volume='certs:/usr/share/filebeats/config/certs'  --network=elasticsearch --volume="${CONFIG_FILEBEAT_DIR}/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro" --volume="${CONFIG_FILEBEAT_DIR}/filebeat.yml:/usr/share/filebeat/modules.d/suricata.yml:ro" --volume="${LOGS_DIR}:/var/log/suricata"  --env ELASTIC_USERNAME=beats_system --env ELASTIC_PASSWORD=${BEATS_PASSWORD}  docker.elastic.co/beats/filebeat:${VERSION} filebeat setup -e -strict.perms=false -E setup.kibana.host=kibana:5601 -E output.elasticsearch.hosts="https://es01:9200" -E output.elasticsearch.ssl.certificate_authorities=/usr/share/filebeats/config/certs/ca/ca.crt

# ensuite lancement en scrutation
docker run --rm --user=root  -d --name filebeat  --volume='certs:/usr/share/filebeats/config/certs'  --network=elasticsearch --volume="${CONFIG_FILEBEAT_DIR}/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro" --volume="${CONFIG_FILEBEAT_DIR}/suricata.yml:/usr/share/filebeat/modules.d/suricata.yml:ro" --volume="${LOGS_DIR}:/var/log/suricata" --env ELASTIC_USERNAME=beats_system --env ELASTIC_PASSWORD=${BEATS_PASSWORD}  docker.elastic.co/beats/filebeat:${VERSION} filebeat -e -strict.perms=false -E setup.kibana.host=kibana:5601 -E output.elasticsearch.hosts="https://es01:9200" -E output.elasticsearch.ssl.certificate_authorities=/usr/share/filebeats/config/certs/ca/ca.crt

# activation du module suricata

docker cp "${CONFIG_FILEBEAT_DIR}"/suricata.yml filebeat:/usr/share/filebeat/modules.d/suricata.yml


if [ ! -f apm.lock ]; then
   	
###################################################################
echo "lancement de zeek" 
###################################################################
    docker run -d --rm  --name zeek  --net=elasticsearch --volumes-from=suricata registry.iutbeziers.fr/bro:4.2.0 /bin/bash -c 'while true; do sleep 100; done'
    docker exec -it zeek   /bin/bash -c 'apt update && apt -y install python3 vim cmake build-essential python3-pip git curl wget libpcap-dev && pip3 install GitPython semantic-version'
# Optionnel long à compiler
#docker exec -it zeek   /bin/bash -c 'wget https://github.com/zeek/spicy/releases/download/v1.3.0/spicy_linux_ubuntu20.deb && dpkg -i spicy_linux_ubuntu20.deb'
#docker exec -it zeek   /bin/bash -c 'export PATH=/opt/spicy/bin:$PATH;zkg install --force zeek/spicy-plugin && zeek -N _Zeek::Spicy'
#docker exec -it zeek   /bin/bash -c 'echo "export PATH=/opt/spicy/bin:$PATH" >> /root/.bashrc'

fi


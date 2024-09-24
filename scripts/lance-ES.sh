#! /bin/bash
# test de sudo
if (sudo -vn && sudo -ln) 2>&1 |grep 'ne pas' > /dev/null; then 
  printf "%s\n" "vous devez pouvoir faire sudo"
  exit 0 
fi



# nettoyage
make clean

#creation network et volumes 
docker network create elasticsearch
docker volume create elasticdata
docker volume create elasticonfig
docker volume create certs

# variables 
CLUSTER_NAME="HandOnPackets"
TEMPLATE_DIR=$(pwd)/templates
TEMP_DIR=$(pwd)/temp
CA_FILE=${TEMP_DIR}/ca.crt
SECRETS_DIR=$(pwd)/secrets
CONFIG_DIR=$(pwd)/config
PASSWORDS_FILE=${SECRETS_DIR}/passwords.txt
ENV_FILE=$(pwd)/.env
IP_HOST=$(ip route get 8.8.8.8 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}')
VERSION=8.15.1
CERT_HOST="/usr/local/share/ca-certificates"


#CERTS_DIR=/usr/share/elasticsearch/config/certificates


# création des fichiers sans les mots de passes
# avec la version 8.0 de kibana le mot de passe du compte kibana_system est ignoré en tant que variable d'environnement, il faut 
# mettre le mot de passe généré dans le fichier config/kibana.yml d'ou le besoin d'un template propre

cp ${TEMPLATE_DIR}/env.template "${ENV_FILE}"

if [[ ! -d "$SECRETS_DIR" ]]; then
   mkdir -p $SECRETS_DIR
fi


if [[ ! -d "$TEMP_DIR" ]]; then
   mkdir -p $TEMP_DIR
fi


###############################################################
# ce premier container éphémère crée les certificats auto-signés
# on prend un mot de passe par default qui sera changé ensuite
###############################################################

docker run --rm -it --env IP_HOST=${IP_HOST} --env ELASTIC_PASSWORD=changeme --env KIBANA_PASSWORD=changeme --volume='certs:/usr/share/elasticsearch/config/certs' --user root docker.elastic.co/elasticsearch/elasticsearch:$VERSION  bash -c 'mkdir -p /usr/share/elasticsearch/config/certs/ca;
         if [ x${ELASTIC_PASSWORD} == x ]; then
          echo "Set the ELASTIC_PASSWORD environment variable in the .env file";
          exit 1;
        elif [ x${KIBANA_PASSWORD} == x ]; then
          echo "Set the KIBANA_PASSWORD environment variable in the .env file";
          exit 1;
        fi;
        if [ ! -f certs/ca.zip ]; then
          echo "Creating CA";
          bin/elasticsearch-certutil ca --silent --pem -out config/certs/ca.zip;
          unzip config/certs/ca.zip -d config/certs;
        fi;
        if [ ! -f certs/certs.zip ]; then
          echo "Creating certs";
          echo -ne \
          "instances:\n"\
          "  - name: es01\n"\
          "    dns:\n"\
          "      - es01\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
	  "      - $IP_HOST\n"\
          "  - name: es02\n"\
          "    dns:\n"\
          "      - es02\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
	  "      - $IP_HOST\n"\
          "  - name: es03\n"\
          "    dns:\n"\
          "      - es03\n"\
          "      - localhost\n"\
	  "      - $IP_HOST\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
          "  - name: kibana\n"\
          "    dns:\n"\
          "      - kibana\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
	  "      - $IP_HOST\n"\
          "  - name: fleet\n"\
          "    dns:\n"\
          "      - localhost\n"\
          "    ip:\n"\
          "      - 127.0.0.1\n"\
	  "      - $IP_HOST\n"\
          > config/certs/instances.yml;
          bin/elasticsearch-certutil cert --silent --pem -out config/certs/certs.zip --in config/certs/instances.yml --ca-cert config/certs/ca/ca.crt --ca-key config/certs/ca/ca.key;
          unzip config/certs/certs.zip -d config/certs;
        fi;
	openssl pkcs12 -export -in config/certs/ca/ca.crt -inkey config/certs/ca/ca.key -out certificate.p12  -passin pass: -passout pass:;
        echo "Setting file permissions"
        chown -R root:root config/certs;
        find . -type d -exec chmod 750 \{\} \;;
        find . -type f -exec chmod 640 \{\} \;;
        echo "All done!";exit 0
      '

# création de l'instance es01 avec le volume contenant les certificats précédents 

docker run -d  --name es01 \
--env cluster.name=${CLUSTER_NAME}  \
--env discovery.type=single-node \
--env ELASTIC_PASSWORD=changeme \
--env bootstrap.memory_lock=true \
--env xpack.security.enabled=true \
--env xpack.security.http.ssl.enabled=true \
--env xpack.security.http.ssl.key=/usr/share/elasticsearch/config/certs/es01/es01.key \
--env xpack.security.http.ssl.certificate=/usr/share/elasticsearch/config/certs/es01/es01.crt \
--env xpack.security.http.ssl.certificate_authorities=/usr/share/elasticsearch/config/certs/ca/ca.crt \
--env xpack.security.http.ssl.verification_mode=certificate \
--env xpack.security.transport.ssl.enabled=true \
--env xpack.security.transport.ssl.key=/usr/share/elasticsearch/config/certs/es01/es01.key \
--env xpack.security.transport.ssl.certificate=/usr/share/elasticsearch/config/certs/es01/es01.crt \
--env xpack.security.transport.ssl.certificate_authorities=/usr/share/elasticsearch/config/certs/ca/ca.crt \
--env xpack.security.transport.ssl.verification_mode=certificate \
--env xpack.security.authc.api_key.enabled=true \
--env xpack.license.self_generated.type=basic \
--env xpack.security.enrollment.enabled=false \
--env cluster.routing.allocation.disk.watermark.low="30mb" \
--env cluster.routing.allocation.disk.watermark.high="20mb" \
--env cluster.routing.allocation.disk.watermark.flood_stage="10mb" \
--env cluster.info.update.interval="1m" \
--env ES_JAVA_OPTS="-Xms2048m -Xmx2048m" \
--env ingest.geoip.downloader.enabled=false \
--volume='elasticdata:/usr/share/elasticsearch/data' \
--volume='elasticonfig:/usr/share/elasticsearch/config' \
--volume='certs:/usr/share/elasticsearch/config/certs' \
--publish 127.0.0.1:9200:9200 --publish 127.0.0.1:9300:9300 --publish ${IP_HOST}:9200:9200 --net elasticsearch \
docker.elastic.co/elasticsearch/elasticsearch:$VERSION

# On récupére la CA pour faire des curl avec la CA générée par le container éphémère

echo "${CA_FILE}"
docker cp es01:/usr/share/elasticsearch/config/certs/ca/ca.crt "${CA_FILE}"

# ES met un peu de temps à être accessible
echo "Attente ES up...";
export ELASTIC_PASSWORD='changeme'
until make curlES 2<&1 |grep -q 'You Know, for Search';do sleep 10; done;


printf "génération des password pour les systèmes et sauvegarde dans  (pour docker-compose) et ${PASSWORDS_FILE} (pour docker run)\n"

# Création de tous les mots de passes systèmes standard de ES et récupération pour dans une second temps permettent à la stack elastic et plus 
# de s'y connecter

ELASTIC_PASSWORD=$(docker exec --user root -it es01 bash -c './bin/elasticsearch-reset-password  -u elastic -s -b')
echo  "password elastic ${ELASTIC_PASSWORD}" 
printf "ELASTIC_PASSWORD=%q\n" "${ELASTIC_PASSWORD}" >> "${ENV_FILE}"
printf "ELASTIC_PASSWORD=%q\n" "${ELASTIC_PASSWORD}" >> "${PASSWORDS_FILE}"

## Pour kibana il faut aussi renseigner le fichier de config avec le nouveau mot de passe
KIBANA_PASSWORD=$(docker exec --user root -it es01 bash -c './bin/elasticsearch-reset-password  -u kibana_system -s -b')
echo  "password kibana_system ${KIBANA_PASSWORD}" 
printf  "KIBANA_PASSWORD=%q\n" "${KIBANA_PASSWORD}" >> "${ENV_FILE}"
printf  "KIBANA_PASSWORD=%q\n" "${KIBANA_PASSWORD}" >> "${PASSWORDS_FILE}"

BEATS_PASSWORD=$(docker exec --user root -it es01 bash -c './bin/elasticsearch-reset-password  -u beats_system -s -b')
echo  "password beats ${BEATS_PASSWORD}" 
printf "BEATS_PASSWORD=%q\n" "${BEATS_PASSWORD}" >> "${ENV_FILE}"
printf "BEATS_PASSWORD=%q\n" "${BEATS_PASSWORD}" >> "${PASSWORDS_FILE}"

APM_PASSWORD=$(docker exec --user root -it es01 bash -c './bin/elasticsearch-reset-password  -u apm_system -s -b')
echo  "password apm ${BEATS_PASSWORD}" 
printf "APM_PASSWORD=%q\n" "${APM_PASSWORD}" >> "${ENV_FILE}"
printf "APM_PASSWORD=%q\n" "${APM_PASSWORD}" >> "${PASSWORDS_FILE}"

MONITORING_PASSWORD=$(docker exec --user root -it es01 bash -c './bin/elasticsearch-reset-password  -u remote_monitoring_user -s -b')
echo  "password monitoring ${MONITORING_PASSWORD}" 
printf "MONITORING_PASSWORD=%q\n" "${MONITORING_PASSWORD}" >> "${ENV_FILE}"
printf "MONITORING_PASSWORD=%q\n" "${MONITORING_PASSWORD}" >> "${PASSWORDS_FILE}"
# 
echo "copy du certificat de l'AC sur votre hôte";
sudo cp ${TEMP_DIR}/ca.crt ${CERT_HOST}/ca.crt
sudo update-ca-certificates

echo "test de ES"
make curlES


#sudo chown -R root.root $(pwd)/config

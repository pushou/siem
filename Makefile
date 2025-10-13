# HELP
# This will output the help for each task
# thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
SHELL := /bin/bash

TEMPLATE_DIR:=${PWD}/templates
SCRIPTS_DIR:=${PWD}/scripts
TEMP_DIR=${PWD}/temp
CA_FILE=${TEMP_DIR}/ca.crt
SECRETS_DIR=${PWD}/secrets
CONFIG_DIR=${PWD}/config
CONFIG_FILEBEAT_DIR=${PWD}/config.filebeat
PASSWORDS_FILE=${SECRETS_DIR}/passwords.txt
ENV_FILE=${PWD}/.env
VERSION=8.15.1
IP_HOST=$(shell ip route get 8.8.8.8 | sed -n '/src/{s/.*src *\([^ ]*\).*/\1/p;q}')

CURRENT_UID := $(shell id -u)
CURRENT_GID := $(shell id -g)

export CURRENT_UID
export CURRENT_GID

.DEFAULT_GOAL := help

es:
	${SCRIPTS_DIR}/lance-ES.sh

siem:
	${SCRIPTS_DIR}/lance-siem.sh

fleet:
	${SCRIPTS_DIR}/lance-fleet.sh

post-restart-es:
	@echo "Redémarrage du container Elasticsearch..."
	- docker start es01
	@echo "Attente ES up..."
	@until make curlES 2>&1 | grep -q 'You Know, for Search'; do sleep 5; done
	@echo "Elasticsearch redémarré avec succès!"

post-restart-siem:
	@echo "Redémarrage des containers SIEM..."
	@echo "Redémarrage de suricata..."
	- docker start suricata
	@echo "Mise à jour des règles Suricata..."
	- docker exec suricata bash -c 'suricata-update' &
	@echo "Redémarrage de evebox..."
	- docker start evebox
	@echo "Redémarrage de Kibana..."
	- docker start kibana
	@echo "Attente Kibana up..."
	@until curl -k -s -XGET https://${IP_HOST}:5601/status -I 2>&1 | grep -qv "init"; do sleep 10; done
	@sleep 30
	@echo "Redémarrage de logstash..."
	- docker start logstash
	@echo "Redémarrage de filebeat..."
	- docker start filebeat
	@echo "Copie de la config suricata dans filebeat..."
	- docker cp "${CONFIG_FILEBEAT_DIR}"/suricata.yml filebeat:/usr/share/filebeat/modules.d/suricata.yml
	@echo "Redémarrage de zeek..."
	- docker start zeek
	@echo "Tous les containers SIEM ont été redémarrés avec succès!"

post-restart-fleet:
	@echo "Redémarrage du container Fleet..."
	@echo "Préparation de Fleet sur Kibana..."
	@source ${PASSWORDS_FILE}; \
	curl --cacert ${CA_FILE} -k -XPOST https://${IP_HOST}:5601/api/fleet/setup --header 'kbn-xsrf: true' -K- <<< "--user elastic:$$ELASTIC_PASSWORD"
	@echo "Création de la policy Fleet Server..."
	@source ${PASSWORDS_FILE}; \
	curl --cacert ${CA_FILE} -k -X POST "https://${IP_HOST}:5601/api/fleet/agent_policies?sys_monitoring=true" --header 'kbn-xsrf: true' --header 'Content-Type: application/json' --data-raw '{"id":"fleet-server-policy-jmp","name":"Fleet Server policy jmp","description":"","namespace":"default","monitoring_enabled":["logs","metrics"],"has_fleet_server":true}' -K- <<< "--user elastic:$$ELASTIC_PASSWORD"
	@echo "Mise à jour de l'URL Fleet Server..."
	@source ${PASSWORDS_FILE}; \
	curl --cacert ${CA_FILE} -k -XPUT "https://${IP_HOST}:5601/api/fleet/settings" --header 'kbn-xsrf: true' --header 'Content-Type: application/json' --data-raw '{"fleet_server_hosts":["https://${IP_HOST}:8220","https://${IP_HOST}:8220"]}' -K- <<< "--user elastic:$$ELASTIC_PASSWORD"
	@echo "Redémarrage du container fleet..."
	- docker start fleet
	@echo "Fleet redémarré avec succès!"

help:
	@echo "---------------HELP-----------------"
	@echo "Pour Initialiser un container ES et "
	@echo "renseigner les variables d'authentification"
	@echo "nécessaires à Kibana, beats..."
	@echo "make es"
	@echo "------------------------------------"
	@echo "pour lancer la stack sécu (suricata,"
	@echo "logstash, evebox,filebeat,kibana)"
	@echo "make siem"
	@echo "------------------------------------"
	@echo "pour tout nettoyer (data comprises)"
	@echo "sans demander confirmation"
	@echo "make clean"
	@echo "------------------------------------"
	@echo "make pass pour afficher les users/passwords"
	@echo "------------------------------------"
	@echo "make curlES pour tester elasticsearch"
	@echo "------------------------------------"
	@echo "make fleet pour installer un server fleet"
	@echo "------------------------------------"
	@echo "make fgprint pour afficher le fingerprint de la CA"
	@echo "------------------------------------"
	@echo "make prca  pour afficher la config ca pour fleet"
	@echo "------------------------------------"
	@echo "APRES REDEMARRAGE DE L'HOTE:"
	@echo "make post-restart-es pour redémarrer ES"
	@echo "make post-restart-siem pour redémarrer la stack SIEM"
	@echo "make post-restart-fleet pour redémarrer Fleet"
	@echo "------------------------------------"
	@echo "régénérés après chaque make es"
	@echo "ES https://IP_HOTE:9200"
	@echo "Kibana https://IP_HOTE:5601"
	@echo "EveBox http://localhost:5636"
	@echo "------------------------------------"

curlES:
	- ${SCRIPTS_DIR}/testES.sh

fgprint:
	- ${SCRIPTS_DIR}/getFingerprint.sh

prca:
	- ${SCRIPTS_DIR}/printcrt.sh

clean:
	- docker stop suricata && docker rm suricata
	- docker stop es01 && docker rm es01
	- docker stop kibana && docker rm kibana
	- docker stop logstash && docker rm logstash
	- docker stop evebox && docker rm evebox
	- docker stop filebeat && docker rm filebeat
	- docker stop zeek && docker rm zeek
	- docker stop fleet && docker rm fleet
	- docker network rm elasticsearch
	- docker volume rm elasticdata
	- docker volume rm elasticonfig
	- docker volume rm certs
	- docker system prune -f
	- docker volume prune -f
	- sudo rm -f "${TEMP_DIR}"/*
	- sudo rm -f "${CONFIG_DIR}"/*.yml
	- sudo rm -f "${CONFIG_FILEBEAT_DIR}"/*.yml
	- sudo rm -f "${CONFIG_DIR}"/pipeline/*.yml
	- sudo rm -f ${SECRETS_DIR}/*
	- rm -f ${PWD}/.env
	- sudo chown -R ${CURRENT_UID}:${CURRENT_GID} ${PWD}


cleansiem:
	- docker stop suricata && docker rm suricata
	- docker stop kibana && docker rm kibana
	- docker stop logstash && docker rm logstash
	- docker stop evebox && docker rm evebox
	- docker stop filebeat && docker rm filebeat
	- docker stop zeek && docker rm zeek
	- docker stop fleet && docker rm fleet
	- docker system prune -f
	- sudo rm -f config/kibana.yml
	- sudo rm -f "${CONFIG_DIR}"/*.yml
	- sudo rm -f "${CONFIG_FILEBEAT_DIR}"/*.yml
	- sudo rm -f "${CONFIG_DIR}"/pipeline/*.yml
stop:
	- docker stop suricata
	- docker stop kibana
	- docker stop logstash
	- docker stop evebox
	- docker stop filebeat
	- docker stop zeek

pass: 
	${SCRIPTS_DIR}/print_password.sh

all: clean es siem pass

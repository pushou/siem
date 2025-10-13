# environnement ELK + BEATS + EVEBOX pour l'analyse de pcap

## Avant d'installer

Ce script est à utiliser sur une VM de test !!  **Il met à jour votre CA**
Le docker-compose.yml est non maintenu, merci de ne pas l'utiliser.

## Packets requis

- jq
- docker
- curl
- make
- sed

## Quelle sont les différentes commandes disponibles

Pour le run des containers et de l'aide

```bash
make help
```

## Installation rapide

```bash
make es
# ...attendez que la procédure soit terminée, les autres "containers" en ont besoin pour démarrer
make siem
# ...attendez que la procédure soit terminée
make fleet
```

On peu maintenant se connecter à l'interface web d'elasic depuis l'ip ``https://ip_de_votre_machine:5601/``

L'utilisateur est ``elastic``
Le mot de passe est celui affichée lors de l'installation

## Supprimer les containers

```bash
make clean
```

## Récuperer les mots de passe

```bash
make pass
```

## Composition de la stack

La stack elastic comprend les éléments suivant:

— Une instance d’Elasticsearch: moteur de recherche et de stockage des données qui écoute sur le port
9200 en TLS sur votre hôte.
— Une instance Kibana: interface web pour visualiser les données qui écoute sur le port 5601 en TLS
sur votre hôte.
— Une instance fleet: interface web pour gérer les agents Elastic ou Beats qui écoute sur le port 8220
en TLS sur votre hôte.

L’IPS "Suricata" est aussi installé sous forme de container et va suivre les flux réseaux de votre machine hôte. Les alertes "Suricata" sont envoyées à Elasticsearch et sont visualisables via Kibana

## Pour rendre accessible les pcaps aux containers les mettre dans ./logs/pcaps

Le container suricata analyse les pcaps et alimente le fichier eve.json:

```bash
docker exec -it suricata bash -c '/var/log/suricata/suri-ingest-pcap.sh /var/log/suricata/pcaps/HandsOn/sensor_data/securityonion-eth1/dailylogs/2015-03-12/snort.log.1426118407'
```

eve.json est automatiquement lu par le container filebeat et alimente Elastic-search avec le tag filebeats-verionfilebeat-année-mois-jour-XXX
eve.json est aussi lu par le container logstash et alimente EveBox (on duplique les enregistrements mais EveBox n'arrive pas à lire les entrées générées par filebeat.)
vous pouvez créez vos propres  règles suricata dans
/var/lib/suricata/rules/local.rules= ./lib/rules/local.rules de votre dir


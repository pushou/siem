# environnement ELK + BEATS + EVEBOX pour l'analyse de pcap
faire 
```
##Pour le run des containers et de l'aide
```
make help
```

## Pour rendre accessible les pcaps aux containers les mettre dans ./logs/pcaps
Le container suricata analyse les pcaps et alimente le fichier eve.json:
```
docker exec -it suricata bash -c '/var/log/suricata/suri-ingest-pcap.sh /var/log/suricata/pcaps/HandsOn/sensor_data/securityonion-eth1/dailylogs/2015-03-12/snort.log.1426118407'
```
eve.json est automatiquement lu par le container filebeat et alimente Elastic-search avec le tag filebeats-verionfilebeat-année-mois-jour-XXX
eve.json est aussi lu par le container logstash et alimente EveBox (on  duplique
les enregistrements mais EveBox n'arrive pas à lire les entrées générées par
filebeat.
vous pouvez créez vos propres  règles suricata dans
/var/lib/suricata/rules/local.rules= ./lib/rules/local.rules de votre dir

Ce script est à utiliser sur une VM de test !!  il met à jour votre CA


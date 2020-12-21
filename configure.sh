#!/bin/sh
# use this script to configure elasticsearch and kibana

if [[ $# -eq 0 ]] ; then
  echo "Please pass in the host computer's ip address"
  exit 1
fi

cat >> /usr/local/etc/elasticsearch/elasticsearch.yml << EOF
network.bind_host: $1
http.port: 9200

transport.host: localhost
transport.tcp.port: 9300
EOF

cat >> /usr/local/etc/kibana/kibana.yml << EOF
elasticsearch.hosts: ["http://$1:9200"]
EOF

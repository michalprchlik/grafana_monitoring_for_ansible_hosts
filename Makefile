install: 
	-docker network create influxdb
	docker pull grafana/grafana
	docker pull influxdb
	mkdir -p grafana/cert
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout grafana/cert/grafana.key -out grafana/cert/grafana.crt

influxdb-run:
	docker run \
	--name influxdb \
	--net=influxdb \
	--privileged \
	--restart always \
	-d \
	-p "8083:8083" \
	-p "8086:8086" \
	-v "${PWD}/influxdb:/var/lib/influxdb" \
	influxdb

grafana-run:
	-chmod 777 ${PWD}/grafana
	-chmod 777 ${PWD}/grafana/grafana.db
	-docker rm -f grafana
	docker run \
	--name grafana \
	--net=influxdb \
	--privileged \
	--restart always \
	-d \
	-e GF_SERVER_PROTOCOL=https \
	-e GF_SERVER_CERT_FILE=/var/lib/grafana/cert/grafana.crt \
    -e GF_SERVER_CERT_KEY=/var/lib/grafana/cert/grafana.key \
	-p "3000:3000" \
	-v "${PWD}/grafana:/var/lib/grafana" \
    grafana/grafana 

grafana-bash:
	docker exec -it grafana bash

influxdb-bash:
	docker exec -it influxdb bash

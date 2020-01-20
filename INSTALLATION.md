# Installation overview

You should choose one of your server as grafana server. For monitoring small infrastructure (max 100 computers) the grafana server can be shared by other services. Monitoring of bigger infrastructure (more than 100) requires dedicated server.

Quick steps:
- install `docker`
- pull this repository
- create self-signed grafana certificates
- start docker containers with grafana and influxdb
- create influxdb user and influxdb database with `curl` on docker influxdb container
- open ports `3000` and `8086` on grafana server 
- update `scanner\config.json` with `influxdb` IP address

## Installation grafana and influxdb

Docker installation

```
# Optional: enable extra RHEL repository to be able to install docker to RHEL servers (not needed on RHEL workstations)
subscription-manager repos --enable=rhel-7-server-extras-rpms

# install docker
yum install -y docker.x86_64 
service docker start

# create docker group, add there user $USER. $USER will not need to write "sudo" in front of docker commands
# replace $USER with your function ID username
groupadd docker
usermod -a -G docker $USER
```

Start services and initial setup of services

```
# git pull this repository 

# one time action to prepare enviroment
# create self-signed grafana certificates and docker network
make install

# start docker containers
make grafana-run
make influxdb-run

# create user "chronothan" with password "supersecret". Influxdb database "monitoring" is also created
# this connection is already prepared in grafana
curl -XPOST "http://localhost:8086/query" --data-urlencode "q=CREATE USER chronothan WITH PASSWORD 'supersecret' WITH ALL PRIVILEGES"
curl -XPOST "http://localhost:8086/query" -u chronothan:supersecret --data-urlencode "q=CREATE DATABASE monitoring"
```

Grafana server ports:
- grafana port `3000` will be used in web browser by users. e.g. `https://localhost:3000`
- influxdb port `8086` will be used by scanners to send data to influxdb

Example commands to open above ports on `RHEL 7` with `iptables`

```
# open ports
iptables -A INPUT -p tcp -m tcp --sport 3000 -j ACCEPT
iptables -A OUTPUT -p tcp -m tcp --dport 3000 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --sport 8086 -j ACCEPT
iptables -A OUTPUT -p tcp -m tcp --dport 8086 -j ACCEPT
service iptables save
service iptables restart
```

## Scanner configuration 

Scanner `scanner\scanner.sh` configuration can be found in `scanner\config.json`. Format of the file is [JSON](https://www.json.org/) format. Scanner will read configuration before every scan with `jq` utility. More values can be added here. 

Configuration options:
- `influx_url` - URL to influxdb. Network connection is needed from monitored server to influxdb. **Change this value to grafana server IP address**
- `scanner.is_linux_monitoring_enabled` - enable/disable monitoring of linux machine health as an example of JSON array value

Example `scanner\config.json` with influxdb running on IP address `1.1.1.1`, on standard port `8086`. The link should be `http://1.1.1.1:8086/write?db=monitoring`. 

```
{
	"influx_url" : "http://1.1.1.1:8086/write?db=monitoring",
	"scanner": 
	{
		"is_linux_monitoring_enabled": "1"
	}
}
```

## End

Installation and configuration is finished now. You can test grafana on `https://localhost:3000`. User `admin` with password `admin`. It should be loaded without data with dashboard settings. To populate dashboards with data, scanners need to be deployed to `ansible hosts` with `ansible playbooks`. Those steps are described in [README.md](README.md) in section "Ansible playbooks". The end.

## Troubleshooting

Pull docker images without internet access (e.g. your grafana server is behind firewall)

```
# error
# on grafana server 
docker pull grafana/grafana
> Using default tag: latest
> Trying to pull repository registry.access.redhat.com/grafana/grafana ... 
> Trying to pull repository docker.io/grafana/grafana ... 
> Get https://registry-1.docker.io/v2/: net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)

# solution
# on another computer (with internet access) download image and save it as file to `/tmp/grafana.docker`
docker pull grafana/grafana
docker save -o /tmp/grafana.docker grafana/grafana:latest

# upload it to grafana server to`/tmp/grafana.docker` and import the images to docker
docker load -i /tmp/grafana.docker
```

Docker network error

```
# error
make create-network
> Error response from daemon: Failed to Setup IP tables: Unable to enable SKIP DNAT rule

# solution
sudo service docker restart
```

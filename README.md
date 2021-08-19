# Grafana monitoring for ansible hosts

The purpose of the project is to provide **automated and clean monitoring of linux servers**. It can be used by smaller teams responsible for linux infrastructure (e.g. application support teams). 

Project contains dockerized `grafana` server with `influxdb` and `ansible playbooks` for manipulating `linux scanners` on `ansible hosts`. The project is able to scan `different linux distributions`.

## Overview

Overview of the project:
- one time installation and configuration
- `grafana` and `influxdb` in docker
- operation and usage of scanners is prepared in `ansible playbooks`
- scanned computers are automatically registered/displayed in `grafana` without any additional configuration
- semaphore approach helps to visualise issues on monitored servers (red = error, orange = warning, green = ok)
- you can add scanning of your own values by changing `scanner\scanner.sh`
- you can pass new configuration in [JSON](https://www.json.org/) format to scanner in `scanner\config.json`
- basic [capacity management](https://en.wikipedia.org/wiki/Capacity_management) monitoring to be more compliant with [ITIL](https://en.wikipedia.org/wiki/ITIL)   
- computers are scanned for 11 different values (password expiration, disk usage, memory usage, etc.) 

`Grafana` is configured with 3 dashboards (links in list below are links to pictures of dashboards):
- dashboard with [list of all servers](images/server_overview.png) to **highlight issues** in server infrastructure (e.g. password on server XY will expire in 5 days)
- every server have dashboard with [server detail](images/server_detail.png)
- dashboard with [one year overview of infrastructure](images/server_big_picture.png) so you can check infrastructure workload in longer period

Monitoring is supported on linux OS:
- `RHEL 7`
- `RHEL 8` (not tested)
- `CentOS 7`
- `CentOS 8`
- `Fedora 31`
- `Ubuntu 16`
- `Oracle linux 7`
- `openSUSE 15`

## Installation & configuration

Detailed installation instructions, installation troubleshooting and configuration of `grafana server` can be found in [INSTALLATION.md](INSTALLATION.md).  

Installation of required packages and scanners to `ansible hosts` is done by `ansible playbooks` (see below)

## Ansible playbooks

All ansible playbooks are in `ansible\` directory. Commands below are executed with inventory file `hosts` with connections to `ansible hosts`.

```
# install all required packages `jq`, `bc` and `sysstat`
ansible-playbook -i hosts install_packages.yml

# create remote directory `scanner`, copy files `scanner\scanner.sh` and `scanner\config.json` to the directory. 
# set up crontab job to execute the script every 5 minutes
ansible-playbook -i hosts install_scanner_to_cron.yml

# create remote directory `scanner`, copy files `scanner\scanner.sh` and `scanner\config.json` to the directory.
# execute remote script `scanner\scanner.sh` immediatelly. 
ansible-playbook -i hosts scan_now.yml

# remove scanner files and directory
# remove crontab job if it is present
ansible-playbook -i hosts remove_scanner.yml
```

## Operation & troubleshooting

```
# start docker container with influxdb and grafana
make influxdb-run
make grafana-run

# deploy new version of scanners to all servers. Setup execution of the script in crontab job
cd ansible
ansible-playbook -i hosts install_scanner_to_cron.yml

# usual troubleshooting is restarting of docker
sudo service docker restart

# log files of docker containers on grafana server
docker logs grafana
docker logs influxdb

# log files of scanner on monitored servers (ansible hosts)
tail -50 /tmp/scanner.log
```


## User access & security

User access to grafana server running on `https://localhost:3000`. You should change the password of `admin`. You can also connect `grafana` with `LDAP` for managing user accesses.

```
username = admin
password = admin
```

User access to influxdb curl queries (e.g. database creation query - `curl -XPOST "http://localhost:8086/query" -u chronothan:supersecret --data-urlencode "q=CREATE DATABASE monitoring"`)

```
username = chronothan
password = supersecret
```

Self-signed certificates created with `make install` should be replaced by trusted ones to prevent not secured https connection warnings in web browser. 

```
grafana\
  cert\             - certificates created by "make install". Used by grafana 
    grafana.key
    grafana.crt 
```

## Scanner

Scanning is done by `scanner\scanner.sh`. It is linux shell script using `/bin/bash`. It requires packages `bc`, `jq` and `sysstat`. To install required packages run `ansible playbook`.  

The scanner reads output of standard linux commands and files. Usually the `grep` with regular expression is involved. The value is than send to `influxdb` to IP address configured in `scanner\config.json`.

The script is able to scan for linux values:  
- CPU, swap and memory usage
- mount usage with mount names. Inodes on mounts 
- hostname, OS version, architecture
- user password expiration
- uptime of computer and zombie processes

Check the source code, in case of interest.

## Directory structure

```
ansible\
  *.yml             - various ansible playbooks
                      see section "Ansible playbooks" in this document for more information 
scanner\
  config.json       - configuration file for scanner. You can add more values and read them in scanner.sh
                      see "INSTALLATION.md" for more information
  scanner.sh        - scanner for scanning linux health. The data is send to influxdb to IP address in config.json
                      see "Scanner" section of this document for more information
grafana\
  cert\             - self-signed certificates for https created by "make install". Can be replaced with trusted ones  
    grafana.key
    grafana.crt
  plugins\          - empty directory created on runtime
  png\              - empty directory created on runtime
  grafana.db        - binary file containing settings of grafana server
influxdb\           - binary files with data from influxdb. The directory is is created at runtime
                      directory is empty in this repository to prevent conflicts when git pulling
.gitignore          - what is inside of this file is not part of this project
Makefile            - everything you need to work with this project
README.md           - if you can read this sentence, README.md is your current file :) 
```

## Update to new version

Any changes done in `grafana dashboards` need to be discarted (generates git conflict). Currently, there is no support for any customisation of dashboards.

Your data in `influxdb database` is not replaced/removed during update

If you want to change something you should consider contributing to this project or fork/clone the repository. 

Example commands to update:

```
git pull
make grafana-run
cd ansible
ansible-playbook -i hosts install_scanner_to_cron.yml
```
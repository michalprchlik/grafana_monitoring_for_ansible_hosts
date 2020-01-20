#!/bin/bash
#===============================================================================
#       AUTHOR: michal.prchlik@cz.ibm.com
#  DESCRIPTION: Scanning script for server monitoring
#               scanned data is send to influxdb to IP address in config.json
#               config.json file must be in same on the scanner's location. 
# REQUIREMENTS: jq, sysstat, bc 
#        USAGE: ./scanner.sh
#      VERSION: 1.00
#===========================================================================================================

cd "$(dirname "$0")"

hostname=`hostname --short`
filename_config="config.json"

if [ -e ${filename_config} ]; then
	influx_url="$( jq -r '.influx_url' ${filename_config} )"

	# example, how to read json array values from config.json
	scanner_is_linux_monitoring_enabled="$( jq -r '.scanner.is_linux_monitoring_enabled' ${filename_config} )"
else
	echo "config file ${filename_config} does not exists. "
	exit 1
fi

function send_to_influx(){
	tag=$1	
	value_to_send=$2
	echo "${tag}=${value_to_send}"	
	curl --silent --connect-timeout 10 --max-time 10 -XPOST "${influx_url}" --data-binary "tag=${tag},hostname=${hostname} value=${value_to_send}"
}

function linux_hostname(){
	value=${hostname}
	value="\"${value}\""	
	send_to_influx "linux_hostname" ${value}
}

function linux_disk_mount(){
	if [ ${scanner_is_linux_monitoring_enabled} == 1 ]; then
		array=( $(df -Pl --exclude=tmpfs --exclude=vfat --exclude=squashfs  | awk {'print $1'}) )
		#remove header row
		unset array[0]
		for mount_name in "${array[@]}"
		do
			value=`df -Pl --exclude=tmpfs --exclude=vfat  --exclude=squashfs | grep ${mount_name} | head -1 | awk {'print $5'} | sed 's/[^0-9]*//g'`
			echo "linux_disk_mount ${mount_name}=${value}"
			curl --silent --connect-timeout 10 --max-time 10 -XPOST "${influx_url}" --data-binary "tag=linux_disk_mount,mount_name=${mount_name},hostname=${hostname} value=${value}"
		done
	fi
}

function linux_disk_inode(){
	if [ ${scanner_is_linux_monitoring_enabled} == 1 ]; then
		array=( $(df -iPl --exclude=tmpfs --exclude=vfat | awk {'print $1'}) )
		#remove header row
		unset array[0]
		for mount_name in "${array[@]}"
		do
			value=`df -iPl --exclude=tmpfs | grep ${mount_name} | head -1 | awk {'print $4'} | sed 's/[^0-9]*//g'`
			echo "linux_disk_inode ${mount_name}=${value}"
			curl --silent --connect-timeout 10 --max-time 10 -XPOST "${influx_url}" --data-binary "tag=linux_disk_inode,mount_name=${mount_name},hostname=${hostname} value=${value}"
		done
	fi
}

function linux_memory(){
	if [ ${scanner_is_linux_monitoring_enabled} == 1 ]; then
		value=`cat /proc/meminfo | grep MemTotal | sed 's/[^0-9]*//g'`
		send_to_influx "linux_memory_total" ${value}
		
		value=`cat /proc/meminfo | grep MemAvailable | sed 's/[^0-9]*//g'`
		send_to_influx "linux_memory_avaliable" ${value}
		
		value=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2 }')
		send_to_influx "linux_memory_percent" ${value}
	fi
}

function linux_swap(){
	if [ ${scanner_is_linux_monitoring_enabled} == 1 ]; then
		value=$(sar 1 1 -S | tail -n 1 | awk {'print $4'} | sed 's/,/./')
		send_to_influx "linux_swap_percent" ${value}
	fi
}

function linux_cpu(){
	if [ ${scanner_is_linux_monitoring_enabled} == 1 ]; then
		#value=$(top -bn1 | grep load | awk '{printf "%.2f", $(NF-2)}')
		value=$(sar 1 1 -u | tail -n 1 | awk {'print $8'} | sed 's/,/./')
		#previous command returned idle%. Convert it to cpu load %
		value=`echo "100 - ${value}" | bc -l`
		send_to_influx "linux_cpu_percent" ${value}
	fi
}

function linux_version(){
	if [ ${scanner_is_linux_monitoring_enabled} == 1 ]; then
		#example - PRETTY_NAME="CentOS Linux 7 (Core)" -> CentOS Linux 7 (Core)
		value=`cat /etc/os-release | grep -i PRETTY | sed 's/"//g' | sed 's/PRETTY_NAME=//' | sed 's/ /\\ /g'`
		value="\"${value}\""
		send_to_influx "linux_version" "${value}"
	fi
}

function linux_zombie_process(){
	if [ ${scanner_is_linux_monitoring_enabled} == 1 ]; then
		#find out the count of zombie processes on the machine
		value=`ps aux | awk {'print $8'} | grep -c Z`
		send_to_influx "linux_zombie_process" ${value}
	fi
}

function linux_uptime(){
	if [ ${scanner_is_linux_monitoring_enabled} == 1 ]; then
		#example - 12:36:31 up 5 days, 21:50,  2 users,  load average: 0.36, 0.29, 0.39 -> 5
		#        - 10:36:20 up  3:24,  1 user,  load average: 77.46, 18.36, 6.11        -> empty -> 0
		value=`uptime | grep days | sed "s/.*up \(.*\) days.*/\\1/g"`
		if [ -z "${value}" ]; then
			value=0
		fi
		send_to_influx "linux_uptime" ${value}
	fi
}

function linux_architecture(){
	if [ ${scanner_is_linux_monitoring_enabled} == 1 ]; then
		#example - 64
		value=`uname -m`
		value="\"${value}\""
		send_to_influx "linux_architecture" "${value}"
	fi
}

function linux_user_password_expiration {
	# Feb 12, 2019 
	# or never
	user=$(whoami)
	value=`sudo chage -l ${user} | grep "Password expires" | sed -r "s/Password expires.*: (.*)/\1/"`
	if [ "${value}" == "never" ]; then
		value=999
	else
		#Feb 12, 2019 -> 1549926000
		value=`date --date "${value}" "+%s"`
		
		# calculate days to change the password
		timestamp_current=$(date +%s)
		value=`echo "${value} - ${timestamp_current}" | bc -l`
		value=$(($value / 86400))
	fi	
	
	send_to_influx "linux_user_password_expiration" ${value}
}

function scanner_report(){
	hostname=${hostname}
	filename=$(basename $0)
	location=$(pwd)/$(basename $0)
	username=$(whoami)

	last_modification_time=$(stat -c "%Y" $0)	
	#grafana's timestamp needs to be 1000x bigger
	last_modification_time=$(($last_modification_time * 1000))
	
	echo "tag=scanner,hostname=${hostname},filename=${filename},location=${location},username=${username},last_modification_time=${last_modification_time} value=1"
	curl --silent --connect-timeout 10 --max-time 10 -XPOST "${influx_url}" --data-binary "tag=scanner,hostname=${hostname},location=${location},filename=${filename},username=${username},last_modification_time=${last_modification_time} value=1"
}

#linux part
linux_hostname
linux_disk_mount
linux_disk_inode
linux_memory
linux_swap
linux_cpu
linux_version
linux_zombie_process
linux_uptime
linux_architecture
linux_user_password_expiration

scanner_report

echo "END script"

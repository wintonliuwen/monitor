#!/bin/bash

server=""

DEPENDS="hdparm lsb_release df iostat netstat ifstat"

uuid=""
cpumodel=""
cpunum=""
cpufreq=""
cpucache=""

memsize=""

diskmodel=""
disksize=""
disksn=""
diskbuffer=0
diskspeed=""

osver=""
oskernel=""
hostname=""

ethname=""
ipaddr=""
macaddr=""



usage()
{
	echo "Usage: nms <server>"
	exit 0;
}

checktools()
{
	local i=0
	for tool in ${DEPENDS}
	do
		path=$(which ${tool})
		if [ -z "$path" ];then
			echo "Please install the tool ${tool}"
			let "i+=1"
		fi
	done

	if [ "$i" -gt 0 ];then
		exit 0
	fi
}

getcpuinfo(){
	cpumodel=$(cat /proc/cpuinfo | grep 'model name' | head -1 | awk -F':' '{print $2}' | awk -F'@' '{print $1}')
	cpunum=$(cat /proc/cpuinfo | grep processor | wc -l)
	cpufreq=$(cat /proc/cpuinfo | grep 'model name' | head -1 | awk -F':' '{print $2}' | awk -F'@' '{print $2}' | sed -e 's/GHz//g')
	cpucache=$(cat /proc/cpuinfo  | grep "cache size" | head -1 | awk -F':' '{print $2}' | sed -e 's/KB//g')
}

getmeminfo(){
    local ramsize=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')
    local ramMb=$((ramsize/1000))
	local ram512=$((($ramMb+511)/512))
	memsize=$((ram512*512))
}

getdiskinfo(){
	local diskname=$(ls /dev | grep sd | head -1)
	local diskdevice="/dev/${diskname}"
	local diskbufkb=$(hdparm -I ${diskdevice} | grep "cache\/buffer" | awk '{print $4}')
	disksn=$(hdparm -I ${diskdevice} | grep "Serial Number" | awk '{print $3}')
	diskmodel=$(hdparm -I ${diskdevice} | grep "Model Number" | awk -F":" '{print $2}')
	disksize=$(hdparm -I ${diskdevice} | grep "1000\*1000" | awk -F"(" '{print $2}' | awk '{print $1}')
	diskspeed=$(hdparm -I ${diskdevice} | grep "Rotation Rate" | awk -F":" '{print $2}')
	diskbuffer=$((diskbufkb/1024))
}

getosinfo(){
	osver=$(lsb_release -d | awk -F":" '{print $2}' | sed 's/\t//g')
	oskernel=$(uname -r | awk -F'-' '{print $1}')
	hostname=$(hostname)
}

getnetwork(){
	ethname=$(route -n | grep "^0.0.0.0" | head -1 | awk -F" " '{print $8}')
	ipaddr=$(ifconfig ${ethname} | sed -n 2p | awk '{print $2}' | tr -d 'addr:')
	macaddr=$(ifconfig ${ethname}  | sed -n 1p | awk '{print $5}')
}


getrtcpu(){
	local cpuusage=0
	local used=$(ps -eo pcpu,pid,user,args | sort -k 1 -r | head -4 | sed 1d | awk '{print $1}')
	local top3=$(ps -eo pcpu,pid,user,args | sort -k 1 -r | head -4 | sed 1d | awk '{print $4}')
	echo "\"cpuusage\":{"
	echo "\"top\":["
	for((i=1; i<=3; i++))
	do
		processi=$(echo ${top3} | cut -d ' ' -f $i)
		cpuusedi=$(echo ${used} | cut -d ' ' -f $i)
		cpuusage=$(echo "${cpuusage}+${cpuusedi}" | bc)
		echo "{"
		echo "\"processname\":\"${processi}\","
		echo "\"percent\":${cpuusedi}"
		echo "}"
		if [ "$i" -ne 3 ];then
			echo ","
		fi
	done
	echo "],"
	echo "\"totalusage\":${cpuusage}"
	echo "},"
}

getrtmem(){
	local usedkb=$(free | sed  -n 2p | awk '{print $3}')
	local freekb=$(free | sed  -n 2p | awk '{print $4}')
	local usedMb=$((usedkb/1024))
	local freeMb=$((freekb/1024))
	local memusage=0
	local memtop3=$(ps aux | sort -k 4 -r | head -4 | sed 1d | awk '{print $11}')
	local used=$(ps aux | sort -k 4 -r | head -4 | sed 1d  | awk '{print $4}')

	echo "\"memusage\":{"
	echo "\"top\":["
	for ((i=1; i<=3; i++))
	do
		taski=$(echo ${memtop3} | cut -d ' ' -f $i)
		memusedi=$(echo ${used} | cut -d ' ' -f $i)
		memusage=$(echo "${memusage}+${memusedi}" | bc)
		echo "{"
		echo "\"processname\":\"${taski}\","
		echo "\"percent\":${memusedi}"
		echo "}"
		if [ "$i" -ne 3 ];then
			echo ","
		fi
	done
	echo "],"
	echo "\"totalusage\":${memusage}"
	echo "},"
}

getrtdisk(){
	local partnum=$(df -m | grep "^\/dev" | wc -l)
	echo "\"diskusage\":["
	for((i=1; i<=$partnum; i++))
	do
		mountpoint=$(df -m | grep "^\/dev/" | sed -n ${i}p | awk '{print $6}')
		used=$(df -m | grep "^\/dev/" | sed -n ${i}p | awk '{print $3}')
		freesize=$(df -m | grep "^\/dev/" | sed -n ${i}p | awk '{print $4}')
		echo "{"
		echo "\"mountpoint\":\"${mountpoint}\","
		echo "\"used\":${used},"
		echo "\"free\":${freesize}"
		echo "}"
		if [ "$i" -ne "$partnum" ];then
			echo ","
		fi
	done
	echo "],"
	readspeed=$(iostat  | grep sda | awk '{print $3}')
	writespeed=$(iostat  | grep sda | awk '{print $4}')
#	echo "readspeed:${readspeed}  writespeed:${writespeed}"
}

getrtnet(){
	local tcpconnected=$(netstat -atn | grep "ESTABLISHED" | wc -l)
	local tcplisten=$(netstat -atn | grep "LISTEN" | wc -l)
	local tcpwait=$(netstat -atn | grep "TIME_WAIT" | wc -l)
	local tcpclosewait=$(netstat -atn | grep "CLOSE_WAIT" | wc -l)
	local downspeed=$(ifstat -i ${ethname} 0.5 1| sed -n 3p | awk '{print $1}')
	local upspeed=$(ifstat -i ${ethname} 0.5 1 | sed -n 3p | awk '{print $2}')
	echo "\"network\":{"
	echo "\"connected\":${tcpconnected},"
	echo "\"listenning\":${tcplisten},"
	echo "\"timewait\":${tcpwait},"
	echo "\"closewait\":${tcpclosewait},"
	echo "\"downspeed\":${downspeed},"
	echo "\"upspeed\":${upspeed}"
	echo }
}

getuuid()
{
	getnetwork
	getdiskinfo
	mac=$(echo ${macaddr} | sed 's/://g')
	uuid=${mac}${disksn}
}

getuuid
#echo "****************Static System Info**************"
#echo "####CPU Info#######"
getcpuinfo
#echo "cpu: ${cpumodel}"
#echo "cpunum: ${cpunum}"
#echo "cpu freq:${cpufreq}"
#echo "cpu cache:${cpucache}"
#echo ""

#echo "####Memory Info#####"
getmeminfo
#echo "Memory size:${memsize}MB"
#echo ""

#echo "####Harddisk Info###"
getdiskinfo
#echo "disk model:${diskmodel}"
#echo "disk size: ${disksize}GB"
#echo "disk speed: ${diskspeed}"
#echo "disk buffer: ${diskbuffer}MB"
#echo ""

#echo "####System####"
getosinfo
#echo "Operating System:\"${osver}\""
#echo "Kernel Version: ${oskernel}"
#echo "Host name: ${hostname}"
#echo ""

#echo "####Network####"
getnetwork
#echo "ethname:${ethname} ip:${ipaddr} mac:${macaddr}"
#echo ""

#echo "**************Real time Info************"
#echo "####CPU####"
#getrtcpu
#echo ""

#echo "####Memory######"
#getrtmem
#echo ""

#echo "####disk######"
#getrtdisk
#echo ""

#echo "###Network####"
#getrtnet
#echo ""


staticjson(){
	echo "{"
	echo "\"uuid\":\"${uuid}\","
	echo "\"cpu\":{"
	echo "\"cpumodel\":\"${cpumodel}\","
	echo "\"cpunum\":${cpunum},"
	echo "\"cpufreq\":${cpufreq},"
	echo "\"cpucache\":${cpucache}"
	echo "},"
	
	echo "\"mem\":${memsize},"
	echo "\"disk\":{"
	echo "\"diskmodel\":\"${diskmodel}\","
	echo "\"disksize\":${disksize},"
	echo "\"diskspeed\":${diskspeed},"
	echo "\"diskcache\":${diskbuffer}"
	echo "},"
	
	echo "\"system\":{"
	echo "\"hostname\":\"${hostname}\","
	echo "\"osver\":\"${osver}\","
	echo "\"kernel\":\"${oskernel}\""
	echo "},"
	
	echo "\"network\":{"
	echo "\"ethname\":\"${ethname}\","
	echo "\"ipaddr\":\"${ipaddr}\","
	echo "\"macaddr\":\"${macaddr}\""
	echo "}"
	echo "}"
}

dynamicjson(){
	echo "{"
	echo "\"uuid\":\"${uuid}\","
	getrtcpu
	getrtmem
	getrtdisk
	getrtnet	
	echo "}"
}


if [ $# -ne 1 ];then
	usage
else
	serverip=$1
fi

checktools

staticjson=$(staticjson)
curl  -X POST -H 'Content-Type:application/json' -d "${staticjson}" http://${serverip}:8080/nms/poststatics

while true
do
dyjson=$(dynamicjson)
curl  -X POST -H 'Content-Type:application/json'  -d "${dyjson}"  http://${serverip}:8080/nms/postdrynamic
sleep 60
done


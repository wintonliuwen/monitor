#!/bin/sh

RESULTPATH="/tmp/monitoring"
FUNCTIONS=""

main_loop(){

	for i in ${FUNCTIONS}
	do
		${i} >> ${RESULTPATH}
	done

}

# print the results
print_result(){
	echo "$(date "+%Y%m%d %H:%M:%S") $1"
}

# memory parts
processmem(){
	local result=""
	pid=$(pidof "$1")
	if [ -n "$pid" ];then
		result="$(echo $(cat /proc/${pid}/status | grep VmSize | awk -F':' '{print $2}'))"
	else
		result="No such process:$1"
	fi
	print_result "${result}"
}

# CPU parts
processcpu(){
	local totalcpu=""
	local processcpu=0
	local result=0
	pid=$(pidof "$1")
	if [ -n "$pid" ];then
		totalcpu=$(cat /proc/stat|grep "cpu "|awk '{for(i=2;i<=NF;i++)j+=$i;print j;}')
		processcpu=$(cat /proc/${pid}/stat | awk '{print $14+$15+$16+$17}')
		result=$((processcpu * 100 / totalcpu))
		result="${result}%"
	else
		result="No such process:$1"
	fi
	print_result "${result}"
}


processcpu $1
processmem $1

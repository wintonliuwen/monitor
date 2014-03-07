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
		result=$(echo $(cat /proc/${pid}/status | grep VmSize | awk -F':' '{print $2}'))
	else
		result="No such process:$1"
	fi
	print_result "$result"
}

processmem $1

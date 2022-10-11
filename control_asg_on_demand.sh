#!/bin/bash

export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export AWS_DEFAULT_REGION="us-west-1"
BOXTYPE=$2

declare -A MIN
declare -A MAX
declare -A DESIRED
declare -A LOCATION
declare -a LABELS=()

function getData() {
	DATA_JSON=`echo "$ASGS_JSON" | jq '. | {Name:.AutoScalingGroupName, Min:.MinSize, Max:.MaxSize, Desired:.DesiredCapacity, FZ_LOCATION:.Tags[] | select (.Key == "FZ_LOCATION")| .Value } '`
	for ASG_Name in `echo $DATA_JSON | jq -r '.Name'`; do
		record_t="echo '$DATA_JSON' | jq '. | select (.Name == \"$ASG_Name\")'"
		record=`eval $record_t`
		OS=`getOS $ASG_Name`
		MIN["$ASG_Name"]=`echo $record | jq -r ".Min"`
		MAX["$ASG_Name"]=`echo $record | jq -r ".Max"`
		DESIRED["$ASG_Name"]=`echo $record | jq -r ".Desired"`
		LOCATION["$ASG_Name"]=`echo $record | jq -r ".FZ_LOCATION"`
		line="$ASG_Name - $OS - `echo $record | jq -r ".FZ_LOCATION"`"
		LABELS+=("$line")
	done
}

function ExportData() {
	export MIN
	export MAX
	export DESIRED
	export LOCATION
}

function buildDesiredSeq() {
	ASG_Name=$1
	echo ${DESIRED["$ASG_Name"]}; seq 0 1 ${MAX["$ASG_Name"]} | grep -v ${DESIRED["$ASG_Name"]}
}

function buildASGchoices() {
	for label in "${LABELS[@]}"; do
		echo $label
	done
}

function fetchAWS() {
	ASGS_T="aws autoscaling describe-auto-scaling-groups --max-items 1000 | jq '.AutoScalingGroups[] | select (.AutoScalingGroupName | contains (\"$AWSENV$BOXTYPE\"))' "
	#ASGS_T="aws autoscaling describe-auto-scaling-groups --max-items 1000 | jq '.AutoScalingGroups[] | select (.AutoScalingGroupName | contains (\"main$BOXTYPE\"))' "
	#ASGS_T="cat resp.txt | jq '.AutoScalingGroups[] | select (.AutoScalingGroupName | contains (\"$BOXTYPE\"))' "
	ASGS_JSON=$(eval $ASGS_T)
}

function getOS() {
	#this is not very reliable would be better a tag in the ASG
	Name=$1
	if [[ "${Name:(-2):1}" == "0" ]]; then
		echo "trusty"
	else
		echo "bionic"
	fi
}

function getRegion() {
	if [[ "$REGION" == "SJO" ]]; then
		AWS_DEFAULT_REGION="us-west-1"
	else
		AWS_DEFAULT_REGION="us-east-1"
	fi
}

REGION=$1
AWSENV=$4 # main or intg
getRegion
case $3 in
	"asg")
		fetchAWS
		getData
		buildASGchoices
	;;
	"seq")
		fetchAWS
		getData
		ASG_Name="$5"
		buildDesiredSeq ${ASG_Name%% -*}
	;;
esac

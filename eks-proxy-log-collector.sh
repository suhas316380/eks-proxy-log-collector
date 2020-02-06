## Author: Suhas Basarkod

#!/usr/bin/env bash 

node_names=$1
proxy_port='8080'

pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

# Check for Pre-requisites. We need kubectl, curl, jq, wget and tar
check_prereqs()
{
  no_go=0
  declare -a pre_req_utils=("kubectl" "curl" "jq" "wget" "tar")
  for p in "${pre_req_utils[@]}"
  do 
    [[ ! `${p} --help 2>/dev/null` ]] && echo "${p} does not exist. Please install it first" && no_go=1
  done
  [[ ${no_go} -eq 1 ]] && exit 0
}

# Run validation against NodeNames if they are specified as arguements to this script. This function checks for:
# 1. If the Node Name is in the correct format using Perl Pattern matching via grep. Eg: ip-192-168-2-227.ec2.internal
# 2. Checks if the specified NodeName exists in the current context by checking the status code via Curl command. Eg: curl http://localhost:<proxy_port>/api/v1/nodes/<node_name> 
validate()
{
    # Run proxy
    kubectl proxy --port=${proxy_port} &
    echo "Starting kubectl proxy ..sleeping for 5 seconds"
    sleep 5
    node_names=$(echo $1 | tr -d ' ')
    IFS=',' read -r -a node_names <<< "$node_names"
    for s in "${node_names[@]}"
    do
      if echo $s | grep -qP '^ip-\d{1,3}\-\d{1,3}\-\d{1,3}\-\d{1,3}.ec2.internal'; then
        status_code=$(curl -s -o /dev/null -w "%{http_code}" ${base_uri}/${s} -o /dev/null)
        if echo ${status_code} | grep -v -q '200'; then
          echo "Node Not found in context (${current_context}): run 'curl ${base_uri}/${s}' manually to check'"
          exit 0
        fi
      elif echo $s | grep -qP '^fargate-ip-\d{1,3}\-\d{1,3}\-\d{1,3}\-\d{1,3}.ec2.internal'; then
        echo "found fargate Node - ${i} ..EKS Fargate node logging feature isn't available yet"
        exit 0
      else
        echo "malformed nodeName: $s \n run 'kubectl get no' to get the nodeNames"
        exit 0
      fi
    done
}

check_prereqs

tmp_log_dir="/tmp/logs" && mkdir -p ${tmp_log_dir} && pushd ${tmp_log_dir}
current_context=$(kubectl config current-context)
base_uri="http://localhost:${proxy_port}/api/v1/nodes"

# Check if any NodeName(s) are passed via script. If not, give user a chance to pass it again.
# If no NodeNames are passed, script will get logs from all the Nodes within a Cluster. 
if [[ -z "$node_names" ]]; then
  read -e -p "
  No node names Specified..Would you like to pass 1 or more Nodenames (comma saperated values) - Yes|No|Exit ? [Y|N|E] " YN
  if [[ $YN == "y" || $YN == "Y" ]]; then
    read -e -p "Enter NodeName(s): " node_names
    validate "$node_names"
  elif [[ $YN == "E" || $YN == "e" ]]; then exit 0
  else
    # Run proxy
    kubectl proxy --port=${proxy_port} & 
    echo "No problem.. Attempting to pull logs from all the nodes :)"
    echo "Starting kubectl proxy ..sleeping for 5 seconds"
    sleep 5
    # Get nodeNames
    node_names=$(IFS=" " curl -s ${base_uri}/ | jq .items[].metadata.name )
    declare -a node_names=( $node_names )
  fi
else
  validate "$node_names"
fi

# Required Log directories found at: http://localhost:<proxy_port>/api/v1/nodes/ip-192-168-2-227.ec2.internal/proxy/logs/*
# Container Logs: Only grab "aws-node", "kube-system" and "coredns" container logs
# aws-routed-eni: Container ipamd and plugin logs
# messages: /var/log/messages of the node
declare -a target_log_dirs=("containers" "aws-routed-eni" "messages")

# Initilize
declare -a final_log_dirs=()

# now loop through the NodeNames
for i in "${node_names[@]}"
do
  i=$(echo $i | tr -d "\"" | tr -d "\'")
  # Skip Fargate Logs as it's not available yet
  if echo $i | grep -qP '^fargate-ip-\d{1,3}\-\d{1,3}\-\d{1,3}\-\d{1,3}.ec2.internal'; then
    echo "found fargate Node - ${i}..Skipping it as it's EKS Fargate node logging feature isn't available yet"
    continue
  # Get EC2 WorkerNode logs 
  elif echo $i | grep -qP '^ip-\d{1,3}\-\d{1,3}\-\d{1,3}\-\d{1,3}.ec2.internal'; then
    logs_uri="${base_uri}/${i}/proxy/logs/"
    present_log_dirs=$(curl -s $logs_uri | grep -Po '(?<=href=")[^"]*(?=")')
    declare -a present_log_dirs=( $present_log_dirs )
    for k in "${present_log_dirs[@]}"
    do
      if [[ $(printf "_[%s]_" "${target_log_dirs[@]}") =~ .*_\[${k}*\]_.* ]]; then
        full_uri="${logs_uri}${k}"
        echo "Gathering logs from: $full_uri"
        if [[ "$k" =~ "containers" ]]; then
          wget --quiet --no-parent -r -A '*aws-node*,*coredns*,*kube-proxy*' $full_uri
        elif [[ "$k" =~ "messages" ]]; then
          wget --quiet --no-parent -r -A '*messages*' $full_uri
        else
          wget --quiet --no-parent -r -A '*.log*' $full_uri
        fi
      fi
    done
    # Get the information about the Node.
    curl -s ${base_uri}/${i} | jq '.metadata, .spec, .status' > ${tmp_log_dir}/localhost\:${proxy_port}/api/v1/nodes/${i}/${i}_nodeinfo.json
  else
    echo "Unknown Error while getting logs for ${i}" && exit 1
  fi
done
[[ -d ${tmp_log_dir}/localhost\:${proxy_port}/api/v1/nodes ]] && tar -C ${tmp_log_dir}/localhost\:${proxy_port}/api/v1/nodes -cpzf logs.tar.gz ./ && rm -rf ${tmp_log_dir}/localhost\:${proxy_port} 2>/dev/null && ls ${tmp_log_dir}/logs.tar.gz 2>/dev/null
kill -9 $(ps -ef | grep "kubectl proxy" | grep -v grep | awk '{print $2}') &>/dev/null
popd ${tmp_log_dir}

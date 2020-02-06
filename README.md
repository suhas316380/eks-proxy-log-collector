# eks-proxy-log-collector

This interactive bash script enables us to collect IPAMd logs, /var/log/messages and logs of containers(aws-node, coreDNS and kube-proxy) within kube-system namespace posted by kubelet within each worker node in an Amazon EKS Cluster by [starting a proxy to the Kubernetes API] server. Logs are exported to /tmp/logs/logs.tar.gz. This is especially helpful if one does not have the ability to login to the worker nodes. If you have SSH access to worker nodes, use [eks-log-collector] instead. 


### Pre-reqs

  - kubectl, curl, jq, wget and tar
  - Required permissions to run 'kubectl proxy' command
  - Script needs to be run on the server from where you have installed kubectl to communicate with your cluster without having to tunnel to bastion.

Limitations:
  - Does not work with Fargate nodes


### Usage
**Example-1**: Accepts a single nodename or multiple comma saperated nodenames as an arguement to the script.

```sh
$curl -O https://raw.githubusercontent.com/suhas316380/eks-proxy-log-collector/master/eks-proxy-log-collector.sh | bash eks-proxy-log-collector.sh <node_name-1>,<node_name-2>
```

If nodename(s) arguement is passed, script checks if the specified node:
1. Matches the pattern: `^ip-\d{1,3}\-\d{1,3}\-\d{1,3}\-\d{1,3}.*.internal`
2. Belongs to the cluster based on current context (`kubectl config current-context`) by checking the status code via curl
```sh
$curl -s -o /dev/null -w "%{http_code}" http://localhost:${proxy_port}/api/v1/nodes/<node_name> -o /dev/null
```

**Example-2**:
```sh
$curl -O https://raw.githubusercontent.com/suhas316380/eks-proxy-log-collector/master/eks-proxy-log-collector.sh | bash eks-proxy-log-collector.sh
No node names Specified..Would you like to pass 1 or more Nodenames (comma saperated values) - Yes|No|Exit ? [Y|N|E] n
No problem.. Attempting to pull logs from all the nodes :)
Starting kubectl proxy ..sleeping for 5 seconds
Starting to serve on 127.0.0.1:8080
Gathering logs from ...
...

```

When executed, script starts a proxy by executing the following command in the background (default proxy port is 8080):

```sh
$kubectl proxy --port=${proxy_port} & 
```

Once the proxy to the API server is started, it attempts to pull logs from the following locations:
```
- http://localhost:8080/api/v1/nodes/<woker_node_name>/proxy/logs/aws-routed-eni/*
- http://localhost:8080/api/v1/nodes/<woker_node_name>/proxy/logs/messages
- http://localhost:8080/api/v1/nodes/<woker_node_name>/proxy/logs/containers/*
```
Once done, logs are exported to /tmp/logs/logs.tar.gz and kubectl proxy process is killed by running:

```sh
$kill -9 $(ps -ef | grep "kubectl proxy" | grep -v grep | awk '{print $2}') &>/dev/null
```
### Output Example

**Example-1**: Pull logs of a specific worker nodes
```
$curl -O https://raw.githubusercontent.com/suhas316380/eks-proxy-log-collector/master/eks-proxy-log-collector.sh | bash eks-proxy-log-collector.sh ip-192-168-13-15.ec2.internal
Starting kubectl proxy ..sleeping for 5 seconds
Starting to serve on 127.0.0.1:8080
Gathering logs from: http://localhost:8080/api/v1/nodes/ip-192-168-13-15.ec2.internal/proxy/logs/aws-routed-eni/
Gathering logs from: http://localhost:8080/api/v1/nodes/ip-192-168-13-15.ec2.internal/proxy/logs/containers/
Gathering logs from: http://localhost:8080/api/v1/nodes/ip-192-168-13-15.ec2.internal/proxy/logs/messages
/tmp/logs/logs.tar.gz

```

**Example-2**: Pull logs of all the worker nodes in the cluster
```
$curl -O https://raw.githubusercontent.com/suhas316380/eks-proxy-log-collector/master/eks-proxy-log-collector.sh | bash eks-proxy-log-collector.sh

No node names Specified..Would you like to pass 1 or more Nodenames (comma saperated values) - Yes|No|Exit ? [Y|N|E] n
No problem.. Attempting to pull logs from all the nodes :)
Starting kubectl proxy ..sleeping for 5 seconds
Starting to serve on 127.0.0.1:8080
Gathering logs from: http://localhost:8080/api/v1/nodes/ip-192-168-13-15.ec2.internal/proxy/logs/aws-routed-eni/
Gathering logs from: http://localhost:8080/api/v1/nodes/ip-192-168-13-15.ec2.internal/proxy/logs/containers/
Gathering logs from: http://localhost:8080/api/v1/nodes/ip-192-168-13-15.ec2.internal/proxy/logs/messages
Gathering logs from: http://localhost:8080/api/v1/nodes/ip-192-168-51-176.ec2.internal/proxy/logs/aws-routed-eni/
Gathering logs from: http://localhost:8080/api/v1/nodes/ip-192-168-51-176.ec2.internal/proxy/logs/containers/
Gathering logs from: http://localhost:8080/api/v1/nodes/ip-192-168-51-176.ec2.internal/proxy/logs/messages

```

### Todos

 - Needs improvement in error handling.
 - If you are using bastion host, script does not support tunneling. This feature needs to be implemented in the script - equivalent of: `ssh -i <<Keypair>> ec2-user@<<Public_IP_Workstation>> -L 8080:127.0.0.1:8080`

### Troubleshooting
 - Make sure the correct context is set using cluster ARN and not an alias. Eg: `kubectl config use-context arn:aws:eks:us-east-1:12345678:cluster/suhas-eks`
 - If running the script on Mac, if you run into error with grep, make sure to use bash interpreter: `bash eks-proxy-log-collector.sh`

   [eks-log-collector]: <https://github.com/nithu0115/eks-logs-collector>
   [starting a proxy to the Kubernetes API]: <https://kubernetes.io/docs/tasks/access-kubernetes-api/http-proxy-access-api/>

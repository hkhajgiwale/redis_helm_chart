#!/bin/bash

# Define key and value for testing
KEY="mykey"
VALUE="Hello, Redis!"
MAX_RETRIES=2
RETRY_INTERVAL=10

# Function to discover Redis node IPs
get_redis_node_ips() {
  kubectl get pods -l app=redis -o jsonpath='{.items[*].status.podIP}'
}

# Function to get master node IP
get_master_ip() {
  kubectl get pods -l app=redis,role=master -o jsonpath='{.items[0].status.podIP}'
}

# Function to get replica node IPs
get_replica_ips() {
  kubectl get pods -l app=redis,role=replica -o jsonpath='{.items[*].status.podIP}'
}

# Function to check cluster status
check_cluster() {
  for ip in $(get_redis_node_ips); do
    if kubectl exec -i $(kubectl get pods -l app=redis,role=master -o jsonpath='{.items[0].metadata.name}') -- redis-cli -h $ip -p 6379 cluster info | grep -q "cluster_state:ok"; then
      echo "Cluster is operational on node $ip."
      return 0
    fi
  done
  return 1
}

# Function to create Redis cluster
create_cluster() {
  REDIS_NODES=$(printf "%s:6379 " $(get_redis_node_ips))
  kubectl exec -i $(kubectl get pods -l app=redis,role=master -o jsonpath='{.items[0].metadata.name}') -- redis-cli --cluster create $REDIS_NODES --cluster-replicas 1 <<EOF
yes
EOF
}

# Function to wait until the cluster is operational
wait_for_cluster() {
  local retries=0
  while [ $retries -lt $MAX_RETRIES ]; do
    if check_cluster; then
      return 0
    fi
    sleep $RETRY_INTERVAL
    retries=$((retries + 1))
  done
  echo "Cluster did not become operational within the expected time."
  return 1
}

# Function to push data to the cluster
push_data() {
  local master_ip=$(get_master_ip)
  echo "Pushing data to master node $master_ip..."
  kubectl exec -i $(kubectl get pods -l app=redis,role=master -o jsonpath='{.items[0].metadata.name}') -- sh -c "redis-cli -c -h $master_ip -p 6379 set $KEY \"$VALUE\""
}

# Function to verify data on a node
verify_data_on_node() {
  local node_ip=$1
  DATA=$(kubectl exec -i $(kubectl get pods -l app=redis,role=master -o jsonpath='{.items[0].metadata.name}') -- sh -c "redis-cli -c -h $node_ip -p 6379 get $KEY" 2>/dev/null)
  echo $DATA
}

# Function to verify data on master
verify_data_on_master() {
  local retries=0
  local master_ip=$(get_master_ip)
  while [ $retries -lt $MAX_RETRIES ]; do
    MASTER_DATA=$(verify_data_on_node $master_ip)
    if [[ "$MASTER_DATA" == "$VALUE" ]]; then
      echo "Data successfully pushed to master node $master_ip."
      return 0
    fi
    sleep $RETRY_INTERVAL
    retries=$((retries + 1))
  done
  echo "Failed to push data to master node $master_ip."
  return 1
}

# Function to check data replication
check_replication() {
  local retries=0
  while [ $retries -lt $MAX_RETRIES ]; do
    local all_replicas_ok=1
    for ip in $(get_redis_node_ips); do
      REPLICA_DATA=$(verify_data_on_node $ip)
      if [[ "$REPLICA_DATA" != "$VALUE" ]]; then
        echo "Data not replicated properly on node $ip. Expected: $VALUE, Got: $REPLICA_DATA"
        all_replicas_ok=0
      fi
    done
    if [ $all_replicas_ok -eq 1 ]; then
      echo "Data replication successful."
      return 0
    fi
    sleep $RETRY_INTERVAL
    retries=$((retries + 1))
  done
  echo "Data replication failed."
  return 1
}

# Main script execution
if check_cluster; then
  echo "Redis cluster is already created."
else
  create_cluster
fi

wait_for_cluster
push_data
verify_data_on_master
check_replication

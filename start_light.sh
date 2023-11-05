#!/usr/bin/env bash

if [ $# -lt 3 ];then
    echo "Usage: $0 bridge_host_user bridge_ip bridge_path"
    echo "example"
    echo "$0 ubuntu 10.8.22.241 /data/celestia/bridge/"
    exit
fi

buser=$1
bip=$2
bridge_path=$3

which sshpass
ret=$?
if [ $ret -ne 0 ];then
    sudo apt-get install sshpass
fi

BRIDGE_PATH=$bridge_path
info=$(ssh ubuntu@$bip "celestia p2p info --node.store $BRIDGE_PATH")
echo $info

# Try to get the genesis hash. Usually first request returns an empty string (port is not open, curl fails), later attempts
# returns "null" if block was not yet produced.
GENESIS=
CNT=0
MAX=30
while [ "${#GENESIS}" -le 4 -a $CNT -ne $MAX ]; do
	GENESIS=$(curl -s http://$bip:26657/block?height=1 | jq '.result.block_id.hash' | tr -d '"')
	((CNT++))
	sleep 1
done

bridge_id=$(echo $info | jq .result.id | tr -d '"')
addr=$(echo $info | jq .result.peer_addr | tr -d '"' | grep ip4 | sed 's/^[[:space:]]*//' | sed 's/,$//')
BRIDGE="$addr/p2p/$bridge_id"
NETWORK="private"
export CELESTIA_CUSTOM="${NETWORK}:${GENESIS}:${BRIDGE}"
echo $CELESTIA_CUSTOM

# light node
LIGHT_STORE=/data/celestia/celestia-light-testnet
rm -rf $LIGHT_STORE
mkdir -p $LIGHT_STORE

celestia light init --node.store $LIGHT_STORE --p2p.network $NETWORK
nohup celestia light start --node.store $LIGHT_STORE --gateway --core.ip $bip &> ./light.log &

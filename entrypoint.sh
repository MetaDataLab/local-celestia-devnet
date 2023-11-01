#!/usr/bin/env bash
# dependencies: (1) celestia-app v1.1.0 
#               (2) celestia v0.11.0

set -x

CHAINID="private"
MONIKER="validator1"
KEY_NAME=validator

# App & node has a celestia user with home dir /home/celestia
if grep -q "init" /proc/1/cgroup; then
    echo "Running on Linux Ubuntu host"
    ENV="linux"
    APP_PATH="/data/celestia/.celestia-app"
    NODE_PATH="/data/celestia/bridge/"
else
    echo "Running in Docker container"
    ENV="docker"
    APP_PATH="/home/celestia/.celestia-app"
    NODE_PATH="/home/celestia/bridge/"
fi


# Check if the folder exists
if [ -d "$APP_PATH" ]; then
  # If it exists, delete it
  echo "The folder $APP_PATH exists. Deleting it..."
  rm -rf "$APP_PATH"
  echo "Folder deleted."
else
  # If it doesn't exist, print a message
  echo "The folder $APP_PATH does not exist."
fi

# Check if the folder exists
if [ -d "$NODE_PATH" ]; then
  # If it exists, delete it
  echo "The folder $NODE_PATH exists. Deleting it..."
  rm -rf "$NODE_PATH"
  echo "Folder deleted."
else
  # If it doesn't exist, print a message
  echo "The folder $NODE_PATH does not exist."
fi

# Build genesis file incl account for passed address
coins="1000000000000000utia"
celestia-appd init $MONIKER --chain-id $CHAINID --home $APP_PATH
celestia-appd keys add $KEY_NAME --keyring-backend="test" --home $APP_PATH
# this won't work because some proto types are declared twice and the logs output to stdout (dependency hell involving iavl)
celestia-appd add-genesis-account $KEY_NAME $coins --home $APP_PATH
celestia-appd gentx $KEY_NAME 5000000000utia \
  --home $APP_PATH \
  --keyring-backend="test" \
  --chain-id $CHAINID

celestia-appd collect-gentxs --home $APP_PATH  

celestia-appd version &> /tmp/version
APPD_VER_X=$(cat /tmp/version | cut -d '.' -f 1)
APPD_VER_Y=$(cat /tmp/version | cut -d '.' -f 2)

# Set proper defaults and change ports
# If you encounter: `sed: -I or -i may not be used with stdin` on MacOS you can mitigate by installing gnu-sed
# https://gist.github.com/andre3k1/e3a1a7133fded5de5a9ee99c87c6fa0d?permalink_comment_id=3082272#gistcomment-3082272
sed -i'.bak' 's#"tcp://127.0.0.1:26657"#"tcp://0.0.0.0:26657"#g' $APP_PATH/config/config.toml
# celestia-appd v1.3.0 to be set
if [ $APPD_VER_Y -gt 1 ];then
    sed -i 's/grpc_laddr = ""/grpc_laddr = "tcp:\/\/0.0.0.0:9090"/' $APP_PATH/config/config.toml
fi

#sed -i'.bak' 's/timeout_commit = "25s"/timeout_commit = "1s"/g' $APP_PATH/config/config.toml
#sed -i'.bak' 's/timeout_propose = "3s"/timeout_propose = "1s"/g' $APP_PATH/config/config.toml
#sed -i'.bak' 's/index_all_keys = false/index_all_keys = true/g' $APP_PATH/config/config.toml
#sed -i'.bak' 's/mode = "full"/mode = "validator"/g' $APP_PATH/config/config.toml

# Register the validator EVM address
{
  # wait for block 1
  sleep 20

  # private key: da6ed55cb2894ac2c9c10209c09de8e8b9d109b910338d5bf3d747a7e1fc9eb9
  celestia-appd tx qgb register \
    "$(celestia-appd keys show validator --home "${APP_PATH}" --bech val -a)" \
    0x966e6f22781EF6a6A82BBB4DB3df8E225DfD9488 \
    --from validator \
    --home "${APP_PATH}" \
    --fees 30000utia -b block \
    -y
} &

mkdir -p $NODE_PATH/keys
cp -r $APP_PATH/keyring-test/ $NODE_PATH/keys/keyring-test/

# Start the celestia-app
if [ "$ENV" = "linux" ]; then
    nohup celestia-appd start --home $APP_PATH &> celestia-appd.log &
else
    celestia-appd start --home $APP_PATH &
fi

# Try to get the genesis hash. Usually first request returns an empty string (port is not open, curl fails), later attempts
# returns "null" if block was not yet produced.
GENESIS=
CNT=0
MAX=30
while [ "${#GENESIS}" -le 4 -a $CNT -ne $MAX ]; do
	GENESIS=$(curl -s http://127.0.0.1:26657/block?height=1 | jq '.result.block_id.hash' | tr -d '"')
	((CNT++))
	sleep 1
done

export CELESTIA_CUSTOM=private:$GENESIS
echo $CELESTIA_CUSTOM

celestia bridge init --node.store $NODE_PATH
export CELESTIA_NODE_AUTH_TOKEN=$(celestia bridge auth admin --node.store ${NODE_PATH})
echo "WARNING: Keep this auth token secret **DO NOT** log this auth token outside of development. CELESTIA_NODE_AUTH_TOKEN=$CELESTIA_NODE_AUTH_TOKEN"

if [ "$ENV" = "linux" ]; then
    nohup celestia bridge start \
      --node.store $NODE_PATH --gateway \
      --core.ip 127.0.0.1 \
      --keyring.accname validator &> bridge.log &
else
    celestia bridge start \
      --node.store $NODE_PATH --gateway \
      --core.ip 127.0.0.1 \
      --keyring.accname validator
fi
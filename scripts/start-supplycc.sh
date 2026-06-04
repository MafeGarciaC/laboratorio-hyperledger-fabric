#!/bin/bash
# Script para iniciar el chaincode server supplycc
# Ejecutar cada vez que WSL se reinicia
export PATH=$HOME/fabric/fabric-samples/bin:/usr/local/go/bin:$PATH

FABRIC_DIR="$HOME/fabric/fabric-samples"
NETWORK_DIR="$FABRIC_DIR/test-network"
export FABRIC_CFG_PATH="$FABRIC_DIR/config/"
export CORE_PEER_TLS_ENABLED=true
export PEER1_TLS="$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem"

org1() {
  export CORE_PEER_LOCALMSPID="Org1MSP"
  export CORE_PEER_TLS_ROOTCERT_FILE="$PEER1_TLS"
  export CORE_PEER_MSPCONFIGPATH="$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
  export CORE_PEER_ADDRESS="localhost:7051"
}

# Esperar Docker
for i in $(seq 1 30); do
  docker ps &>/dev/null && break
  sleep 2
done

# Obtener Docker gateway IP
DOCKER_GW=$(docker inspect peer0.org1.example.com \
    --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}' 2>/dev/null | head -1)
[ -z "$DOCKER_GW" ] && DOCKER_GW="172.18.0.1"

# Recompilar si no existe
if [ ! -f /tmp/supplycc_server ]; then
  cd ~/capstone/chaincode
  go build -o /tmp/supplycc_server \
    ~/capstone/chaincode/supplycc_noMain.go \
    ~/capstone/chaincode/main_caas.go 2>/dev/null
fi

# Esperar peers
for i in $(seq 1 30); do
  curl -s http://localhost:5984 | grep -q "couchdb" && break
  sleep 3
done
org1
for i in $(seq 1 30); do
  peer channel list>/dev/null 2>&1 && break
  sleep 3
done

# Obtener CCID
SEQ=$(peer lifecycle chaincode querycommitted -C supplychannel --name supplycc --output json 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('sequence',0))" 2>/dev/null || echo "0")
CCID=$(peer lifecycle chaincode queryapproved \
    --channelID supplychannel --name supplycc --sequence "$SEQ" --output json 2>/dev/null \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
src = d.get('source',{}).get('Type',{})
for k,v in src.items():
    if isinstance(v, dict) and 'package_id' in v:
        print(v['package_id'])
" 2>/dev/null)

# Matar instancias anteriores
pkill -f "supplycc_server" 2>/dev/null; sleep 1

# Iniciar server
nohup env \
    CHAINCODE_SERVER_CCID="$CCID" \
    CHAINCODE_SERVER_ADDRESS="0.0.0.0:7052" \
    /tmp/supplycc_server \
    > /tmp/cc.log 2>&1 &
echo "✓ Chaincode server iniciado (CCID: $CCID)"
echo "  Log: /tmp/cc.log"

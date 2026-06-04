#!/bin/bash
# =============================================================================
#  deploy-supplycc.sh
#  Despliega el chaincode supplycc en el canal supplychannel
#  Laboratorio Capstone — Semanas 4 + 5 | Jaider Reyes Herazo
# =============================================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
err()  { echo -e "${RED}✗ ERROR: $1${NC}"; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $1${NC}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"; }

# ── CONFIGURACIÓN ─────────────────────────────────────────────────────────────
FABRIC_DIR="$HOME/fabric/fabric-samples"
NETWORK_DIR="$FABRIC_DIR/test-network"
CHANNEL_NAME="supplychannel"
CC_NAME="supplycc"
CC_VERSION="1.0"
CC_SEQUENCE="1"
CC_SRC_PATH="$(cd "$(dirname "$0")/../chaincode" && pwd)"

export PATH="$FABRIC_DIR/bin:$PATH"
export FABRIC_CFG_PATH="$FABRIC_DIR/config/"
export CORE_PEER_TLS_ENABLED=true
export ORDERER_CA="$NETWORK_DIR/organizations/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem"
export PEER1_TLS="$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem"
export PEER2_TLS="$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem"

set_org1() {
  export CORE_PEER_LOCALMSPID="Org1MSP"
  export CORE_PEER_TLS_ROOTCERT_FILE="$PEER1_TLS"
  export CORE_PEER_MSPCONFIGPATH="$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
  export CORE_PEER_ADDRESS="localhost:7051"
}

set_org2() {
  export CORE_PEER_LOCALMSPID="Org2MSP"
  export CORE_PEER_TLS_ROOTCERT_FILE="$PEER2_TLS"
  export CORE_PEER_MSPCONFIGPATH="$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp"
  export CORE_PEER_ADDRESS="localhost:9051"
}

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Laboratorio Capstone — Semanas 4 + 5     ║${NC}"
echo -e "${BOLD}║  Despliegue: supplycc v1.0                ║${NC}"
echo -e "${BOLD}║  Canal: supplychannel                     ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════╝${NC}"
echo ""

# ── PASO 0: VERIFICAR RED ─────────────────────────────────────────────────────
step "PASO 0 · Verificando red activa"
docker ps --filter "name=peer0.org1" --format "{{.Names}}" | grep -q "peer0.org1" || \
  err "La red no está corriendo. Ejecuta primero: ./setup-network-s3.sh"
ok "Red Fabric activa"
ok "Canal supplychannel disponible"

# ── PASO 1: EMPAQUETAR ────────────────────────────────────────────────────────
step "PASO 1 · Empaquetando chaincode supplycc"
set_org1
cd "$NETWORK_DIR"

peer lifecycle chaincode package "${CC_NAME}.tar.gz" \
  --path "$CC_SRC_PATH" \
  --lang golang \
  --label "${CC_NAME}_${CC_VERSION}"

ok "Chaincode empaquetado: ${CC_NAME}.tar.gz"
ls -lh "${CC_NAME}.tar.gz"

# ── PASO 2: INSTALAR EN ORG1 ──────────────────────────────────────────────────
step "PASO 2 · Instalando en peer0.org1 (Proveedor)"
set_org1
peer lifecycle chaincode install "${CC_NAME}.tar.gz"
ok "Instalado en Org1"

# ── PASO 3: INSTALAR EN ORG2 ──────────────────────────────────────────────────
step "PASO 3 · Instalando en peer0.org2 (Distribuidor)"
set_org2
peer lifecycle chaincode install "${CC_NAME}.tar.gz"
ok "Instalado en Org2"

# ── PASO 4: OBTENER PACKAGE ID ────────────────────────────────────────────────
step "PASO 4 · Obteniendo Package ID"
set_org1
PACKAGE_ID=$(peer lifecycle chaincode queryinstalled \
  | grep "${CC_NAME}_${CC_VERSION}" \
  | awk -F'[, ]+' '{for(i=1;i<=NF;i++) if($i=="Package") print $(i+2)}' \
  | head -1)

# Método alternativo si el anterior falla
if [ -z "$PACKAGE_ID" ]; then
  PACKAGE_ID=$(peer lifecycle chaincode queryinstalled 2>/dev/null \
    | grep "Label: ${CC_NAME}_${CC_VERSION}" -A1 \
    | grep "Package ID:" \
    | awk '{print $3}' | tr -d ',')
fi

# Método más robusto
if [ -z "$PACKAGE_ID" ]; then
  PACKAGE_ID=$(peer lifecycle chaincode queryinstalled 2>/dev/null \
    | grep "${CC_NAME}_${CC_VERSION}" \
    | sed 's/.*Package ID: //' | sed 's/,.*//')
fi

[ -z "$PACKAGE_ID" ] && err "No se pudo obtener el Package ID"
ok "Package ID: $PACKAGE_ID"

# ── PASO 5: APROBAR COMO ORG1 ─────────────────────────────────────────────────
step "PASO 5 · Aprobando chaincode como Org1 (Proveedor)"
set_org1
peer lifecycle chaincode approveformyorg \
  -o localhost:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --channelID "$CHANNEL_NAME" \
  --name "$CC_NAME" \
  --version "$CC_VERSION" \
  --package-id "$PACKAGE_ID" \
  --sequence "$CC_SEQUENCE" \
  --tls --cafile "$ORDERER_CA"
ok "Aprobado por Org1MSP"

# ── PASO 6: APROBAR COMO ORG2 ─────────────────────────────────────────────────
step "PASO 6 · Aprobando chaincode como Org2 (Distribuidor)"
set_org2
peer lifecycle chaincode approveformyorg \
  -o localhost:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --channelID "$CHANNEL_NAME" \
  --name "$CC_NAME" \
  --version "$CC_VERSION" \
  --package-id "$PACKAGE_ID" \
  --sequence "$CC_SEQUENCE" \
  --tls --cafile "$ORDERER_CA"
ok "Aprobado por Org2MSP"

# ── PASO 7: VERIFICAR LISTA DE APROBACIONES ───────────────────────────────────
step "PASO 7 · Verificando endorsement policy AND(Org1, Org2)"
set_org1
peer lifecycle chaincode checkcommitreadiness \
  --channelID "$CHANNEL_NAME" \
  --name "$CC_NAME" \
  --version "$CC_VERSION" \
  --sequence "$CC_SEQUENCE" \
  --tls --cafile "$ORDERER_CA" \
  --output json

# ── PASO 8: COMMIT AL CANAL ───────────────────────────────────────────────────
step "PASO 8 · Haciendo commit del chaincode al canal"
set_org1
peer lifecycle chaincode commit \
  -o localhost:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --channelID "$CHANNEL_NAME" \
  --name "$CC_NAME" \
  --version "$CC_VERSION" \
  --sequence "$CC_SEQUENCE" \
  --tls --cafile "$ORDERER_CA" \
  --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER1_TLS" \
  --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER2_TLS"
ok "Chaincode commiteado al canal $CHANNEL_NAME"

# ── PASO 9: INICIALIZAR LEDGER ────────────────────────────────────────────────
step "PASO 9 · Inicializando ledger con productos de ejemplo"
sleep 3
set_org1
peer chaincode invoke \
  -o localhost:7050 \
  --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile "$ORDERER_CA" \
  -C "$CHANNEL_NAME" -n "$CC_NAME" \
  --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER1_TLS" \
  --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER2_TLS" \
  -c '{"function":"InitLedger","Args":[]}'
sleep 3
ok "Ledger inicializado con 3 productos"

# ── PASO 10: VERIFICAR ────────────────────────────────────────────────────────
step "PASO 10 · Verificación final — Consultar todos los productos"
set_org1
peer chaincode query \
  -C "$CHANNEL_NAME" -n "$CC_NAME" \
  -c '{"function":"ConsultarTodos","Args":[]}' | python3 -m json.tool

echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  ✓ supplycc desplegado exitosamente        ║${NC}"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Chaincode: ${CYAN}$CC_NAME v$CC_VERSION${NC}"
echo -e "  Canal:     ${CYAN}$CHANNEL_NAME${NC}"
echo -e "  Funciones: InitLedger, RegistrarProducto, TransferirProducto,"
echo -e "             ConfirmarRecepcion, ActualizarCantidad, MarcarEntregado,"
echo -e "             LeerProducto, ObtenerHistorial, ConsultarTodos, ConsultarPorEstado"
echo ""
echo -e "  ${YELLOW}Siguiente paso: cd ../api && npm install && node app.js${NC}"
echo ""

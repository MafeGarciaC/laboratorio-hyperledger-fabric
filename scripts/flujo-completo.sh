#!/bin/bash
# =============================================================================
#  flujo-completo.sh
#  Prueba el flujo completo del Supply Chain usando el CLI del peer
#  Registrar → Transferir → Confirmar → ActualizarCantidad → MarcarEntregado
#  Laboratorio Capstone | Jaider Reyes Herazo
# =============================================================================

FABRIC_DIR="$HOME/fabric/fabric-samples"
NETWORK_DIR="$FABRIC_DIR/test-network"
CHANNEL="supplychannel"
CC="supplycc"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'; RED='\033[0;31m'

export PATH="$FABRIC_DIR/bin:$PATH"
export FABRIC_CFG_PATH="$FABRIC_DIR/config/"
export CORE_PEER_TLS_ENABLED=true
export ORDERER_CA="$NETWORK_DIR/organizations/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem"
export PEER1_TLS="$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem"
export PEER2_TLS="$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem"

org1() {
  export CORE_PEER_LOCALMSPID="Org1MSP"
  export CORE_PEER_TLS_ROOTCERT_FILE="$PEER1_TLS"
  export CORE_PEER_MSPCONFIGPATH="$NETWORK_DIR/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
  export CORE_PEER_ADDRESS="localhost:7051"
}
org2() {
  export CORE_PEER_LOCALMSPID="Org2MSP"
  export CORE_PEER_TLS_ROOTCERT_FILE="$PEER2_TLS"
  export CORE_PEER_MSPCONFIGPATH="$NETWORK_DIR/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp"
  export CORE_PEER_ADDRESS="localhost:9051"
}

invoke() {
  peer chaincode invoke -o localhost:7050 \
    --ordererTLSHostnameOverride orderer.example.com \
    --tls --cafile "$ORDERER_CA" \
    -C "$CHANNEL" -n "$CC" \
    --peerAddresses localhost:7051 --tlsRootCertFiles "$PEER1_TLS" \
    --peerAddresses localhost:9051 --tlsRootCertFiles "$PEER2_TLS" \
    -c "$1" 2>/dev/null
}

query() {
  peer chaincode query -C "$CHANNEL" -n "$CC" -c "$1" 2>/dev/null | python3 -m json.tool
}

banner() { echo -e "\n${BOLD}${CYAN}▶ $1${NC}\n"; }
ok()     { echo -e "  ${GREEN}✓ $1${NC}"; }
pause()  { echo -e "\n${YELLOW}  Presiona ENTER para continuar...${NC}"; read -r; }

clear
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Laboratorio Capstone — Flujo Completo Supply Chain ║${NC}"
echo -e "${BOLD}║  Semanas 4 + 5 | Hyperledger Fabric 2.5            ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
banner "ETAPA 1 — Estado inicial del ledger"
org1
echo -e "  Consultando todos los productos iniciales...\n"
query '{"function":"ConsultarTodos","Args":[]}'
pause

# ─────────────────────────────────────────────────────────────────────────────
banner "ETAPA 2 — Org1 registra un nuevo lote de Mango Tommy"
org1
echo -e "  Registrando PROD-010 desde Org1 (Proveedor)...\n"
invoke '{"function":"RegistrarProducto","Args":["PROD-010","Mango Tommy","800","kg","Tolima, Colombia","Barranquilla Puerto","24°C"]}'
sleep 3
ok "PROD-010 registrado en el ledger"
echo ""
echo -e "  Verificando en el World State...\n"
query '{"function":"LeerProducto","Args":["PROD-010"]}'
pause

# ─────────────────────────────────────────────────────────────────────────────
banner "ETAPA 3 — Org1 actualiza la cantidad (merma en bodega)"
org1
echo -e "  Actualizando cantidad de PROD-010 de 800 a 780 kg (merma 2.5%)...\n"
invoke '{"function":"ActualizarCantidad","Args":["PROD-010","780","Merma por seleccion de calidad en bodega"]}'
sleep 3
ok "Cantidad actualizada"
query '{"function":"LeerProducto","Args":["PROD-010"]}'
pause

# ─────────────────────────────────────────────────────────────────────────────
banner "ETAPA 4 — Org1 transfiere el lote a Org2 (Distribuidor)"
org1
echo -e "  Transfiriendo PROD-010 a Org2MSP...\n"
invoke '{"function":"TransferirProducto","Args":["PROD-010","Org2MSP","Envio maritimo Puerto Barranquilla - ETA 3 dias"]}'
sleep 3
ok "Producto en tránsito hacia Org2"
query '{"function":"LeerProducto","Args":["PROD-010"]}'
pause

# ─────────────────────────────────────────────────────────────────────────────
banner "ETAPA 5 — Org2 confirma la recepción del lote"
org2
echo -e "  Confirmando recepcion desde Org2 (Distribuidor)...\n"
invoke '{"function":"ConfirmarRecepcion","Args":["PROD-010","22°C","Lote recibido en excelente estado - certificado fitosanitario OK"]}'
sleep 3
ok "Recepción confirmada por Org2MSP"
query '{"function":"LeerProducto","Args":["PROD-010"]}'
pause

# ─────────────────────────────────────────────────────────────────────────────
banner "ETAPA 6 — Org2 marca el producto como entregado al cliente final"
org2
echo -e "  Marcando entrega final a SuperAlimentos S.A...\n"
invoke '{"function":"MarcarEntregado","Args":["PROD-010","SuperAlimentos S.A.","Factura #2026-089 - Recibido conforme"]}'
sleep 3
ok "Producto entregado al cliente final"
query '{"function":"LeerProducto","Args":["PROD-010"]}'
pause

# ─────────────────────────────────────────────────────────────────────────────
banner "ETAPA 7 — Historial completo del ledger para PROD-010"
org1
echo -e "  Consultando historial inmutable desde el genesis...\n"
query '{"function":"ObtenerHistorial","Args":["PROD-010"]}'
pause

# ─────────────────────────────────────────────────────────────────────────────
banner "ETAPA 8 — Estado final de TODOS los productos"
org1
echo ""
echo -e "  Productos REGISTRADOS:\n"
query '{"function":"ConsultarPorEstado","Args":["REGISTRADO"]}'
echo ""
echo -e "  Productos ENTREGADOS:\n"
query '{"function":"ConsultarPorEstado","Args":["ENTREGADO"]}'

echo ""
echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  ✓ Flujo completo Supply Chain ejecutado          ║${NC}"
echo -e "${GREEN}${BOLD}║  Abre CouchDB: http://localhost:5984/_utils        ║${NC}"
echo -e "${GREEN}${BOLD}║  Busca la base de datos: supplychannel_            ║${NC}"
echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

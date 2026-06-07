'use strict';
// =============================================================================
//  app.js — API REST Supply Chain | Laboratorio Capstone Semanas 4+5
//  Hyperledger Fabric 2.5 + Express + fabric-gateway
// =============================================================================

const express  = require('express');
const cors     = require('cors');
const morgan   = require('morgan');
const crypto   = require('crypto');
const fs       = require('fs');
const path     = require('path');
const grpc     = require('@grpc/grpc-js');
const { connect, hash, signers } = require('@hyperledger/fabric-gateway');

const app  = express();
const PORT = process.env.PORT || 3000;

// ── CONFIGURACIÓN FABRIC ─────────────────────────────────────────────────────
const FABRIC_DIR   = path.join(process.env.HOME, 'fabric', 'fabric-samples');
const NETWORK_DIR  = path.join(FABRIC_DIR, 'test-network');
const CHANNEL      = 'supplychannel';
const CHAINCODE    = 'supplycc';
const MSP_ID       = process.env.MSP_ID || 'Org1MSP';
const PEER_PORT    = MSP_ID === 'Org2MSP' ? '9051' : '7051';
const PEER_HOST    = MSP_ID === 'Org2MSP' ? 'peer0.org2.example.com' : 'peer0.org1.example.com';
const ORG_PATH     = MSP_ID === 'Org2MSP'
  ? path.join(NETWORK_DIR, 'organizations/peerOrganizations/org2.example.com')
  : path.join(NETWORK_DIR, 'organizations/peerOrganizations/org1.example.com');
const USER         = MSP_ID === 'Org2MSP' ? 'User1@org2.example.com' : 'User1@org1.example.com';

// ── MIDDLEWARE GLOBAL ─────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

// ── INSTANCIA GLOBAL DEL CONTRATO ─────────────────────────────────────────────
let contract;

async function conectarFabric() {
  const tlsCertPath = path.join(ORG_PATH, `tlsca/tlsca.${MSP_ID === 'Org2MSP' ? 'org2' : 'org1'}.example.com-cert.pem`);
  const certDir     = path.join(ORG_PATH, `users/${USER}/msp/signcerts`);
  const keyDir      = path.join(ORG_PATH, `users/${USER}/msp/keystore`);

  const tlsCert   = fs.readFileSync(tlsCertPath);
  const certFiles = fs.readdirSync(certDir);
  const certPem   = fs.readFileSync(path.join(certDir, certFiles[0]));
  const keyFiles  = fs.readdirSync(keyDir);
  const keyPem    = fs.readFileSync(path.join(keyDir, keyFiles[0]));

  const client = new grpc.Client(
    `localhost:${PEER_PORT}`,
    grpc.credentials.createSsl(tlsCert),
    { 'grpc.ssl_target_name_override': PEER_HOST }
  );

  const gateway = connect({
    client,
    identity: { mspId: MSP_ID, credentials: certPem },
    signer: signers.newPrivateKeySigner(crypto.createPrivateKey(keyPem)),
    evaluateOptions:    () => ({ deadline: Date.now() + 5000 }),
    endorseOptions:     () => ({ deadline: Date.now() + 15000 }),
    submitOptions:      () => ({ deadline: Date.now() + 5000 }),
    commitStatusOptions:() => ({ deadline: Date.now() + 60000 }),
  });

  const network = await gateway.getNetwork(CHANNEL);
  contract = network.getContract(CHAINCODE);
  console.log(`\n✅ Conectado a Fabric`);
  console.log(`   Org:       ${MSP_ID}`);
  console.log(`   Canal:     ${CHANNEL}`);
  console.log(`   Chaincode: ${CHAINCODE}\n`);
}

// ── HELPER ────────────────────────────────────────────────────────────────────
const decode = (result) => JSON.parse(Buffer.from(result).toString());
const wrap   = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// =============================================================================
//  MIDDLEWARE DE AUTENTICACIÓN X-Org-Id  (Actividad Semana 5)
//  Header X-Org-Id: org1  → Operaciones de Proveedor (Org1)
//  Header X-Org-Id: org2  → Operaciones de Distribuidor (Org2)
//  Sin header / valor inválido en rutas protegidas → 403 Forbidden
// =============================================================================

// Operaciones exclusivas de org1 (Proveedor): registrar, actualizar, transferir
const soloOrg1 = (req, res, next) => {
  const orgId = req.headers['x-org-id'];
  if (orgId !== 'org1') {
    return res.status(403).json({
      error: 'Acceso denegado. Esta operación requiere X-Org-Id: org1 (Proveedor)',
      recibido: orgId || '(sin header)'
    });
  }
  next();
};

// Operaciones exclusivas de org2 (Distribuidor): confirmar recepción, entregar
const soloOrg2 = (req, res, next) => {
  const orgId = req.headers['x-org-id'];
  if (orgId !== 'org2') {
    return res.status(403).json({
      error: 'Acceso denegado. Esta operación requiere X-Org-Id: org2 (Distribuidor)',
      recibido: orgId || '(sin header)'
    });
  }
  next();
};

// =============================================================================
//  RUTAS API REST
// =============================================================================

// GET /health — sin autenticación (monitoreo)
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    org: MSP_ID,
    canal: CHANNEL,
    chaincode: CHAINCODE,
    timestamp: new Date().toISOString()
  });
});

// GET /productos — sin autenticación (lectura pública)
app.get('/productos', wrap(async (req, res) => {
  const result = await contract.evaluateTransaction('ConsultarTodos');
  res.json(decode(result) || []);
}));

// GET /productos/estado/:estado — sin autenticación
app.get('/productos/estado/:estado', wrap(async (req, res) => {
  const { estado } = req.params;
  const result = await contract.evaluateTransaction('ConsultarPorEstado', estado.toUpperCase());
  res.json(decode(result) || []);
}));

// GET /productos/:id — sin autenticación
app.get('/productos/:id', wrap(async (req, res) => {
  const result = await contract.evaluateTransaction('LeerProducto', req.params.id);
  res.json(decode(result));
}));

// GET /productos/:id/historial — sin autenticación
app.get('/productos/:id/historial', wrap(async (req, res) => {
  const result = await contract.evaluateTransaction('ObtenerHistorial', req.params.id);
  res.json(decode(result) || []);
}));

// POST /productos — solo org1 (Proveedor registra)
app.post('/productos', soloOrg1, wrap(async (req, res) => {
  const { id, nombre, cantidad, unidad, origen, destino, temperatura } = req.body;
  if (!id || !nombre || !cantidad || !unidad || !origen || !destino) {
    return res.status(400).json({
      error: 'Campos requeridos: id, nombre, cantidad, unidad, origen, destino'
    });
  }
  await contract.submitTransaction(
    'RegistrarProducto',
    id, nombre, String(cantidad), unidad, origen, destino, temperatura || 'N/A'
  );
  res.status(201).json({ message: `Producto ${id} registrado en el ledger`, timestamp: new Date().toISOString() });
}));

// PUT /productos/:id/transferir — solo org1 (Proveedor transfiere)
app.put('/productos/:id/transferir', soloOrg1, wrap(async (req, res) => {
  const { nuevoPropietario, detalle } = req.body;
  if (!nuevoPropietario || !detalle) {
    return res.status(400).json({ error: 'Campos requeridos: nuevoPropietario, detalle' });
  }
  await contract.submitTransaction('TransferirProducto', req.params.id, nuevoPropietario, detalle);
  res.json({ message: `Producto ${req.params.id} transferido a ${nuevoPropietario}` });
}));

// PUT /productos/:id/confirmar — solo org2 (Distribuidor confirma)
app.put('/productos/:id/confirmar', soloOrg2, wrap(async (req, res) => {
  const { temperaturaRecibido, temperatura, detalle } = req.body;
  const temp = temperaturaRecibido || temperatura || 'N/A';
  await contract.submitTransaction(
    'ConfirmarRecepcion',
    req.params.id,
    temp,
    detalle || 'Recepción confirmada'
  );
  res.json({ message: `Recepción del producto ${req.params.id} confirmada` });
}));

// PUT /productos/:id/cantidad — solo org1 (propietario actualiza)
app.put('/productos/:id/cantidad', soloOrg1, wrap(async (req, res) => {
  const { cantidad, motivo } = req.body;
  if (!cantidad || !motivo) {
    return res.status(400).json({ error: 'Campos requeridos: cantidad, motivo' });
  }
  await contract.submitTransaction('ActualizarCantidad', req.params.id, String(cantidad), motivo);
  res.json({ message: `Cantidad del producto ${req.params.id} actualizada a ${cantidad}` });
}));

// PUT /productos/:id/entregar — solo org2 (Distribuidor entrega)
app.put('/productos/:id/entregar', soloOrg2, wrap(async (req, res) => {
  const { clienteFinal, evidencia } = req.body;
  if (!clienteFinal || !evidencia) {
    return res.status(400).json({ error: 'Campos requeridos: clienteFinal, evidencia' });
  }
  await contract.submitTransaction('MarcarEntregado', req.params.id, clienteFinal, evidencia);
  res.json({ message: `Producto ${req.params.id} marcado como ENTREGADO a ${clienteFinal}` });
}));

// ── MANEJO DE ERRORES ─────────────────────────────────────────────────────────
app.use((err, req, res, next) => {
  console.error('❌', err.message);
  const msg    = err.message || 'Error interno';
  const status = msg.includes('no encontrado') ? 404 : 500;
  res.status(status).json({ error: msg });
});

app.use((req, res) => res.status(404).json({ error: `Ruta no encontrada: ${req.method} ${req.url}` }));

// =============================================================================
//  ARRANQUE
// =============================================================================
async function main() {
  try {
    await conectarFabric();
    app.listen(PORT, () => {
      console.log(`🚀 API Supply Chain en http://localhost:${PORT}`);
      console.log('\n📋 Endpoints (GET sin auth | POST/PUT requieren X-Org-Id):');
      console.log('   GET    /health');
      console.log('   GET    /productos');
      console.log('   GET    /productos/:id');
      console.log('   GET    /productos/:id/historial');
      console.log('   GET    /productos/estado/:estado');
      console.log('   POST   /productos              [X-Org-Id: org1]');
      console.log('   PUT    /productos/:id/transferir [X-Org-Id: org1]');
      console.log('   PUT    /productos/:id/cantidad  [X-Org-Id: org1]');
      console.log('   PUT    /productos/:id/confirmar [X-Org-Id: org2]');
      console.log('   PUT    /productos/:id/entregar  [X-Org-Id: org2]\n');
    });
  } catch (err) {
    console.error('❌ Error conectando a Fabric:', err);
    process.exit(1);
  }
}

main();

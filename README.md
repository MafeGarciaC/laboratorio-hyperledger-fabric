# Laboratorio Hyperledger Fabric — Semanas 4 y 5
## Capstone: Chaincode supplycc + API REST Supply Chain

**Estudiante:** MafeGarciaC
**Tecnologías:** Hyperledger Fabric 2.5 · Go 1.21 · Node.js 18 · CouchDB · Docker

---

## 📦 Estructura del proyecto

```
├── chaincode/
│   ├── supplycc.go       ← Smart contract (10 funciones Supply Chain)
│   ├── main_caas.go      ← Entry point (modo estándar + CaaS)
│   ├── go.mod
│   └── go.sum
├── api/
│   ├── app.js            ← API REST Express (9 endpoints)
│   └── package.json
└── scripts/
    ├── deploy-supplycc.sh   ← Deploy completo (10 pasos)
    ├── flujo-completo.sh    ← Prueba del flujo Supply Chain
    └── start-supplycc.sh    ← Reinicio del chaincode server
```

---

## 🔗 Funciones del Chaincode

| Función | Descripción |
|---------|-------------|
| `InitLedger` | Inicializa con 3 productos de ejemplo |
| `RegistrarProducto` | Org1 registra nuevo lote |
| `ActualizarCantidad` | Actualiza cantidad con validación de propietario |
| `TransferirProducto` | Cambia propietario (Org1 → Org2) |
| `ConfirmarRecepcion` | Org2 confirma recepción |
| `MarcarEntregado` | Marca entrega al cliente final |
| `LeerProducto` | Consulta estado actual (World State) |
| `ObtenerHistorial` | Historial inmutable del ledger |
| `ConsultarTodos` | Rich query — todos los productos |
| `ConsultarPorEstado` | Rich query — filtrar por estado |

## 📊 Estados del ciclo de vida
```
REGISTRADO → EN_TRANSITO → RECIBIDO → ENTREGADO
```

## 🚀 API REST Endpoints

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/health` | Estado de la conexión |
| GET | `/productos` | Todos los productos |
| GET | `/productos/:id` | Producto por ID |
| GET | `/productos/:id/historial` | Historial inmutable |
| GET | `/productos/estado/:estado` | Filtrar por estado |
| POST | `/productos` | Registrar nuevo producto |
| PUT | `/productos/:id/transferir` | Transferir a Org2 |
| PUT | `/productos/:id/confirmar` | Confirmar recepción |
| PUT | `/productos/:id/cantidad` | Actualizar cantidad |
| PUT | `/productos/:id/entregar` | Marcar como entregado |

## 🏗️ Prerrequisitos

- WSL2 Ubuntu con Docker Desktop
- Hyperledger Fabric 2.5 (fabric-samples en `~/fabric/`)
- Go 1.21, Node.js 18
- Canal `supplychannel` activo (Semana 3)

## 📦 Productos de ejemplo (Colombia Caribe)

- **PROD-001**: Cacao Orgánico — Tumaco, Colombia
- **PROD-002**: Café Especial Sucre — Sincelejo, Sucre
- **PROD-003**: Aguacate Hass — Cauca, Colombia

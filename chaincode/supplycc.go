package main

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// =============================================================================
//  supplycc.go — Chaincode de Supply Chain Management
//  Laboratorio Capstone Semanas 4 + 5 | Jaider Reyes Herazo
//  Hyperledger Fabric 2.5 — Canal: supplychannel
// =============================================================================

// Producto representa un lote en la cadena de suministro
type Producto struct {
	ID          string `json:"id"`
	Nombre      string `json:"nombre"`
	Cantidad    int    `json:"cantidad"`
	Unidad      string `json:"unidad"`
	Propietario string `json:"propietario"`
	Estado      string `json:"estado"`
	Origen      string `json:"origen"`
	Destino     string `json:"destino"`
	Temperatura string `json:"temperatura"`
	Timestamp   string `json:"timestamp"`
	TxID        string `json:"txId"`
}

// EventoHistorial registra cada cambio de estado en el ledger
type EventoHistorial struct {
	TxID      string `json:"txId"`
	Timestamp string `json:"timestamp"`
	Estado    string `json:"estado"`
	Actor     string `json:"actor"`
	Detalle   string `json:"detalle"`
}

// SupplyContract implementa ContractInterface
type SupplyContract struct {
	contractapi.Contract
}

// =============================================================================
//  FUNCIÓN 1 — InitLedger
//  Inicializa el ledger con productos de ejemplo del Caribe colombiano
// =============================================================================
func (sc *SupplyContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	productos := []Producto{
		{
			ID: "PROD-001", Nombre: "Cacao Orgánico", Cantidad: 500,
			Unidad: "kg", Propietario: "Org1MSP", Estado: "REGISTRADO",
			Origen: "Tumaco, Colombia", Destino: "Medellín Hub",
			Temperatura: "18°C", Timestamp: time.Now().Format(time.RFC3339),
			TxID: ctx.GetStub().GetTxID(),
		},
		{
			ID: "PROD-002", Nombre: "Café Especial Sucre", Cantidad: 200,
			Unidad: "kg", Propietario: "Org1MSP", Estado: "REGISTRADO",
			Origen: "Sincelejo, Sucre", Destino: "Bogotá DC",
			Temperatura: "20°C", Timestamp: time.Now().Format(time.RFC3339),
			TxID: ctx.GetStub().GetTxID(),
		},
		{
			ID: "PROD-003", Nombre: "Aguacate Hass", Cantidad: 1000,
			Unidad: "kg", Propietario: "Org1MSP", Estado: "REGISTRADO",
			Origen: "Cauca, Colombia", Destino: "Cartagena Puerto",
			Temperatura: "12°C", Timestamp: time.Now().Format(time.RFC3339),
			TxID: ctx.GetStub().GetTxID(),
		},
	}

	for _, p := range productos {
		pJSON, err := json.Marshal(p)
		if err != nil {
			return fmt.Errorf("error serializando %s: %v", p.ID, err)
		}
		if err := ctx.GetStub().PutState(p.ID, pJSON); err != nil {
			return fmt.Errorf("error guardando %s: %v", p.ID, err)
		}
	}
	return nil
}

// =============================================================================
//  FUNCIÓN 2 — RegistrarProducto
//  El Proveedor (Org1) registra un nuevo lote en el ledger
// =============================================================================
func (sc *SupplyContract) RegistrarProducto(
	ctx contractapi.TransactionContextInterface,
	id, nombre string, cantidad int,
	unidad, origen, destino, temperatura string,
) error {
	existe, err := sc.existeProducto(ctx, id)
	if err != nil {
		return err
	}
	if existe {
		return fmt.Errorf("el producto %s ya existe en el ledger", id)
	}

	clientID, _ := ctx.GetClientIdentity().GetMSPID()

	producto := Producto{
		ID: id, Nombre: nombre, Cantidad: cantidad,
		Unidad: unidad, Propietario: clientID, Estado: "REGISTRADO",
		Origen: origen, Destino: destino, Temperatura: temperatura,
		Timestamp: time.Now().Format(time.RFC3339),
		TxID:      ctx.GetStub().GetTxID(),
	}

	pJSON, err := json.Marshal(producto)
	if err != nil {
		return err
	}

	ctx.GetStub().SetEvent("ProductoRegistrado", pJSON)
	return ctx.GetStub().PutState(id, pJSON)
}

// =============================================================================
//  FUNCIÓN 3 — TransferirProducto
//  Cambia propietario y estado cuando hay transferencia entre orgs
// =============================================================================
func (sc *SupplyContract) TransferirProducto(
	ctx contractapi.TransactionContextInterface,
	id, nuevoPropietario, detalle string,
) error {
	producto, err := sc.LeerProducto(ctx, id)
	if err != nil {
		return err
	}

	if producto.Estado == "ENTREGADO" {
		return fmt.Errorf("el producto %s ya fue entregado y no puede transferirse", id)
	}

	evento := EventoHistorial{
		TxID: ctx.GetStub().GetTxID(), Timestamp: time.Now().Format(time.RFC3339),
		Estado: "EN_TRANSITO", Actor: producto.Propietario, Detalle: detalle,
	}
	sc.guardarHistorial(ctx, id, evento)

	producto.Propietario = nuevoPropietario
	producto.Estado = "EN_TRANSITO"
	producto.TxID = ctx.GetStub().GetTxID()
	producto.Timestamp = time.Now().Format(time.RFC3339)

	pJSON, err := json.Marshal(producto)
	if err != nil {
		return err
	}

	ctx.GetStub().SetEvent("ProductoTransferido", pJSON)
	return ctx.GetStub().PutState(id, pJSON)
}

// =============================================================================
//  FUNCIÓN 4 — ConfirmarRecepcion
//  El Distribuidor (Org2) confirma que recibió el lote
// =============================================================================
func (sc *SupplyContract) ConfirmarRecepcion(
	ctx contractapi.TransactionContextInterface,
	id, temperaturaRecibido, detalle string,
) error {
	producto, err := sc.LeerProducto(ctx, id)
	if err != nil {
		return err
	}

	if producto.Estado != "EN_TRANSITO" {
		return fmt.Errorf("el producto %s no está EN_TRANSITO (estado: %s)", id, producto.Estado)
	}

	clientID, _ := ctx.GetClientIdentity().GetMSPID()

	evento := EventoHistorial{
		TxID: ctx.GetStub().GetTxID(), Timestamp: time.Now().Format(time.RFC3339),
		Estado: "RECIBIDO", Actor: clientID,
		Detalle: fmt.Sprintf("%s — Temp recibido: %s", detalle, temperaturaRecibido),
	}
	sc.guardarHistorial(ctx, id, evento)

	producto.Estado = "RECIBIDO"
	producto.Temperatura = temperaturaRecibido
	producto.TxID = ctx.GetStub().GetTxID()
	producto.Timestamp = time.Now().Format(time.RFC3339)

	pJSON, _ := json.Marshal(producto)
	ctx.GetStub().SetEvent("RecepcionConfirmada", pJSON)
	return ctx.GetStub().PutState(id, pJSON)
}

// =============================================================================
//  FUNCIÓN 5 — ActualizarCantidad
//  FUNCIÓN MODIFICADA EN EL LABORATORIO — incluye validación de propietario
//  y registro en el historial
// =============================================================================
func (sc *SupplyContract) ActualizarCantidad(
	ctx contractapi.TransactionContextInterface,
	id string, nuevaCantidad int, motivo string,
) error {
	producto, err := sc.LeerProducto(ctx, id)
	if err != nil {
		return err
	}

	// Validar que quien actualiza es el propietario actual
	clientID, _ := ctx.GetClientIdentity().GetMSPID()
	if clientID != producto.Propietario {
		return fmt.Errorf("solo el propietario (%s) puede actualizar la cantidad — llamante: %s",
			producto.Propietario, clientID)
	}

	// Validar que la cantidad sea positiva
	if nuevaCantidad <= 0 {
		return fmt.Errorf("la cantidad debe ser mayor a 0, recibido: %d", nuevaCantidad)
	}

	// Registrar en historial
	evento := EventoHistorial{
		TxID:      ctx.GetStub().GetTxID(),
		Timestamp: time.Now().Format(time.RFC3339),
		Estado:    producto.Estado,
		Actor:     clientID,
		Detalle:   fmt.Sprintf("Cantidad actualizada de %d a %d %s — Motivo: %s", producto.Cantidad, nuevaCantidad, producto.Unidad, motivo),
	}
	sc.guardarHistorial(ctx, id, evento)

	cantidadAnterior := producto.Cantidad
	producto.Cantidad = nuevaCantidad
	producto.TxID = ctx.GetStub().GetTxID()
	producto.Timestamp = time.Now().Format(time.RFC3339)

	pJSON, err := json.Marshal(producto)
	if err != nil {
		return err
	}

	// Emitir evento con información de la actualización
	eventoData := map[string]interface{}{
		"id":               id,
		"cantidadAnterior": cantidadAnterior,
		"cantidadNueva":    nuevaCantidad,
		"unidad":           producto.Unidad,
		"motivo":           motivo,
		"actor":            clientID,
	}
	eventoJSON, _ := json.Marshal(eventoData)
	ctx.GetStub().SetEvent("CantidadActualizada", eventoJSON)

	return ctx.GetStub().PutState(id, pJSON)
}

// =============================================================================
//  FUNCIÓN 6 — MarcarEntregado (FUNCIÓN NUEVA — agregada en el laboratorio)
//  Marca un producto como entregado al cliente final
//  Esta es la función nueva que los estudiantes deben implementar
// =============================================================================
func (sc *SupplyContract) MarcarEntregado(
	ctx contractapi.TransactionContextInterface,
	id, clienteFinal, evidencia string,
) error {
	producto, err := sc.LeerProducto(ctx, id)
	if err != nil {
		return err
	}

	// Solo productos RECIBIDOS pueden marcarse como ENTREGADOS
	if producto.Estado != "RECIBIDO" {
		return fmt.Errorf("solo productos RECIBIDOS pueden marcarse como entregados (estado actual: %s)", producto.Estado)
	}

	clientID, _ := ctx.GetClientIdentity().GetMSPID()

	evento := EventoHistorial{
		TxID:      ctx.GetStub().GetTxID(),
		Timestamp: time.Now().Format(time.RFC3339),
		Estado:    "ENTREGADO",
		Actor:     clientID,
		Detalle:   fmt.Sprintf("Entregado a: %s — Evidencia: %s", clienteFinal, evidencia),
	}
	sc.guardarHistorial(ctx, id, evento)

	producto.Estado = "ENTREGADO"
	producto.Propietario = clienteFinal
	producto.TxID = ctx.GetStub().GetTxID()
	producto.Timestamp = time.Now().Format(time.RFC3339)

	pJSON, err := json.Marshal(producto)
	if err != nil {
		return err
	}

	ctx.GetStub().SetEvent("ProductoEntregado", pJSON)
	return ctx.GetStub().PutState(id, pJSON)
}

// =============================================================================
//  FUNCIÓN 7 — LeerProducto
//  Consulta el estado actual de un producto (World State)
// =============================================================================
func (sc *SupplyContract) LeerProducto(
	ctx contractapi.TransactionContextInterface, id string,
) (*Producto, error) {
	pJSON, err := ctx.GetStub().GetState(id)
	if err != nil {
		return nil, fmt.Errorf("error leyendo %s: %v", id, err)
	}
	if pJSON == nil {
		return nil, fmt.Errorf("producto %s no encontrado en el ledger", id)
	}
	var producto Producto
	if err := json.Unmarshal(pJSON, &producto); err != nil {
		return nil, err
	}
	return &producto, nil
}

// =============================================================================
//  FUNCIÓN 8 — ObtenerHistorial
//  Retorna el historial completo de transacciones de un producto
// =============================================================================
func (sc *SupplyContract) ObtenerHistorial(
	ctx contractapi.TransactionContextInterface, id string,
) ([]*EventoHistorial, error) {
	iterator, err := ctx.GetStub().GetHistoryForKey(id)
	if err != nil {
		return nil, err
	}
	defer iterator.Close()

	var historial []*EventoHistorial
	for iterator.HasNext() {
		respuesta, err := iterator.Next()
		if err != nil {
			return nil, err
		}
		var producto Producto
		if err := json.Unmarshal(respuesta.Value, &producto); err != nil {
			continue
		}
		evento := &EventoHistorial{
			TxID:      respuesta.TxId,
			Timestamp: time.Unix(respuesta.Timestamp.Seconds, 0).Format(time.RFC3339),
			Estado:    producto.Estado,
			Actor:     producto.Propietario,
			Detalle:   fmt.Sprintf("Cantidad: %d %s | Temperatura: %s", producto.Cantidad, producto.Unidad, producto.Temperatura),
		}
		historial = append(historial, evento)
	}
	return historial, nil
}

// =============================================================================
//  FUNCIÓN 9 — ConsultarTodos (Rich Query — requiere CouchDB)
// =============================================================================
func (sc *SupplyContract) ConsultarTodos(
	ctx contractapi.TransactionContextInterface,
) ([]*Producto, error) {
	query := `{"selector":{"id":{"$gt":""}},"sort":[{"timestamp":"desc"}]}`
	return sc.ejecutarRichQuery(ctx, query)
}

// =============================================================================
//  FUNCIÓN 10 — ConsultarPorEstado (Rich Query — requiere CouchDB)
// =============================================================================
func (sc *SupplyContract) ConsultarPorEstado(
	ctx contractapi.TransactionContextInterface, estado string,
) ([]*Producto, error) {
	estados := map[string]bool{
		"REGISTRADO": true, "EN_TRANSITO": true,
		"RECIBIDO": true, "ENTREGADO": true,
	}
	if !estados[estado] {
		return nil, fmt.Errorf("estado inválido: %s. Válidos: REGISTRADO, EN_TRANSITO, RECIBIDO, ENTREGADO", estado)
	}
	query := fmt.Sprintf(`{"selector":{"estado":"%s"}}`, estado)
	return sc.ejecutarRichQuery(ctx, query)
}

// =============================================================================
//  HELPERS INTERNOS
// =============================================================================
func (sc *SupplyContract) existeProducto(ctx contractapi.TransactionContextInterface, id string) (bool, error) {
	data, err := ctx.GetStub().GetState(id)
	if err != nil {
		return false, err
	}
	return data != nil, nil
}

func (sc *SupplyContract) guardarHistorial(
	ctx contractapi.TransactionContextInterface,
	productoID string, evento EventoHistorial,
) {
	key, _ := ctx.GetStub().CreateCompositeKey("historial", []string{productoID, evento.TxID})
	eJSON, _ := json.Marshal(evento)
	ctx.GetStub().PutState(key, eJSON)
}

func (sc *SupplyContract) ejecutarRichQuery(
	ctx contractapi.TransactionContextInterface, query string,
) ([]*Producto, error) {
	iterator, err := ctx.GetStub().GetQueryResult(query)
	if err != nil {
		return nil, err
	}
	defer iterator.Close()
	var productos []*Producto
	for iterator.HasNext() {
		resp, err := iterator.Next()
		if err != nil {
			return nil, err
		}
		var p Producto
		if err := json.Unmarshal(resp.Value, &p); err != nil {
			continue
		}
		productos = append(productos, &p)
	}
	return productos, nil
}

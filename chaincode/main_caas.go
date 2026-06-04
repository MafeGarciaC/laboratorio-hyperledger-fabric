package main

import (
	"fmt"
	"os"

	"github.com/hyperledger/fabric-chaincode-go/shim"
	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// main soporta modo estandar y modo CaaS (Chaincode as a Service)
func main() {
	cc, err := contractapi.NewChaincode(&SupplyContract{})
	if err != nil {
		fmt.Printf("Error creando chaincode: %v\n", err)
		return
	}

	ccID := os.Getenv("CHAINCODE_SERVER_CCID")
	ccAddr := os.Getenv("CHAINCODE_SERVER_ADDRESS")

	if ccID != "" && ccAddr != "" {
		server := &shim.ChaincodeServer{
			CCID:     ccID,
			Address:  ccAddr,
			CC:       cc,
			TLSProps: shim.TLSProperties{Disabled: true},
		}
		fmt.Printf("CaaS server en %s (CCID: %s)\n", ccAddr, ccID)
		if err := server.Start(); err != nil {
			fmt.Printf("Error CaaS: %v\n", err)
		}
	} else {
		if err := cc.Start(); err != nil {
			fmt.Printf("Error iniciando chaincode: %v\n", err)
		}
	}
}

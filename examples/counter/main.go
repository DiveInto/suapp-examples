package main

import (
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/flashbots/suapp-examples/framework"
	"github.com/sirupsen/logrus"
)

func main() {

	fr := framework.New(framework.WithL1())
	contract := fr.Suave.DeployContract("counter.sol/Counter.json")

	// new dataRecord inputs
	uint256AbiType, _ := abi.NewType("uint256", "", nil)
	numEncoded, err := abi.Arguments{{Type: uint256AbiType}}.Pack(big.NewInt(int64(123)))
	if err != nil {
		panic(err)
	}

	receipt := contract.SendConfidentialRequest("setNumber", nil, numEncoded)

	hintEvent := &NumberSetEvent{}
	if err := hintEvent.Unpack(receipt.Logs[0]); err != nil {
		panic(err)
	}

	fmt.Println("NumSet event num:", hintEvent.Number)
}

var (
	numSetEventABI abi.Event
)

func init() {
	artifact, _ := framework.ReadArtifact("counter.sol/Counter.json")
	numSetEventABI = artifact.Abi.Events["NumberSet"]
}

type NumberSetEvent struct {
	Number int
}

func (h *NumberSetEvent) Unpack(log *types.Log) error {
	res, err := numSetEventABI.ParseLog(log)
	if err != nil {
		return err
	}
	logrus.Printf("res: %+v", res)

	number, ok := res["number"].(*big.Int)
	if !ok {
		return fmt.Errorf("number is not an int")
	}
	h.Number = int(number.Int64())

	return nil
}

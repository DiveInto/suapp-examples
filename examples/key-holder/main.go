package main

import (
	"fmt"
	"math/big"
	"os"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/flashbots/suapp-examples/framework"
	"github.com/sirupsen/logrus"
)

func main() {
	if os.Getenv("STEP") == "2" {
		step2()
	} else {
		step1()
	}
}

var contract *framework.Contract

func step1() {
	fr := framework.New(framework.WithL1())
	contract = fr.Suave.DeployContract("KeyHolder.sol/KeyHolder.json")

	// 1. init
	receipt := contract.SendConfidentialRequest("offchainInitPrivateKey", nil, nil)

	showAdxEvent := &ShowAdxEvent{}
	if err := showAdxEvent.Unpack(receipt.Logs[0]); err != nil {
		panic(err)
	}
	fmt.Println("ShowAdx Event:", showAdxEvent.Adx)
}

func step2() {
	contractAddress := common.HexToAddress("0x73dE34F94162ED311DA06d23ed4aD5eA9E00FfEe")

	fr := framework.New(framework.WithL1())
	contract := fr.NewContract(contractAddress, "KeyHolder.sol/KeyHolder.json")

	receipt := contract.SendConfidentialRequest("offchain", nil, nil)

	txnSigEvent := &TxnSignatureEvent{}
	if err := txnSigEvent.Unpack(receipt.Logs[0]); err != nil {
		panic(err)
	}
	fmt.Printf("TxnSig Event: %+v", txnSigEvent)
}

var (
	// abi abi.ABI
	// mArtifact *framework.Artifact

	showAdxEventABI      abi.Event
	txnSignatureEventABI abi.Event
)

func init() {
	artifact, _ := framework.ReadArtifact("KeyHolder.sol/KeyHolder.json")

	// abi = artifact.Abi

	txnSignatureEventABI = artifact.Abi.Events["TxnSignature"]
	showAdxEventABI = artifact.Abi.Events["ShowAdx"]
}

type TxnSignatureEvent struct {
	Hash string
	V1   uint8
	V    *big.Int
	R    string
	S    string
}

func (h *TxnSignatureEvent) Unpack(log *types.Log) error {
	res, err := txnSignatureEventABI.ParseLog(log)
	if err != nil {
		return err
	}
	logrus.Printf("res: %+v", res)

	h.Hash, _ = res["hash"].(string)
	h.V1, _ = res["v1"].(uint8)
	h.V, _ = res["v"].(*big.Int)
	h.R, _ = res["r"].(string)
	h.S, _ = res["s"].(string)

	return nil
}

type ShowAdxEvent struct {
	Adx common.Address
}

func (h *ShowAdxEvent) Unpack(log *types.Log) error {
	res, err := showAdxEventABI.ParseLog(log)
	if err != nil {
		return err
	}
	logrus.Printf("res: %+v", res)

	adx, ok := res["adx"].(common.Address)
	if !ok {
		return fmt.Errorf("adx is not string")
	}
	h.Adx = adx

	return nil
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "suave-std/Suapp.sol";
import "suave-std/Context.sol";
import "suave-std/Transactions.sol";
import "suave-std/suavelib/Suave.sol";
import "suave-std/crypto/Secp256k1.sol";
import "solady/src/utils/LibString.sol";
import "solady/src/utils/JSONParserLib.sol";
import "forge-std/console.sol";

contract KeyHolder is Suapp {
    using JSONParserLib for *;

    Suave.DataId signingKeyRecord;
    string public PRIVATE_KEY = "KEY";
    address public Adx;

    event TxnSignature(string hash, uint8 v1, uint256 v, string r, string s);
    event ShowAdx(address adx);
    event ShowStr(string str);

    function onchain() public emitOffchainLogs {}

    function offchain() public returns (bytes memory) {
        bytes memory signingKey = Suave.confidentialRetrieve(signingKeyRecord, PRIVATE_KEY);
        // string memory signingKey = "0x91ab9a7e53c220e6210460b65a7a3bb2ca181412a8a7b43ff336b3df1737ce12";

        Transactions.EIP155Request memory txnWithToAddress = Transactions.EIP155Request({
            to: address(0x00000000000000000000000000000000DeaDBeef),
            gas: 1000000,
            gasPrice: 1 gwei,
            value: 1,
            nonce: 0,
            // nonce: 94,
            data: bytes(""),
            chainId: 33626250
        });

        Transactions.EIP155 memory txn = Transactions.signTxn(txnWithToAddress, string(signingKey));

        bytes memory rlp = Transactions.encodeRLP(txn);
        bytes memory hash = abi.encodePacked(keccak256(rlp));

        emit TxnSignature(
            LibString.toHexString(uint256(bytesToBytes32(hash))),
            uint8(txn.v),
            txn.v,
            LibString.toHexString(uint256(txn.r)),
            LibString.toHexString(uint256(txn.s))
        );

        sendTx(rlp);

        return abi.encodeWithSelector(this.onchain.selector);
    }

    function sendTx(bytes memory txBytes) internal returns (JSONParserLib.Item memory) {
        // function sendTx(bytes memory txBytes) internal {
        Suave.HttpRequest memory request;
        request.method = "POST";
        request.url = "https://rpc.toliman.suave.flashbots.net";
        request.headers = new string[](1);
        request.headers[0] = "Content-Type: application/json";

        bytes memory body = abi.encodePacked(
            '{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["',
            LibString.toHexString(txBytes),
            '"],"id":1}'
        );
        request.body = body;

        console.log(string(body));
        emit ShowStr(string(body));

        bytes memory output = Suave.doHTTPRequest(request);

        console.log(string(output));

        JSONParserLib.Item memory item = string(output).parse();
        return item.at('"result"');
    }

    function offchainInitPrivateKey() public returns (bytes memory) {
        string memory randPrivateKey = Suave.privateKeyGen(Suave.CryptoSignature.SECP256);

        address[] memory peekers = new address[](1);
        peekers[0] = address(this);
        Suave.DataRecord memory record = Suave.newDataRecord(0, peekers, peekers, "private_key");

        Suave.confidentialStore(record.id, PRIVATE_KEY, bytes(randPrivateKey));

        address adx = Secp256k1.deriveAddress(randPrivateKey);
        emit ShowAdx(adx);

        return abi.encodeWithSelector(this.updateKeyAndAdxOnchain.selector, record.id, adx);
    }

    function updateKeyAndAdxOnchain(Suave.DataId _signingKeyRecord, address adx) public emitOffchainLogs {
        signingKeyRecord = _signingKeyRecord;
        Adx = adx;
    }

    function bytesToBytes32(bytes memory source) public pure returns (bytes32 result) {
        if (source.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }
}

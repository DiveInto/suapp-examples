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

contract BlindlyCash is Suapp {
    using JSONParserLib for *;

    Suave.DataId recordDataId;

    struct PubKey {
        bytes e;
        uint256 N;
    }

    string public COIN_MASTER_KEY = "COIN_MASTER_KEY";
    string public SIGN_D_KEY = "SIGN_D_KEY";

    address public CoinMasterAdx;
    PubKey public pubKey;

    event TxnSignature(string hash, uint8 v1, uint256 v, string r, string s);
    event ShowAdx(address adx);
    event ShowStr(string str);
    
    event Deposit(address adx, uint256 amount, bytes signature);

    function onchain() public emitOffchainLogs {}

    function offchain() public returns (bytes memory) {
        bytes memory signingKey = Suave.confidentialRetrieve(recordDataId, COIN_MASTER_KEY);

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

    function offchainInit() public returns (bytes memory) {
        // 1. gen a random private key as coin master
        string memory randPrivateKey = Suave.privateKeyGen(Suave.CryptoSignature.SECP256);

        address[] memory peekers = new address[](1);
        peekers[0] = address(this);
        Suave.DataRecord memory record = Suave.newDataRecord(0, peekers, peekers, "private_key");

        Suave.confidentialStore(record.id, COIN_MASTER_KEY, bytes(randPrivateKey));

        address adx = Secp256k1.deriveAddress(randPrivateKey);
        emit ShowAdx(adx);

        // 2. get RSA keypair from CCR: (e, d, N)
        bytes memory keypairData = Context.confidentialInputs();
        (bytes e, bytes d, uint256 N) = abi.decode(keypairData, (bytes, bytes, uint256));
        Suave.confidentialStore(record.id, SIGN_D_KEY, d);

        //todo add validation for Pub&Prv key pair

        return abi.encodeWithSelector(this.onchainInit.selector, record.id, adx, e, N);
    }

    function onchainInit(Suave.DataId _recordDataId, address coinMasterAdx, bytes e, uint256 N)
        public
        emitOffchainLogs
    {
        recordDataId = _recordDataId;
        CoinMasterAdx = coinMasterAdx;
        pubKey = PubKey({e: e, N: N});
    }

    map(bytes32=>bool) usedBlindMsgMap;

    function depositOffline(bytes blindMessage) public payable {
        require(msg.value == 0.01 ether, "only support deposit 0.01 eth");

        // sign this msg & send sig to onchain func
        bytes memory d = Suave.confidentialRetrieve(recordDataId, SIGN_D_KEY);

        uint blindMsgSig = modExp(blindMessage, d, pubKey.N);

        return abi.encodeWithSelector(this.depositOnline.selector, blindMessage, blindMsgSig);
    }

    // ? how to make sure this is only called by our offline function? 
    function depositOnline(bytes blindMessage, bytes signature) public payable {
        require(msg.value == 0.01 ether, "only support deposit 0.01 eth");
        require(usedBlindMsgMap[keccak256(blindMessage)] == false, "blind message already used");

        usedBlindMsgMap[keccak256(blindMessage)] = true;

        emit Deposit(msg.sender, msg.value, signature);
    }

    // offline so redeem note won't leak
    function redeemOffline() public payable {}

    function redeemOnline(uint256 amount) public payable {}

    function bytesToBytes32(bytes memory source) public pure returns (bytes32 result) {
        if (source.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function modExp(uint256 _b, uint256 _e, uint256 _m) public view returns (uint256 result) {
        assembly {
            // Free memory pointer
            let pointer := mload(0x40)

            // Define length of base, exponent and modulus. 0x20 == 32 bytes
            mstore(pointer, 0x20)
            mstore(add(pointer, 0x20), 0x20)
            mstore(add(pointer, 0x40), 0x20)

            // Define variables base, exponent and modulus
            mstore(add(pointer, 0x60), _b)
            mstore(add(pointer, 0x80), _e)
            mstore(add(pointer, 0xa0), _m)

            // Store the result
            let value := mload(0xc0)

            // Call the precompiled contract 0x05 = bigModExp
            if iszero(staticcall(not(0), 0x05, pointer, 0xc0, value, 0x20)) {
                revert(0, 0)
            }

            result := mload(value)
        }
    }
}

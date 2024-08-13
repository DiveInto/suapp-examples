// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "suave-std/suavelib/Suave.sol";
import {Suapp} from "suave-std/Suapp.sol";

contract Counter is Suapp {
    uint256 public number;

    event NumberSet(uint256 number);

    // modifier confidential() {
    //     require(Suave.isConfidential(), "function must be called confidentially");
    //     _;
    // }

    function onSetNumber(uint256 newNumber) external emitOffchainLogs {
        number = newNumber;
    }

    function setNumber() public confidential returns (bytes memory) {
        bytes memory data = Suave.confidentialInputs();
        uint256 newNumber = abi.decode(data, (uint256));
        emit NumberSet(newNumber);
        return abi.encodeWithSelector(this.onSetNumber.selector, newNumber);
    }
}

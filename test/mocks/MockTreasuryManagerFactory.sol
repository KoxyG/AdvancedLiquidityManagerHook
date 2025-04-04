// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ITreasuryManagerFactory} from "../../src/interface/ITreasuryManagerFactory.sol";

contract MockTreasuryManagerFactory is ITreasuryManagerFactory {
    function deployManager(address) external pure returns (address payable) {
        return payable(address(0x789));
    }
} 
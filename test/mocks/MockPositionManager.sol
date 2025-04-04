// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPositionManager} from "../../src/interface/IPositionManager.sol";
import {IFlaunch} from "../../src/interface/IFlaunch.sol";

contract MockPositionManager is IPositionManager {
    function flaunch(FlaunchParams calldata) external payable returns (address) {
        return address(0x123);
    }

    function flaunchContract() external view returns (IFlaunch) {
        return IFlaunch(address(0x456));
    }
} 
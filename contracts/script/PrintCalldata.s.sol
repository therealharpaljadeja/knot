// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { Executor } from "../src/Executor.sol";
import { FlashLoanHandler } from "../src/FlashLoanHandler.sol";
import { HandlerAaveV3 } from "../src/HandlerAaveV3.sol";
import { HandlerFunds } from "../src/HandlerFunds.sol";

/// @title Cross-language calldata fixture
/// @notice Prints deterministic round-trip calldata mirrored by web encoding tests.
contract PrintCalldata is Script {
    address internal constant USDC = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address internal constant FLASH = 0x1111111111111111111111111111111111111111;
    address internal constant AAVE = 0x2222222222222222222222222222222222222222;
    address internal constant FUNDS = 0x3333333333333333333333333333333333333333;
    address internal constant EXECUTOR = 0x4444444444444444444444444444444444444444;

    function run() external pure {
        address[] memory innerHandlers = new address[](3);
        innerHandlers[0] = AAVE;
        innerHandlers[1] = AAVE;
        innerHandlers[2] = FUNDS;
        bytes[] memory innerDatas = new bytes[](3);
        innerDatas[0] = abi.encodeCall(HandlerAaveV3.supply, (USDC, type(uint256).max));
        innerDatas[1] = abi.encodeCall(HandlerAaveV3.withdraw, (USDC, type(uint256).max));
        innerDatas[2] = abi.encodeCall(HandlerFunds.addFunds, (USDC, 500));

        address[] memory outerHandlers = new address[](1);
        outerHandlers[0] = FLASH;
        bytes[] memory outerDatas = new bytes[](1);
        outerDatas[0] = abi.encodeCall(
            FlashLoanHandler.flashLoan, (USDC, 1_000_000, innerHandlers, innerDatas)
        );

        bytes memory calldata_ = abi.encodeCall(Executor.execute, (outerHandlers, outerDatas));
        console2.log("executor", EXECUTOR);
        console2.logBytes(calldata_);
    }
}

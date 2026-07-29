// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IMoncomboRegistry
/// @notice Read interface shared by the executor and its handlers.
interface IMoncomboRegistry {
    function handlers(address handler) external view returns (bool);
    function callers(address caller) external view returns (address);
    function routers(address router) external view returns (bool);
}

/// @title IFlashLoanSimpleReceiver
/// @notice Callback required by the Aave v3 Pool.
interface IFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

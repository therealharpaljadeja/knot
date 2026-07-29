// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AaveV3Monad } from "@aave-address-book/AaveV3Monad.sol";
import { IPool } from "@aave-address-book/AaveV3.sol";
import { HandlerBase } from "./HandlerBase.sol";
import { IMoncomboRegistry, IFlashLoanSimpleReceiver } from "./interfaces/IMoncombo.sol";

/// @title Flash Loan Handler
/// @notice Opens an Aave v3 simple flash loan and executes whitelisted inner actions.
contract FlashLoanHandler is HandlerBase, IFlashLoanSimpleReceiver {
    using SafeERC20 for IERC20;

    IPool public constant POOL = AaveV3Monad.POOL;
    IMoncomboRegistry public immutable REGISTRY;

    error ArrayLengthMismatch();
    error HandlerNotAllowed(address handler);
    error UnauthorizedCallback(address caller);
    error InvalidInitiator(address initiator);
    error InnerActionFailed(uint256 index, bytes reason);

    constructor(address registry_) {
        REGISTRY = IMoncomboRegistry(registry_);
    }

    /// @notice Flash-borrows an asset and runs the supplied inner handler calls.
    function flashLoan(
        address asset,
        uint256 amount,
        address[] calldata innerHandlers,
        bytes[] calldata innerDatas
    ) external {
        if (innerHandlers.length != innerDatas.length) {
            revert ArrayLengthMismatch();
        }
        for (uint256 i; i < innerHandlers.length; ++i) {
            if (!REGISTRY.handlers(innerHandlers[i])) {
                revert HandlerNotAllowed(innerHandlers[i]);
            }
        }
        _trackToken(asset);
        POOL.flashLoanSimple(address(this), asset, amount, abi.encode(innerHandlers, innerDatas), 0);
    }

    /// @notice Aave callback that executes inner actions and approves exact repayment.
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        if (msg.sender != address(POOL)) revert UnauthorizedCallback(msg.sender);
        if (initiator != address(this)) revert InvalidInitiator(initiator);

        (address[] memory handlers, bytes[] memory datas) = abi.decode(params, (address[], bytes[]));
        if (handlers.length != datas.length) revert ArrayLengthMismatch();
        for (uint256 i; i < handlers.length; ++i) {
            address handler = handlers[i];
            if (!REGISTRY.handlers(handler)) revert HandlerNotAllowed(handler);
            (bool success, bytes memory result) = handler.delegatecall(datas[i]);
            if (!success) revert InnerActionFailed(i, result);
        }

        IERC20(asset).forceApprove(address(POOL), amount + premium);
        _trackApproval(asset, address(POOL));
        _trackToken(asset);
        return true;
    }
}

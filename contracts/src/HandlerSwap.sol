// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { HandlerBase } from "./HandlerBase.sol";
import { IMoncomboRegistry } from "./interfaces/IMoncombo.sol";

/// @title Swap Handler
/// @notice Calls an allowlisted router with venue-specific calldata and checks exact-input output.
contract HandlerSwap is HandlerBase {
    using SafeERC20 for IERC20;
    using Address for address;

    IMoncomboRegistry public immutable REGISTRY;

    error RouterNotAllowed(address router);
    error InsufficientOutput(uint256 received, uint256 minimum);

    constructor(address registry_) {
        REGISTRY = IMoncomboRegistry(registry_);
    }

    /// @notice Executes an exact-input swap through an allowlisted router.
    /// @dev `routeData` is the router's complete calldata. It must send output to address(this).
    function swapExactIn(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        bytes calldata routeData
    ) external returns (uint256 amountOut) {
        if (!REGISTRY.routers(router)) revert RouterNotAllowed(router);
        uint256 resolved = _resolveAmount(tokenIn, amountIn);
        _trackToken(tokenIn);
        _trackToken(tokenOut);

        uint256 beforeBalance = IERC20(tokenOut).balanceOf(address(this));
        IERC20(tokenIn).forceApprove(router, resolved);
        _trackApproval(tokenIn, router);
        router.functionCall(routeData);
        amountOut = IERC20(tokenOut).balanceOf(address(this)) - beforeBalance;
        if (amountOut < minOut) revert InsufficientOutput(amountOut, minOut);
        IERC20(tokenIn).forceApprove(router, 0);
    }
}

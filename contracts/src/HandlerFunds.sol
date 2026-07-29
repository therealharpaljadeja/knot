// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { HandlerBase } from "./HandlerBase.sol";

/// @title Funds Handler
/// @notice Moves exact ERC-20 amounts between the combo initiator and executor.
contract HandlerFunds is HandlerBase {
    using SafeERC20 for IERC20;

    /// @notice Pulls an exact token amount from the cached combo sender.
    function addFunds(address token, uint256 amount) external {
        address sender = _comboSender();
        uint256 resolved = amount == type(uint256).max ? IERC20(token).balanceOf(sender) : amount;
        _trackToken(token);
        IERC20(token).safeTransferFrom(sender, address(this), resolved);
    }

    /// @notice Immediately returns the executor's full token balance to the combo sender.
    function returnFunds(address token) external {
        _trackToken(token);
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance != 0) IERC20(token).safeTransfer(_comboSender(), balance);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ExecutionStorage } from "./libraries/ExecutionStorage.sol";

/// @title Handler Base
/// @notice Shared execution-context helpers for delegatecall-safe handlers.
abstract contract HandlerBase {
    using SafeERC20 for IERC20;

    error NoActiveExecution();
    error NativeSweepFailed();
    error ResidualTokenBalance(address token, uint256 balance);
    error ResidualNativeBalance(uint256 balance);

    /// @notice Returns the wallet that started the current combo.
    function _comboSender() internal view returns (address sender) {
        sender = ExecutionStorage.layout().sender;
        if (sender == address(0)) revert NoActiveExecution();
    }

    /// @notice Registers an ERC-20 for final sweeping and zero-balance verification.
    function _trackToken(address token) internal {
        ExecutionStorage.Layout storage state = ExecutionStorage.layout();
        if (!state.tokenSeen[token]) {
            state.tokenSeen[token] = true;
            state.tokens.push(token);
        }
    }

    /// @notice Registers an approval that final post-processing must clear.
    function _trackApproval(address token, address spender) internal {
        ExecutionStorage.Layout storage state = ExecutionStorage.layout();
        bytes32 key = _approvalKey(token, spender);
        if (!state.approvalSeen[key]) {
            state.approvalSeen[key] = true;
            state.approvals.push(ExecutionStorage.Approval(token, spender));
        }
    }

    /// @notice Resolves the chained-input sentinel to the executor's full token balance.
    function _resolveAmount(address token, uint256 amount) internal view returns (uint256) {
        return amount == type(uint256).max ? IERC20(token).balanceOf(address(this)) : amount;
    }

    /// @notice Clears temporary approvals, sweeps tracked assets, and asserts no dust remains.
    function _postProcess(address recipient) internal {
        ExecutionStorage.Layout storage state = ExecutionStorage.layout();
        uint256 approvalsLength = state.approvals.length;
        for (uint256 i; i < approvalsLength; ++i) {
            ExecutionStorage.Approval memory approval = state.approvals[i];
            IERC20(approval.token).forceApprove(approval.spender, 0);
            state.approvalSeen[_approvalKey(approval.token, approval.spender)] = false;
        }
        delete state.approvals;

        uint256 tokensLength = state.tokens.length;
        for (uint256 i; i < tokensLength; ++i) {
            address token = state.tokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance != 0) IERC20(token).safeTransfer(recipient, balance);
            uint256 residual = IERC20(token).balanceOf(address(this));
            if (residual != 0) revert ResidualTokenBalance(token, residual);
            state.tokenSeen[token] = false;
        }
        delete state.tokens;

        uint256 nativeBalance = address(this).balance;
        if (nativeBalance != 0) {
            (bool sent,) = recipient.call{ value: nativeBalance }("");
            if (!sent) revert NativeSweepFailed();
        }
        if (address(this).balance != 0) revert ResidualNativeBalance(address(this).balance);
    }

    function _approvalKey(address token, address spender) private pure returns (bytes32 key) {
        assembly ("memory-safe") {
            mstore(0x00, token)
            mstore(0x20, spender)
            key := keccak256(0x00, 0x40)
        }
    }
}

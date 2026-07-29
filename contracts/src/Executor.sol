// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { HandlerBase } from "./HandlerBase.sol";
import { IMoncomboRegistry } from "./interfaces/IMoncombo.sol";
import { ExecutionStorage } from "./libraries/ExecutionStorage.sol";

/// @title Moncombo Executor
/// @notice Stateless user entry point that runs whitelisted handlers by delegatecall.
contract Executor is Ownable, Pausable, HandlerBase {
    using Address for address;

    IMoncomboRegistry public immutable REGISTRY;

    error ArrayLengthMismatch();
    error ReentrantExecution();
    error HandlerNotAllowed(address handler);
    error CallbackOutsideExecution();
    error CallerNotRegistered(address caller);
    error DirectNativeTransfer();

    constructor(address registry_, address initialOwner) Ownable(initialOwner) {
        REGISTRY = IMoncomboRegistry(registry_);
    }

    /// @notice Executes ordered, whitelisted handler calls and returns all touched assets.
    function execute(address[] calldata handlers, bytes[] calldata datas)
        external
        payable
        whenNotPaused
    {
        if (handlers.length != datas.length) revert ArrayLengthMismatch();
        ExecutionStorage.Layout storage state = ExecutionStorage.layout();
        if (state.sender != address(0)) revert ReentrantExecution();
        state.sender = msg.sender;

        _run(handlers, datas);
        _postProcess(msg.sender);
        state.sender = address(0);
    }

    /// @notice Pauses new combos and protocol callbacks.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resumes combo execution.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev Accepts native MON only during an active combo.
    receive() external payable {
        if (ExecutionStorage.layout().sender == address(0)) revert DirectNativeTransfer();
    }

    /// @dev Routes a trusted external callback to its registered handler.
    fallback() external payable whenNotPaused {
        if (ExecutionStorage.layout().sender == address(0)) revert CallbackOutsideExecution();
        address handler = REGISTRY.callers(msg.sender);
        if (handler == address(0)) revert CallerNotRegistered(msg.sender);
        if (!REGISTRY.handlers(handler)) revert HandlerNotAllowed(handler);
        bytes memory result = handler.functionDelegateCall(msg.data);
        assembly ("memory-safe") {
            return(add(result, 0x20), mload(result))
        }
    }

    function _run(address[] calldata handlers, bytes[] calldata datas) internal {
        uint256 length = handlers.length;
        for (uint256 i; i < length; ++i) {
            address handler = handlers[i];
            if (!REGISTRY.handlers(handler)) revert HandlerNotAllowed(handler);
            handler.functionDelegateCall(datas[i]);
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Moncombo Registry
/// @notice Owner-managed allowlists for executable handlers, callback callers, and routers.
contract Registry is Ownable {
    mapping(address handler => bool allowed) public handlers;
    mapping(address caller => address handler) public callers;
    mapping(address router => bool allowed) public routers;

    event HandlerSet(address indexed handler, bool allowed);
    event CallerSet(address indexed caller, address indexed handler);
    event RouterSet(address indexed router, bool allowed);

    error ZeroAddress();
    error HandlerNotAllowed(address handler);

    constructor(address initialOwner) Ownable(initialOwner) { }

    /// @notice Adds or removes a delegatecall target.
    function setHandler(address handler, bool allowed) external onlyOwner {
        if (handler == address(0)) revert ZeroAddress();
        handlers[handler] = allowed;
        emit HandlerSet(handler, allowed);
    }

    /// @notice Routes a trusted callback caller to a whitelisted handler.
    function setCaller(address caller, address handler) external onlyOwner {
        if (caller == address(0)) revert ZeroAddress();
        if (handler != address(0) && !handlers[handler]) revert HandlerNotAllowed(handler);
        callers[caller] = handler;
        emit CallerSet(caller, handler);
    }

    /// @notice Adds or removes a router that HandlerSwap may call.
    function setRouter(address router, bool allowed) external onlyOwner {
        if (router == address(0)) revert ZeroAddress();
        routers[router] = allowed;
        emit RouterSet(router, allowed);
    }
}

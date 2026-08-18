// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Knot Registry timelock
/// @notice Enforces an on-chain delay before the owner-only Registry setters can execute.
/// @dev The proposer is also the canceller. Execution is permissionless after the delay,
///      and role administration is controlled only by the timelock itself.
contract RegistryTimelock is TimelockController {
    error ZeroDelay();
    error ZeroProposer();

    // TimelockController stores its delay privately. This value backs the overridden getter so
    // the inherited scheduling checks and the update path share the same non-zero invariant.
    uint256 private _minimumDelay;

    constructor(uint256 minDelay, address proposer)
        TimelockController(minDelay, _singleton(proposer), _singleton(address(0)), address(0))
    {
        if (minDelay == 0) revert ZeroDelay();
        if (proposer == address(0)) revert ZeroProposer();
        _minimumDelay = minDelay;
    }

    /// @inheritdoc TimelockController
    function getMinDelay() public view override returns (uint256) {
        return _minimumDelay;
    }

    /// @notice Updates the delay through a timelocked self-call while preserving a non-zero floor.
    function updateDelay(uint256 newDelay) external override {
        address sender = _msgSender();
        if (sender != address(this)) revert TimelockUnauthorizedCaller(sender);
        if (newDelay == 0) revert ZeroDelay();
        emit MinDelayChange(_minimumDelay, newDelay);
        _minimumDelay = newDelay;
    }

    function _singleton(address account) private pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }
}

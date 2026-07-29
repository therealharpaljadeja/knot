// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ExecutionStorage
/// @notice Namespaced storage shared by the Executor and delegate-called handlers.
library ExecutionStorage {
    bytes32 internal constant SLOT = keccak256("moncombo.execution.storage.v1");

    struct Approval {
        address token;
        address spender;
    }

    struct Layout {
        address sender;
        address[] tokens;
        mapping(address => bool) tokenSeen;
        Approval[] approvals;
        mapping(bytes32 => bool) approvalSeen;
    }

    function layout() internal pure returns (Layout storage state) {
        bytes32 slot = SLOT;
        assembly ("memory-safe") {
            state.slot := slot
        }
    }
}

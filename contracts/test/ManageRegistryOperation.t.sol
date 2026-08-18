// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Registry } from "../src/Registry.sol";
import { RegistryTimelock } from "../src/RegistryTimelock.sol";
import { ManageRegistry } from "../script/ManageRegistry.s.sol";

contract ManageRegistryOperationTest is Test {
    bytes32 internal constant PREDECESSOR = bytes32(0);
    bytes32 internal constant SALT = keccak256("operator-reviewed-change");

    ManageRegistryHarness internal manager;
    RegistryTimelock internal timelock;
    Registry internal registry;

    function setUp() public {
        manager = new ManageRegistryHarness();
        timelock = new RegistryTimelock(1 days, address(this));
        registry = new Registry(address(timelock));
    }

    function testEncodesSetHandlerOperation() public {
        address handler = makeAddr("handler");
        bytes memory data = manager.exposedSetHandlerData(handler, true);
        assertEq(data, abi.encodeCall(Registry.setHandler, (handler, true)));
        assertEq(
            manager.exposedOperationId(timelock, registry, data, SALT),
            timelock.hashOperation(address(registry), 0, data, PREDECESSOR, SALT)
        );
    }

    function testEncodesSetCallerOperation() public {
        address caller = makeAddr("caller");
        address handler = makeAddr("handler");
        bytes memory data = manager.exposedSetCallerData(caller, handler);
        assertEq(data, abi.encodeCall(Registry.setCaller, (caller, handler)));
        assertEq(
            manager.exposedOperationId(timelock, registry, data, SALT),
            timelock.hashOperation(address(registry), 0, data, PREDECESSOR, SALT)
        );
    }

    function testEncodesSetRouterOperation() public {
        address router = makeAddr("router");
        bytes memory data = manager.exposedSetRouterData(router, false);
        assertEq(data, abi.encodeCall(Registry.setRouter, (router, false)));
        assertEq(
            manager.exposedOperationId(timelock, registry, data, SALT),
            timelock.hashOperation(address(registry), 0, data, PREDECESSOR, SALT)
        );
    }

    function testSaltChangesOperationIdWithoutChangingCalldata() public {
        bytes memory data = manager.exposedSetRouterData(makeAddr("router"), true);
        bytes32 first = manager.exposedOperationId(timelock, registry, data, SALT);
        bytes32 second = manager.exposedOperationId(
            timelock, registry, data, keccak256("operator-reviewed-change-2")
        );
        assertNotEq(first, second);
    }

    function testOnlyPendingStatesHaveActivationTimestamps() public view {
        assertFalse(manager.exposedHasActivationTimestamp(TimelockController.OperationState.Unset));
        assertTrue(manager.exposedHasActivationTimestamp(TimelockController.OperationState.Waiting));
        assertTrue(manager.exposedHasActivationTimestamp(TimelockController.OperationState.Ready));
        assertFalse(manager.exposedHasActivationTimestamp(TimelockController.OperationState.Done));
    }
}

contract ManageRegistryHarness is ManageRegistry {
    function exposedHasActivationTimestamp(TimelockController.OperationState state)
        external
        pure
        returns (bool)
    {
        return _hasActivationTimestamp(state);
    }

    function exposedSetHandlerData(address handler, bool allowed)
        external
        pure
        returns (bytes memory)
    {
        return _setHandlerData(handler, allowed);
    }

    function exposedSetCallerData(address caller, address handler)
        external
        pure
        returns (bytes memory)
    {
        return _setCallerData(caller, handler);
    }

    function exposedSetRouterData(address router, bool allowed)
        external
        pure
        returns (bytes memory)
    {
        return _setRouterData(router, allowed);
    }

    function exposedOperationId(
        RegistryTimelock timelock,
        Registry registry,
        bytes memory data,
        bytes32 salt
    ) external pure returns (bytes32) {
        return _operationId(timelock, registry, data, salt);
    }
}

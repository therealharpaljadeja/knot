// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Registry } from "../src/Registry.sol";
import { RegistryTimelock } from "../src/RegistryTimelock.sol";

contract RegistryTimelockTest is Test {
    uint256 internal constant DELAY = 2 days;
    bytes32 internal constant PREDECESSOR = bytes32(0);
    bytes32 internal constant SALT = keccak256("registry-change-1");

    address internal proposer = makeAddr("proposer");
    address internal executor = makeAddr("executor");
    address internal outsider = makeAddr("outsider");
    address internal caller = makeAddr("caller");
    address internal allowedHandler = address(new MockTarget());
    address internal candidateHandler = address(new MockTarget());
    address internal router = address(new MockTarget());

    Registry internal registry;
    RegistryTimelock internal timelock;

    function setUp() public {
        vm.warp(1_000_000);
        registry = new Registry(address(this));
        registry.setHandler(allowedHandler, true);
        timelock = new RegistryTimelock(DELAY, proposer);
        registry.transferOwnership(address(timelock));
    }

    function testRejectsZeroDelay() public {
        vm.expectRevert(RegistryTimelock.ZeroDelay.selector);
        new RegistryTimelock(0, proposer);
    }

    function testRejectsZeroProposer() public {
        vm.expectRevert(RegistryTimelock.ZeroProposer.selector);
        new RegistryTimelock(DELAY, address(0));
    }

    function testConfiguresRestrictedProposerAndCancellerWithOpenExecution() public view {
        assertEq(registry.owner(), address(timelock));
        assertEq(timelock.getMinDelay(), DELAY);
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(timelock)));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), proposer));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), proposer));
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), proposer));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
    }

    function testHandlerChangeIsQueuedBeforePermissionlessExecution() public {
        bytes memory data = abi.encodeCall(Registry.setHandler, (candidateHandler, true));
        bytes32 id = _schedule(data, SALT);

        assertEq(timelock.getTimestamp(id), block.timestamp + DELAY);
        assertTrue(timelock.isOperationPending(id));
        assertFalse(registry.handlers(candidateHandler));

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                _stateBitmap(TimelockController.OperationState.Ready)
            )
        );
        vm.prank(executor);
        timelock.execute(address(registry), 0, data, PREDECESSOR, SALT);

        vm.warp(block.timestamp + DELAY);
        vm.prank(executor);
        timelock.execute(address(registry), 0, data, PREDECESSOR, SALT);

        assertTrue(registry.handlers(candidateHandler));
        assertTrue(timelock.isOperationDone(id));
    }

    function testHandlerRemovalUsesTheSameDelay() public {
        bytes memory data = abi.encodeCall(Registry.setHandler, (allowedHandler, false));
        bytes32 id = _schedule(data, SALT);

        vm.warp(block.timestamp + DELAY - 1);
        _expectOperationNotReady(id);
        timelock.execute(address(registry), 0, data, PREDECESSOR, SALT);
        assertTrue(registry.handlers(allowedHandler));

        vm.warp(block.timestamp + 1);
        timelock.execute(address(registry), 0, data, PREDECESSOR, SALT);
        assertFalse(registry.handlers(allowedHandler));
    }

    function testCallerBindingExecutesAfterDelay() public {
        bytes memory data = abi.encodeCall(Registry.setCaller, (caller, allowedHandler));
        _schedule(data, SALT);
        vm.warp(block.timestamp + DELAY);

        timelock.execute(address(registry), 0, data, PREDECESSOR, SALT);

        assertEq(registry.callers(caller), allowedHandler);
    }

    function testCallerUnbindingUsesTheSameDelay() public {
        bytes memory bindData = abi.encodeCall(Registry.setCaller, (caller, allowedHandler));
        _schedule(bindData, SALT);
        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(registry), 0, bindData, PREDECESSOR, SALT);

        bytes32 unbindSalt = keccak256("caller-unbind");
        bytes memory unbindData = abi.encodeCall(Registry.setCaller, (caller, address(0)));
        bytes32 unbindId = _schedule(unbindData, unbindSalt);
        _expectOperationNotReady(unbindId);
        timelock.execute(address(registry), 0, unbindData, PREDECESSOR, unbindSalt);
        assertEq(registry.callers(caller), allowedHandler);

        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(registry), 0, unbindData, PREDECESSOR, unbindSalt);
        assertEq(registry.callers(caller), address(0));
    }

    function testRouterChangeExecutesAfterDelay() public {
        bytes memory data = abi.encodeCall(Registry.setRouter, (router, true));
        _schedule(data, SALT);
        vm.warp(block.timestamp + DELAY);

        timelock.execute(address(registry), 0, data, PREDECESSOR, SALT);

        assertTrue(registry.routers(router));
    }

    function testRouterRemovalUsesTheSameDelay() public {
        bytes memory addData = abi.encodeCall(Registry.setRouter, (router, true));
        _schedule(addData, SALT);
        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(registry), 0, addData, PREDECESSOR, SALT);

        bytes32 removalSalt = keccak256("router-removal");
        bytes memory removeData = abi.encodeCall(Registry.setRouter, (router, false));
        bytes32 removalId = _schedule(removeData, removalSalt);
        _expectOperationNotReady(removalId);
        timelock.execute(address(registry), 0, removeData, PREDECESSOR, removalSalt);
        assertTrue(registry.routers(router));

        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(registry), 0, removeData, PREDECESSOR, removalSalt);
        assertFalse(registry.routers(router));
    }

    function testProposerCanCancelPendingOperation() public {
        bytes memory data = abi.encodeCall(Registry.setRouter, (router, true));
        bytes32 id = _schedule(data, SALT);

        vm.prank(proposer);
        timelock.cancel(id);

        assertFalse(timelock.isOperation(id));
        vm.warp(block.timestamp + DELAY);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                _stateBitmap(TimelockController.OperationState.Ready)
            )
        );
        timelock.execute(address(registry), 0, data, PREDECESSOR, SALT);
        assertFalse(registry.routers(router));
    }

    function testUnauthorizedAccountCannotScheduleOrCancel() public {
        bytes memory data = abi.encodeCall(Registry.setRouter, (router, true));
        bytes32 id = timelock.hashOperation(address(registry), 0, data, PREDECESSOR, SALT);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                outsider,
                timelock.PROPOSER_ROLE()
            )
        );
        vm.prank(outsider);
        timelock.schedule(address(registry), 0, data, PREDECESSOR, SALT, DELAY);

        _schedule(data, SALT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                outsider,
                timelock.CANCELLER_ROLE()
            )
        );
        vm.prank(outsider);
        timelock.cancel(id);
    }

    function testExecutedOperationCannotBeReplayedOrRescheduledWithSameSalt() public {
        bytes memory data = abi.encodeCall(Registry.setRouter, (router, true));
        _schedule(data, SALT);
        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(registry), 0, data, PREDECESSOR, SALT);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                timelock.hashOperation(address(registry), 0, data, PREDECESSOR, SALT),
                _stateBitmap(TimelockController.OperationState.Ready)
            )
        );
        timelock.execute(address(registry), 0, data, PREDECESSOR, SALT);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                timelock.hashOperation(address(registry), 0, data, PREDECESSOR, SALT),
                _stateBitmap(TimelockController.OperationState.Unset)
            )
        );
        vm.prank(proposer);
        timelock.schedule(address(registry), 0, data, PREDECESSOR, SALT, DELAY);
    }

    function testDifferentSaltsProduceDifferentOperationIds() public view {
        bytes memory data = abi.encodeCall(Registry.setRouter, (router, true));
        bytes32 first = timelock.hashOperation(address(registry), 0, data, PREDECESSOR, SALT);
        bytes32 second = timelock.hashOperation(
            address(registry), 0, data, PREDECESSOR, keccak256("registry-change-2")
        );
        assertNotEq(first, second);
    }

    function testRegistryCannotBeMutatedDirectlyByProposer() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, proposer)
        );
        vm.prank(proposer);
        registry.setRouter(router, true);
    }

    function testDelayCannotBeUpdatedToZero() public {
        bytes32 salt = keccak256("zero-delay-update");
        bytes memory data = abi.encodeCall(TimelockController.updateDelay, (0));
        bytes32 id = timelock.hashOperation(address(timelock), 0, data, PREDECESSOR, salt);

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, data, PREDECESSOR, salt, DELAY);
        vm.warp(block.timestamp + DELAY);

        vm.expectRevert(RegistryTimelock.ZeroDelay.selector);
        timelock.execute(address(timelock), 0, data, PREDECESSOR, salt);

        assertEq(timelock.getMinDelay(), DELAY);
        assertTrue(timelock.isOperationReady(id));
    }

    function testNonZeroDelayUpdateRequiresAQueuedSelfCall() public {
        uint256 newDelay = 3 days;
        bytes32 salt = keccak256("non-zero-delay-update");
        bytes memory data = abi.encodeCall(TimelockController.updateDelay, (newDelay));

        vm.expectRevert(
            abi.encodeWithSelector(TimelockController.TimelockUnauthorizedCaller.selector, proposer)
        );
        vm.prank(proposer);
        timelock.updateDelay(newDelay);

        _scheduleFor(address(timelock), data, salt);
        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(timelock), 0, data, PREDECESSOR, salt);

        assertEq(timelock.getMinDelay(), newDelay);

        bytes memory registryData = abi.encodeCall(Registry.setRouter, (router, true));
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockInsufficientDelay.selector, DELAY, newDelay
            )
        );
        vm.prank(proposer);
        timelock.schedule(address(registry), 0, registryData, PREDECESSOR, SALT, DELAY);
    }

    function _schedule(bytes memory data, bytes32 salt) internal returns (bytes32 id) {
        return _scheduleFor(address(registry), data, salt);
    }

    function _scheduleFor(address target, bytes memory data, bytes32 salt)
        internal
        returns (bytes32 id)
    {
        id = timelock.hashOperation(target, 0, data, PREDECESSOR, salt);
        vm.prank(proposer);
        timelock.schedule(target, 0, data, PREDECESSOR, salt, DELAY);
    }

    function _stateBitmap(TimelockController.OperationState state) internal pure returns (bytes32) {
        return bytes32(uint256(1) << uint8(state));
    }

    function _expectOperationNotReady(bytes32 id) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                id,
                _stateBitmap(TimelockController.OperationState.Ready)
            )
        );
    }
}

contract MockTarget { }

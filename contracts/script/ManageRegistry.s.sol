// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Script, console2 } from "forge-std/Script.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { Registry } from "../src/Registry.sol";
import { RegistryTimelock } from "../src/RegistryTimelock.sol";

/// @title Knot Registry timelock manager
/// @notice Previews, queues, inspects, executes, or cancels one Registry change.
contract ManageRegistry is Script {
    bytes32 internal constant SET_HANDLER = keccak256("set-handler");
    bytes32 internal constant SET_CALLER = keccak256("set-caller");
    bytes32 internal constant SET_ROUTER = keccak256("set-router");
    bytes32 internal constant QUEUE = keccak256("queue");
    bytes32 internal constant STATUS = keccak256("status");
    bytes32 internal constant EXECUTE = keccak256("execute");
    bytes32 internal constant CANCEL = keccak256("cancel");
    bytes32 internal constant PREDECESSOR = bytes32(0);

    struct RegistryChange {
        bytes32 action;
        address target;
        address handler;
        bool allowed;
        bool noOp;
        bytes data;
    }

    error MissingRegistryDeployment(uint256 chainId);
    error ZeroRegistryDeployment(uint256 chainId);
    error MissingTimelockDeployment(uint256 chainId);
    error ZeroTimelockDeployment(uint256 chainId);
    error AddressHasNoCode(string variableName, address target);
    error ZeroInput(string variableName);
    error RegistryOwnerIsNotTimelock(address owner, address timelock);
    error SignerMissingRole(address signer, bytes32 role);
    error LiveModeRequiresBroadcast();
    error UnknownRegistryAction(string action);
    error UnknownTimelockAction(string action);
    error HandlerIsNotAllowed(address handler);
    error NoStateChange();
    error ZeroSalt();
    error PostconditionFailed();

    function run() external {
        bool dryRun = vm.envOr("DRY_RUN", true);
        string memory timelockActionName = vm.envString("TIMELOCK_ACTION");
        bytes32 timelockAction = keccak256(bytes(timelockActionName));
        if (!_isKnownTimelockAction(timelockAction)) {
            revert UnknownTimelockAction(timelockActionName);
        }
        if (
            timelockAction != STATUS && !dryRun
                && !vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)
        ) {
            revert LiveModeRequiresBroadcast();
        }

        Registry registry = _loadRegistry();
        RegistryTimelock timelock = _loadTimelock();
        if (registry.owner() != address(timelock)) {
            revert RegistryOwnerIsNotTimelock(registry.owner(), address(timelock));
        }

        bytes32 salt = vm.envBytes32("TIMELOCK_SALT");
        if (salt == bytes32(0)) revert ZeroSalt();
        bool validateTrustTargets = timelockAction == QUEUE || timelockAction == EXECUTE;
        RegistryChange memory change = _loadChange(registry, validateTrustTargets);
        bytes32 id = _operationId(timelock, registry, change.data, salt);

        _printOperation(registry, timelock, change, timelockActionName, salt, id, dryRun);
        if (timelockAction == STATUS) return;

        address signer = _selectedSigner();
        console2.log("Signer", signer);
        if (timelockAction == QUEUE) {
            _requireRole(timelock, timelock.PROPOSER_ROLE(), signer, false);
            if (!_shouldMutate(dryRun, change.noOp)) return;
            _queue(timelock, registry, change.data, salt, id);
        } else if (timelockAction == EXECUTE) {
            _requireRole(timelock, timelock.EXECUTOR_ROLE(), signer, true);
            if (!_shouldMutate(dryRun, change.noOp)) return;
            _execute(timelock, registry, change, salt, id);
        } else {
            _requireRole(timelock, timelock.CANCELLER_ROLE(), signer, false);
            if (dryRun) {
                console2.log("Dry run complete; the pending operation was not cancelled.");
                return;
            }
            _cancel(timelock, id);
        }
    }

    function _loadRegistry() internal view returns (Registry registry) {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/deployments.json"));
        string memory key = string.concat(".", vm.toString(block.chainid), ".Registry");
        if (!vm.keyExistsJson(json, key)) revert MissingRegistryDeployment(block.chainid);

        address registryAddress = vm.parseJsonAddress(json, key);
        if (registryAddress == address(0)) revert ZeroRegistryDeployment(block.chainid);
        _requireCode("Registry", registryAddress);
        registry = Registry(registryAddress);
    }

    function _loadTimelock() internal view returns (RegistryTimelock timelock) {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/deployments.json"));
        string memory key = string.concat(".", vm.toString(block.chainid), ".RegistryTimelock");
        if (!vm.keyExistsJson(json, key)) revert MissingTimelockDeployment(block.chainid);

        address timelockAddress = vm.parseJsonAddress(json, key);
        if (timelockAddress == address(0)) revert ZeroTimelockDeployment(block.chainid);
        _requireCode("RegistryTimelock", timelockAddress);
        timelock = RegistryTimelock(payable(timelockAddress));
    }

    function _loadChange(Registry registry, bool validateTrustTargets)
        internal
        view
        returns (RegistryChange memory change)
    {
        string memory actionName = vm.envString("REGISTRY_ACTION");
        bytes32 action = keccak256(bytes(actionName));
        if (action == SET_HANDLER) return _loadHandlerChange(registry, validateTrustTargets);
        if (action == SET_CALLER) return _loadCallerChange(registry, validateTrustTargets);
        if (action == SET_ROUTER) return _loadRouterChange(registry, validateTrustTargets);
        revert UnknownRegistryAction(actionName);
    }

    function _loadHandlerChange(Registry registry, bool validateTrustTargets)
        internal
        view
        returns (RegistryChange memory change)
    {
        address handler = vm.envAddress("HANDLER");
        bool allowed = vm.envBool("ALLOWED");
        if (handler == address(0)) revert ZeroInput("HANDLER");
        if (validateTrustTargets && allowed) _requireCode("HANDLER", handler);

        bool current = registry.handlers(handler);
        console2.log("Registry action: set-handler");
        console2.log("Handler", handler);
        console2.log("Current allowed", current);
        console2.log("Intended allowed", allowed);
        if (!allowed) _warnKnownCallers(registry, handler);
        return RegistryChange({
            action: SET_HANDLER,
            target: handler,
            handler: address(0),
            allowed: allowed,
            noOp: current == allowed,
            data: _setHandlerData(handler, allowed)
        });
    }

    function _loadCallerChange(Registry registry, bool validateTrustTargets)
        internal
        view
        returns (RegistryChange memory change)
    {
        address caller = vm.envAddress("CALLER");
        address handler = vm.envAddress("CALLER_HANDLER");
        if (caller == address(0)) revert ZeroInput("CALLER");
        if (validateTrustTargets && handler != address(0)) {
            _requireCode("CALLER", caller);
            _requireCode("CALLER_HANDLER", handler);
            if (!registry.handlers(handler)) revert HandlerIsNotAllowed(handler);
        }

        address current = registry.callers(caller);
        console2.log("Registry action: set-caller");
        console2.log("Caller", caller);
        console2.log("Current handler", current);
        console2.log("Intended handler", handler);
        return RegistryChange({
            action: SET_CALLER,
            target: caller,
            handler: handler,
            allowed: false,
            noOp: current == handler,
            data: _setCallerData(caller, handler)
        });
    }

    function _loadRouterChange(Registry registry, bool validateTrustTargets)
        internal
        view
        returns (RegistryChange memory change)
    {
        address router = vm.envAddress("ROUTER");
        bool allowed = vm.envBool("ALLOWED");
        if (router == address(0)) revert ZeroInput("ROUTER");
        if (validateTrustTargets && allowed) _requireCode("ROUTER", router);

        bool current = registry.routers(router);
        console2.log("Registry action: set-router");
        console2.log("Router", router);
        console2.log("Current allowed", current);
        console2.log("Intended allowed", allowed);
        return RegistryChange({
            action: SET_ROUTER,
            target: router,
            handler: address(0),
            allowed: allowed,
            noOp: current == allowed,
            data: _setRouterData(router, allowed)
        });
    }

    function _printOperation(
        Registry registry,
        RegistryTimelock timelock,
        RegistryChange memory change,
        string memory timelockAction,
        bytes32 salt,
        bytes32 id,
        bool dryRun
    ) internal view {
        TimelockController.OperationState state = timelock.getOperationState(id);
        uint256 timestamp = timelock.getTimestamp(id);
        console2.log("Chain ID", block.chainid);
        console2.log("Registry", address(registry));
        console2.log("RegistryTimelock", address(timelock));
        console2.log("Timelock action", timelockAction);
        console2.log("Dry run", dryRun);
        console2.log("No-op against current Registry state", change.noOp);
        console2.log("Timelock minimum delay", timelock.getMinDelay());
        console2.log("Operation state", _stateName(state));
        if (_hasActivationTimestamp(state)) {
            console2.log("Activation timestamp", timestamp);
        } else if (state == TimelockController.OperationState.Done) {
            console2.log("Activation timestamp unavailable; operation is already done.");
        } else {
            console2.log("Activation timestamp unavailable; operation is not scheduled.");
        }
        console2.log("Operation salt");
        console2.logBytes32(salt);
        console2.log("Operation ID");
        console2.logBytes32(id);
        console2.log("Registry calldata");
        console2.logBytes(change.data);
    }

    function _queue(
        RegistryTimelock timelock,
        Registry registry,
        bytes memory data,
        bytes32 salt,
        bytes32 id
    ) internal {
        uint256 delay = timelock.getMinDelay();
        vm.startBroadcast();
        timelock.schedule(address(registry), 0, data, PREDECESSOR, salt, delay);
        vm.stopBroadcast();
        if (!timelock.isOperationPending(id)) revert PostconditionFailed();
        console2.log("Simulated queue postcondition verified");
        console2.log("Simulated activation timestamp", timelock.getTimestamp(id));
    }

    function _execute(
        RegistryTimelock timelock,
        Registry registry,
        RegistryChange memory change,
        bytes32 salt,
        bytes32 id
    ) internal {
        vm.startBroadcast();
        timelock.execute(address(registry), 0, change.data, PREDECESSOR, salt);
        vm.stopBroadcast();
        if (!timelock.isOperationDone(id) || !_matchesIntendedState(registry, change)) {
            revert PostconditionFailed();
        }
        console2.log("Simulated execution and Registry postconditions verified");
    }

    function _cancel(RegistryTimelock timelock, bytes32 id) internal {
        vm.startBroadcast();
        timelock.cancel(id);
        vm.stopBroadcast();
        if (timelock.isOperation(id)) revert PostconditionFailed();
        console2.log("Simulated cancellation postcondition verified");
    }

    function _matchesIntendedState(Registry registry, RegistryChange memory change)
        internal
        view
        returns (bool)
    {
        if (change.action == SET_HANDLER) {
            return registry.handlers(change.target) == change.allowed;
        }
        if (change.action == SET_CALLER) return registry.callers(change.target) == change.handler;
        return registry.routers(change.target) == change.allowed;
    }

    function _selectedSigner() internal returns (address signer) {
        vm.startBroadcast();
        (, signer,) = vm.readCallers();
        vm.stopBroadcast();
    }

    function _requireRole(
        RegistryTimelock timelock,
        bytes32 role,
        address signer,
        bool allowOpenRole
    ) internal view {
        if (
            !timelock.hasRole(role, signer)
                && !(allowOpenRole && timelock.hasRole(role, address(0)))
        ) {
            revert SignerMissingRole(signer, role);
        }
    }

    function _shouldMutate(bool dryRun, bool noOp) internal pure returns (bool) {
        if (noOp && !dryRun) revert NoStateChange();
        if (dryRun) {
            console2.log("Dry run complete; no timelock transaction was broadcast.");
            return false;
        }
        return true;
    }

    function _warnKnownCallers(Registry registry, address handler) internal view {
        address[] memory empty = new address[](0);
        address[] memory knownCallers = vm.envOr("KNOWN_CALLERS", ",", empty);
        console2.log("Known-caller check is non-exhaustive; Registry callers cannot be enumerated.");
        for (uint256 i; i < knownCallers.length; ++i) {
            if (registry.callers(knownCallers[i]) == handler) {
                console2.log("WARNING: caller is still bound to the handler", knownCallers[i]);
            }
        }
    }

    function _setHandlerData(address handler, bool allowed) internal pure returns (bytes memory) {
        return abi.encodeCall(Registry.setHandler, (handler, allowed));
    }

    function _setCallerData(address caller, address handler) internal pure returns (bytes memory) {
        return abi.encodeCall(Registry.setCaller, (caller, handler));
    }

    function _setRouterData(address router, bool allowed) internal pure returns (bytes memory) {
        return abi.encodeCall(Registry.setRouter, (router, allowed));
    }

    function _operationId(
        RegistryTimelock timelock,
        Registry registry,
        bytes memory data,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return timelock.hashOperation(address(registry), 0, data, PREDECESSOR, salt);
    }

    function _stateName(TimelockController.OperationState state)
        internal
        pure
        returns (string memory)
    {
        if (state == TimelockController.OperationState.Unset) return "unset";
        if (state == TimelockController.OperationState.Waiting) return "waiting";
        if (state == TimelockController.OperationState.Ready) return "ready";
        return "done";
    }

    function _hasActivationTimestamp(TimelockController.OperationState state)
        internal
        pure
        returns (bool)
    {
        return state == TimelockController.OperationState.Waiting
            || state == TimelockController.OperationState.Ready;
    }

    function _isKnownTimelockAction(bytes32 action) internal pure returns (bool) {
        return action == QUEUE || action == STATUS || action == EXECUTE || action == CANCEL;
    }

    function _requireCode(string memory variableName, address target) internal view {
        if (target.code.length == 0) revert AddressHasNoCode(variableName, target);
    }
}

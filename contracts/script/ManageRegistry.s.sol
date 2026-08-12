// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { Registry } from "../src/Registry.sol";

/// @title Knot Registry allowlist manager
/// @notice Safely previews or applies one owner-managed Registry change.
contract ManageRegistry is Script {
    bytes32 internal constant SET_HANDLER = keccak256("set-handler");
    bytes32 internal constant SET_CALLER = keccak256("set-caller");
    bytes32 internal constant SET_ROUTER = keccak256("set-router");

    error MissingRegistryDeployment(uint256 chainId);
    error ZeroRegistryDeployment(uint256 chainId);
    error AddressHasNoCode(string variableName, address target);
    error ZeroInput(string variableName);
    error SignerIsNotOwner(address signer, address owner);
    error LiveModeRequiresBroadcast();
    error UnknownAction(string action);
    error HandlerIsNotAllowed(address handler);
    error NoStateChange();
    error PostconditionFailed();

    function run() external {
        bool dryRun = vm.envOr("DRY_RUN", true);
        if (!dryRun && !vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            revert LiveModeRequiresBroadcast();
        }

        Registry registry = _loadRegistry();
        address signer = _selectedSigner();
        address owner = registry.owner();
        if (signer != owner) revert SignerIsNotOwner(signer, owner);

        console2.log("Chain ID", block.chainid);
        console2.log("Registry", address(registry));
        console2.log("Signer", signer);
        console2.log("Registry owner", owner);
        console2.log("Dry run", dryRun);

        string memory action = vm.envString("REGISTRY_ACTION");
        bytes32 actionHash = keccak256(bytes(action));
        if (actionHash == SET_HANDLER) _setHandler(registry, dryRun);
        else if (actionHash == SET_CALLER) _setCaller(registry, dryRun);
        else if (actionHash == SET_ROUTER) _setRouter(registry, dryRun);
        else revert UnknownAction(action);
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

    function _selectedSigner() internal returns (address signer) {
        vm.startBroadcast();
        (, signer,) = vm.readCallers();
        vm.stopBroadcast();
    }

    function _setHandler(Registry registry, bool dryRun) internal {
        address handler = vm.envAddress("HANDLER");
        bool allowed = vm.envBool("ALLOWED");
        if (handler == address(0)) revert ZeroInput("HANDLER");
        if (allowed) _requireCode("HANDLER", handler);

        bool current = registry.handlers(handler);
        console2.log("Action: set-handler");
        console2.log("Handler", handler);
        console2.log("Current allowed", current);
        console2.log("Intended allowed", allowed);

        if (!allowed) _warnKnownCallers(registry, handler);
        if (!_shouldExecute(dryRun, current == allowed)) return;

        vm.startBroadcast();
        registry.setHandler(handler, allowed);
        vm.stopBroadcast();
        if (registry.handlers(handler) != allowed) revert PostconditionFailed();
        console2.log("Simulated postcondition verified", allowed);
    }

    function _setCaller(Registry registry, bool dryRun) internal {
        address caller = vm.envAddress("CALLER");
        address handler = vm.envAddress("CALLER_HANDLER");
        if (caller == address(0)) revert ZeroInput("CALLER");
        if (handler != address(0)) {
            _requireCode("CALLER", caller);
            _requireCode("CALLER_HANDLER", handler);
            if (!registry.handlers(handler)) revert HandlerIsNotAllowed(handler);
        }

        address current = registry.callers(caller);
        console2.log("Action: set-caller");
        console2.log("Caller", caller);
        console2.log("Current handler", current);
        console2.log("Intended handler", handler);
        if (!_shouldExecute(dryRun, current == handler)) return;

        vm.startBroadcast();
        registry.setCaller(caller, handler);
        vm.stopBroadcast();
        if (registry.callers(caller) != handler) revert PostconditionFailed();
        console2.log("Simulated postcondition verified", handler);
    }

    function _setRouter(Registry registry, bool dryRun) internal {
        address router = vm.envAddress("ROUTER");
        bool allowed = vm.envBool("ALLOWED");
        if (router == address(0)) revert ZeroInput("ROUTER");
        if (allowed) _requireCode("ROUTER", router);

        bool current = registry.routers(router);
        console2.log("Action: set-router");
        console2.log("Router", router);
        console2.log("Current allowed", current);
        console2.log("Intended allowed", allowed);
        if (!_shouldExecute(dryRun, current == allowed)) return;

        vm.startBroadcast();
        registry.setRouter(router, allowed);
        vm.stopBroadcast();
        if (registry.routers(router) != allowed) revert PostconditionFailed();
        console2.log("Simulated postcondition verified", allowed);
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

    function _shouldExecute(bool dryRun, bool noOp) internal pure returns (bool) {
        console2.log("No-op", noOp);
        if (noOp && !dryRun) revert NoStateChange();
        if (dryRun) {
            console2.log("Dry run complete; no transaction was broadcast.");
            return false;
        }
        return true;
    }

    function _requireCode(string memory variableName, address target) internal view {
        if (target.code.length == 0) revert AddressHasNoCode(variableName, target);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { Registry } from "../src/Registry.sol";
import { RegistryTimelock } from "../src/RegistryTimelock.sol";

/// @title Knot Registry timelock migration
/// @notice Deploys a timelock and transfers an existing Registry's ownership in one script run.
contract MigrateRegistryTimelock is Script {
    error MissingRegistryDeployment(uint256 chainId);
    error ZeroRegistryDeployment(uint256 chainId);
    error RegistryHasNoCode(address registry);
    error SignerIsNotOwner(address signer, address owner);
    error LiveModeRequiresBroadcast();
    error OwnershipTransferFailed(address owner);

    function run() external {
        bool dryRun = vm.envOr("DRY_RUN", true);
        if (!dryRun && !vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            revert LiveModeRequiresBroadcast();
        }

        Registry registry = _loadRegistry();
        address signer = _selectedSigner();
        address owner = registry.owner();
        if (signer != owner) revert SignerIsNotOwner(signer, owner);

        uint256 delay = vm.envUint("TIMELOCK_DELAY");
        if (delay == 0) revert RegistryTimelock.ZeroDelay();

        console2.log("Chain ID", block.chainid);
        console2.log("Registry", address(registry));
        console2.log("Current Registry owner", owner);
        console2.log("Timelock proposer/canceller", owner);
        console2.log("Timelock executor", "open to every address after the delay");
        console2.log("Timelock minimum delay", delay);
        console2.log("Dry run", dryRun);

        if (dryRun) {
            console2.log("Dry run complete; no contract was deployed and ownership was unchanged.");
            return;
        }

        vm.startBroadcast();
        RegistryTimelock timelock = new RegistryTimelock(delay, owner);
        registry.transferOwnership(address(timelock));
        vm.stopBroadcast();

        if (registry.owner() != address(timelock)) {
            revert OwnershipTransferFailed(registry.owner());
        }
        console2.log("RegistryTimelock", address(timelock));
        console2.log("Simulated Registry ownership transfer verified");
        console2.log("Record the confirmed timelock address in deployments.json after broadcast.");
    }

    function _loadRegistry() internal view returns (Registry registry) {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/deployments.json"));
        string memory key = string.concat(".", vm.toString(block.chainid), ".Registry");
        if (!vm.keyExistsJson(json, key)) revert MissingRegistryDeployment(block.chainid);

        address registryAddress = vm.parseJsonAddress(json, key);
        if (registryAddress == address(0)) revert ZeroRegistryDeployment(block.chainid);
        if (registryAddress.code.length == 0) revert RegistryHasNoCode(registryAddress);
        registry = Registry(registryAddress);
    }

    function _selectedSigner() internal returns (address signer) {
        vm.startBroadcast();
        (, signer,) = vm.readCallers();
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Script, console2 } from "forge-std/Script.sol";
import { AaveV3Monad } from "@aave-address-book/AaveV3Monad.sol";
import { Registry } from "../src/Registry.sol";
import { Executor } from "../src/Executor.sol";
import { FlashLoanHandler } from "../src/FlashLoanHandler.sol";
import { HandlerAaveV3 } from "../src/HandlerAaveV3.sol";
import { HandlerSwap } from "../src/HandlerSwap.sol";
import { HandlerFunds } from "../src/HandlerFunds.sol";

/// @title Knot deployment script
/// @notice Deploys and wires the complete v1 protocol, then writes deployments.json.
contract Deploy is Script {
    function run() external {
        address routerA = vm.envOr("ROUTER_A", address(0));
        address routerB = vm.envOr("ROUTER_B", address(0));

        // The CLI selects the signer (keystore, hardware wallet, or private key).
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        address owner = vm.envOr("OWNER", deployer);

        Registry registry = new Registry(deployer);
        Executor executor = new Executor(address(registry), owner);
        FlashLoanHandler flashLoan = new FlashLoanHandler(address(registry));
        HandlerAaveV3 aave = new HandlerAaveV3();
        HandlerSwap swap = new HandlerSwap(address(registry));
        HandlerFunds funds = new HandlerFunds();

        registry.setHandler(address(flashLoan), true);
        registry.setHandler(address(aave), true);
        registry.setHandler(address(swap), true);
        registry.setHandler(address(funds), true);
        registry.setCaller(address(AaveV3Monad.POOL), address(flashLoan));
        if (routerA != address(0)) registry.setRouter(routerA, true);
        if (routerB != address(0) && routerB != routerA) registry.setRouter(routerB, true);
        if (owner != deployer) registry.transferOwnership(owner);
        vm.stopBroadcast();

        string memory contractsJson = "contracts";
        vm.serializeAddress(contractsJson, "Registry", address(registry));
        vm.serializeAddress(contractsJson, "Executor", address(executor));
        vm.serializeAddress(contractsJson, "FlashLoanHandler", address(flashLoan));
        vm.serializeAddress(contractsJson, "HandlerAaveV3", address(aave));
        vm.serializeAddress(contractsJson, "HandlerSwap", address(swap));
        string memory nested = vm.serializeAddress(contractsJson, "HandlerFunds", address(funds));
        string memory output = string.concat('{"', vm.toString(block.chainid), '":', nested, "}");
        vm.writeJson(output, string.concat(vm.projectRoot(), "/deployments.json"));

        console2.log("Registry", address(registry));
        console2.log("Executor", address(executor));
        console2.log("FlashLoanHandler", address(flashLoan));
        console2.log("HandlerAaveV3", address(aave));
        console2.log("HandlerSwap", address(swap));
        console2.log("HandlerFunds", address(funds));
    }
}

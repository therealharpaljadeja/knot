// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AaveV3Monad } from "@aave-address-book/AaveV3Monad.sol";
import { IPool } from "@aave-address-book/AaveV3.sol";
import { HandlerBase } from "./HandlerBase.sol";

/// @title Aave v3 Action Handler
/// @notice Supplies underlying assets to, or withdraws them from, Aave v3 on Monad.
contract HandlerAaveV3 is HandlerBase {
    using SafeERC20 for IERC20;

    IPool public constant POOL = AaveV3Monad.POOL;

    /// @notice Supplies `amount` on behalf of the executor.
    function supply(address asset, uint256 amount) external {
        uint256 resolved = _resolveAmount(asset, amount);
        address aToken = POOL.getReserveData(asset).aTokenAddress;
        _trackToken(asset);
        _trackToken(aToken);
        IERC20(asset).forceApprove(address(POOL), resolved);
        _trackApproval(asset, address(POOL));
        POOL.supply(asset, resolved, address(this), 0);
    }

    /// @notice Withdraws `amount`; max uint requests the full Aave position.
    function withdraw(address asset, uint256 amount) external returns (uint256 withdrawn) {
        address aToken = POOL.getReserveData(asset).aTokenAddress;
        _trackToken(asset);
        _trackToken(aToken);
        withdrawn = POOL.withdraw(asset, amount, address(this));
    }
}

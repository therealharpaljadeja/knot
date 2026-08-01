// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AaveV3Monad } from "@aave-address-book/AaveV3Monad.sol";
import { IPool } from "@aave-address-book/AaveV3.sol";
import { HandlerBase } from "./HandlerBase.sol";

/// @title Aave v3 Action Handler
/// @notice Supplies underlying assets to Aave v3 on Monad, withdraws them and repays
///         variable-rate debt.
contract HandlerAaveV3 is HandlerBase {
    using SafeERC20 for IERC20;

    IPool public constant POOL = AaveV3Monad.POOL;

    /// @dev Aave v3.2.0 removed stable borrowing; the Pool only accepts the variable mode.
    uint256 internal constant VARIABLE_RATE_MODE = 2;

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

    /// @notice Repays the combo sender's variable-rate debt; max uint spends the executor's
    ///         complete asset balance and Aave caps the payment at the outstanding debt.
    /// @dev Debt is reduced for `_comboSender()`, never for the executor: the executor is
    ///      transient and holds no position. Aave repayment is permissionless, so paying
    ///      another address adds no credit delegation and no standing approval.
    ///      `_resolveAmount` runs before the Pool call because Aave rejects
    ///      `type(uint256).max` unless the payer is the borrower. The Pool pulls at most the
    ///      outstanding debt, so the approval is cleared here and any unspent principal is
    ///      swept back to the sender by final post-processing. The variable debt token is
    ///      deliberately untracked: it is non-transferable and the executor can never hold a
    ///      balance of it, so tracking it would add a sweep the post-processor cannot make.
    function repay(address asset, uint256 amount) external returns (uint256 repaid) {
        uint256 resolved = _resolveAmount(asset, amount);
        _trackToken(asset);
        IERC20(asset).forceApprove(address(POOL), resolved);
        _trackApproval(asset, address(POOL));
        repaid = POOL.repay(asset, resolved, VARIABLE_RATE_MODE, _comboSender());
        IERC20(asset).forceApprove(address(POOL), 0);
    }
}

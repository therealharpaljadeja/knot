# Monad mainnet manual verification

This runbook is the contract test suite. Follow it in order, use a dedicated
wallet, and stop on the first unexpected result. Commands assume Foundry
(`cast`, `forge`) and `jq` are installed.

All addresses below are Monad mainnet:

```bash
export RPC_URL=https://rpc.monad.xyz
export POOL=0x69a5F9AD4f96ebf0a0C792dD42a01cC5C0102fef
export DATA_PROVIDER=0xB65A68B98274ef7D9a60E0C0747dD1BEc3D32fad
export USDC=0x754704Bc059F8C67012fEd69BC8A327a5aafb603
export AUSDC=0x35a73BAcb179d3740395A3ceCc87FF2e581d6042
export VDUSDC=0x9F555aB84C4e0a531B50283f09Dba7A97134c4e4
export WETH=0xEE8c0E9f1BFFb4Eb878d8f15f368A02a35481242
export MAX_UINT=115792089237316195423570985008687907853269984665640564039457584007913129639935
```

Use an encrypted Foundry keystore or hardware wallet. The examples below name
the keystore `knot-deployer`:

```bash
cast wallet import knot-deployer --interactive
export DEPLOYER_ACCOUNT=knot-deployer
export DEPLOYER=0xAddressStoredInThatKeystore
```

## 1. Read-only protocol checks

Confirm the RPC is mainnet:

```bash
cast chain-id --rpc-url "$RPC_URL"
```

Expected: `143`.

Confirm Aave reports USDC flash loans enabled:

```bash
cast call "$DATA_PROVIDER" \
  "getFlashLoanEnabled(address)(bool)" "$USDC" \
  --rpc-url "$RPC_URL"
```

Expected: `true`. Stop if false.

Read the live premium; never substitute a remembered value:

```bash
export PREMIUM_BPS=$(cast call "$POOL" \
  "FLASHLOAN_PREMIUM_TOTAL()(uint128)" \
  --rpc-url "$RPC_URL")
echo "$PREMIUM_BPS"
```

Expected: a small integer in basis points. Record the value and timestamp.

Read available USDC liquidity:

```bash
cast call "$USDC" \
  "balanceOf(address)(uint256)" "$AUSDC" \
  --rpc-url "$RPC_URL"
```

Expected: a raw six-decimal balance greater than every test amount below. These
calls create no Monadscan transaction.

## 2. Deploy and verify Registry wiring

From `contracts/`, build first:

```bash
forge build
```

Expected: successful compilation with no Solidity warnings. Do not proceed if
the address-book dependency resolves to different Monad addresses.

Deploy. Leave router variables unset until step 6 if the venues are not yet
reviewed:

```bash
export OWNER="$DEPLOYER"
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --account "$DEPLOYER_ACCOUNT" \
  --slow
```

The script writes `deployments.json`. Load the addresses:

```bash
export REGISTRY=$(jq -r '."143".Registry' deployments.json)
export EXECUTOR=$(jq -r '."143".Executor' deployments.json)
export FLASH=$(jq -r '."143".FlashLoanHandler' deployments.json)
export AAVE=$(jq -r '."143".HandlerAaveV3' deployments.json)
export SWAP=$(jq -r '."143".HandlerSwap' deployments.json)
export FUNDS=$(jq -r '."143".HandlerFunds' deployments.json)
```

Check code exists at all six addresses:

```bash
for ADDRESS in "$REGISTRY" "$EXECUTOR" "$FLASH" "$AAVE" "$SWAP" "$FUNDS"; do
  cast code "$ADDRESS" --rpc-url "$RPC_URL"
done
```

Expected: every result is longer than `0x`.

Check every delegatecall handler and the Aave callback route:

```bash
for HANDLER in "$FLASH" "$AAVE" "$SWAP" "$FUNDS"; do
  cast call "$REGISTRY" "handlers(address)(bool)" "$HANDLER" --rpc-url "$RPC_URL"
done
cast call "$REGISTRY" "callers(address)(address)" "$POOL" --rpc-url "$RPC_URL"
```

Expected: four `true` results; `callers(POOL)` equals `$FLASH`.

Verify each contract on Monadscan. Constructor arguments must match the
deployment transaction. The official Monad Foundry flow is:

```bash
forge verify-contract "$REGISTRY" src/Registry.sol:Registry \
  --chain 143 --verifier etherscan \
  --etherscan-api-key "$MONADSCAN_API_KEY" \
  --constructor-args "$(cast abi-encode 'constructor(address)' "$DEPLOYER")" --watch
```

Repeat for the other five contracts using these constructor arguments:

```bash
forge verify-contract "$EXECUTOR" src/Executor.sol:Executor \
  --chain 143 --verifier etherscan --etherscan-api-key "$MONADSCAN_API_KEY" \
  --constructor-args "$(cast abi-encode 'constructor(address,address)' "$REGISTRY" "$OWNER")" --watch
forge verify-contract "$FLASH" src/FlashLoanHandler.sol:FlashLoanHandler \
  --chain 143 --verifier etherscan --etherscan-api-key "$MONADSCAN_API_KEY" \
  --constructor-args "$(cast abi-encode 'constructor(address)' "$REGISTRY")" --watch
forge verify-contract "$AAVE" src/HandlerAaveV3.sol:HandlerAaveV3 \
  --chain 143 --verifier etherscan --etherscan-api-key "$MONADSCAN_API_KEY" --watch
forge verify-contract "$SWAP" src/HandlerSwap.sol:HandlerSwap \
  --chain 143 --verifier etherscan --etherscan-api-key "$MONADSCAN_API_KEY" \
  --constructor-args "$(cast abi-encode 'constructor(address)' "$REGISTRY")" --watch
forge verify-contract "$FUNDS" src/HandlerFunds.sol:HandlerFunds \
  --chain 143 --verifier etherscan --etherscan-api-key "$MONADSCAN_API_KEY" --watch
```

On Monadscan, each deployment must show verified source and the expected
deployer. The Registry transaction list must show four `HandlerSet` events and
one `CallerSet(POOL, FLASH)` event.

## 3. Smoke test — 1 USDC

Refresh the premium and calculate Aave's half-up basis-point rounding:

```bash
export PREMIUM_BPS=$(cast call "$POOL" \
  "FLASHLOAN_PREMIUM_TOTAL()(uint128)" --rpc-url "$RPC_URL")
export BORROW=1000000
export PREMIUM=$(( (BORROW * PREMIUM_BPS + 5000) / 10000 ))
```

Record the wallet and Executor balances:

```bash
export WALLET="$DEPLOYER"
cast call "$USDC" "balanceOf(address)(uint256)" "$WALLET" --rpc-url "$RPC_URL"
cast call "$USDC" "balanceOf(address)(uint256)" "$EXECUTOR" --rpc-url "$RPC_URL"
```

Approve only the premium:

```bash
cast send "$USDC" "approve(address,uint256)" "$EXECUTOR" "$PREMIUM" \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
```

Build the hidden premium-funding action after the empty user action list:

```bash
export FUND_DATA=$(cast calldata \
  "addFunds(address,uint256)" "$USDC" "$PREMIUM")
export FLASH_DATA=$(cast calldata \
  "flashLoan(address,uint256,address[],bytes[])" \
  "$USDC" "$BORROW" "[$FUNDS]" "[$FUND_DATA]")
```

Simulate the exact call from the wallet. Empty output means success because
`execute` returns no value:

```bash
cast call "$EXECUTOR" \
  "execute(address[],bytes[])" "[$FLASH]" "[$FLASH_DATA]" \
  --from "$WALLET" --rpc-url "$RPC_URL"
```

Then send:

```bash
cast send "$EXECUTOR" \
  "execute(address[],bytes[])" "[$FLASH]" "[$FLASH_DATA]" \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
```

Expected balance outcome:

- wallet USDC decreases by exactly `$PREMIUM`;
- wallet allowance to Executor is zero;
- Executor USDC and native MON balances are zero.

```bash
cast call "$USDC" "balanceOf(address)(uint256)" "$EXECUTOR" --rpc-url "$RPC_URL"
cast balance "$EXECUTOR" --rpc-url "$RPC_URL"
cast call "$USDC" "allowance(address,address)(uint256)" \
  "$WALLET" "$EXECUTOR" --rpc-url "$RPC_URL"
```

On Monadscan, inspect the successful transaction and confirm USDC transfers:
Pool → Executor for `1,000,000`, wallet → Executor for `$PREMIUM`, and Executor
→ Pool for `1,000,000 + PREMIUM`. The Aave Pool call must show
`flashLoanSimple`.

## 4. Aave round trip

Use 1 USDC again or another deliberately small amount. Refresh premium and
approve exactly as in step 3.

```bash
export SUPPLY_DATA=$(cast calldata \
  "supply(address,uint256)" "$USDC" "$MAX_UINT")
export WITHDRAW_DATA=$(cast calldata \
  "withdraw(address,uint256)" "$USDC" "$MAX_UINT")
export FUND_DATA=$(cast calldata \
  "addFunds(address,uint256)" "$USDC" "$PREMIUM")
export FLASH_DATA=$(cast calldata \
  "flashLoan(address,uint256,address[],bytes[])" \
  "$USDC" "$BORROW" "[$AAVE,$AAVE,$FUNDS]" \
  "[$SUPPLY_DATA,$WITHDRAW_DATA,$FUND_DATA]")
```

Simulate, then send the exact same call:

```bash
cast call "$EXECUTOR" \
  "execute(address[],bytes[])" "[$FLASH]" "[$FLASH_DATA]" \
  --from "$WALLET" --rpc-url "$RPC_URL"
cast send "$EXECUTOR" \
  "execute(address[],bytes[])" "[$FLASH]" "[$FLASH_DATA]" \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
```

Expected: wallet net change is only `-$PREMIUM`; Executor USDC, aUSDC, and MON
are all zero; allowance is zero.

```bash
cast call "$USDC" "balanceOf(address)(uint256)" "$EXECUTOR" --rpc-url "$RPC_URL"
cast call "$AUSDC" "balanceOf(address)(uint256)" "$EXECUTOR" --rpc-url "$RPC_URL"
cast balance "$EXECUTOR" --rpc-url "$RPC_URL"
```

On Monadscan confirm, in order: flash transfer, Aave `Supply`, aUSDC mint, Aave
`Withdraw`, aUSDC burn, premium funding, and repayment. No aUSDC transfer should
remain at the Executor.

## 5. Deleverage drill — repay debt from collateral

The repay action pays variable-rate debt for the initiating wallet, so this
drill needs a live position. Create a small one outside Knot with the same
wallet: supply USDC collateral, then borrow USDC against it (rate mode 2 is
variable, the only mode the Pool accepts):

```bash
export SUPPLY_AMOUNT=2000000
export DEBT=700000
cast send "$USDC" "approve(address,uint256)" "$POOL" "$SUPPLY_AMOUNT" \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
cast send "$POOL" "supply(address,uint256,address,uint16)" \
  "$USDC" "$SUPPLY_AMOUNT" "$WALLET" 0 \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
cast send "$POOL" "borrow(address,uint256,uint256,uint16,address)" \
  "$USDC" "$DEBT" 2 0 "$WALLET" \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
```

Confirm the variable debt exists; the drill assumes it stays above `$BORROW`:

```bash
cast call "$VDUSDC" "balanceOf(address)(uint256)" "$WALLET" --rpc-url "$RPC_URL"
```

Refresh the premium exactly as in step 3, then approve the premium in USDC and
the collateral in aUSDC. Fund slightly more collateral than the flash amount so
aToken interest rounding can never leave the repayment short:

```bash
export BORROW=500000
export PREMIUM_BPS=$(cast call "$POOL" \
  "FLASHLOAN_PREMIUM_TOTAL()(uint128)" --rpc-url "$RPC_URL")
export PREMIUM=$(( (BORROW * PREMIUM_BPS + 5000) / 10000 ))
export COLLATERAL_IN=600000
cast send "$USDC" "approve(address,uint256)" "$EXECUTOR" "$PREMIUM" \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
cast send "$AUSDC" "approve(address,uint256)" "$EXECUTOR" "$COLLATERAL_IN" \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
```

Order matters: repay runs first so the debt is cleared before the wallet's
aUSDC moves, because Aave checks the sender's health factor on every aToken
transfer.

```bash
export REPAY_DATA=$(cast calldata \
  "repay(address,uint256)" "$USDC" "$MAX_UINT")
export COLLATERAL_DATA=$(cast calldata \
  "addFunds(address,uint256)" "$AUSDC" "$COLLATERAL_IN")
export WITHDRAW_DATA=$(cast calldata \
  "withdraw(address,uint256)" "$USDC" "$MAX_UINT")
export FUND_DATA=$(cast calldata \
  "addFunds(address,uint256)" "$USDC" "$PREMIUM")
export FLASH_DATA=$(cast calldata \
  "flashLoan(address,uint256,address[],bytes[])" \
  "$USDC" "$BORROW" "[$AAVE,$FUNDS,$AAVE,$FUNDS]" \
  "[$REPAY_DATA,$COLLATERAL_DATA,$WITHDRAW_DATA,$FUND_DATA]")
```

Simulate, then send the exact same call:

```bash
cast call "$EXECUTOR" \
  "execute(address[],bytes[])" "[$FLASH]" "[$FLASH_DATA]" \
  --from "$WALLET" --rpc-url "$RPC_URL"
cast send "$EXECUTOR" \
  "execute(address[],bytes[])" "[$FLASH]" "[$FLASH_DATA]" \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
```

Expected balance outcome:

- wallet variable debt decreases by `$BORROW`, minus block-level interest
  accrual;
- wallet aUSDC decreases by exactly `$COLLATERAL_IN`;
- wallet USDC changes by about `COLLATERAL_IN - BORROW - PREMIUM`, moving a few
  units with aToken interest rounding;
- Executor USDC, aUSDC and MON balances are zero; both allowances are zero.

```bash
cast call "$VDUSDC" "balanceOf(address)(uint256)" "$WALLET" --rpc-url "$RPC_URL"
cast call "$USDC" "balanceOf(address)(uint256)" "$EXECUTOR" --rpc-url "$RPC_URL"
cast call "$AUSDC" "balanceOf(address)(uint256)" "$EXECUTOR" --rpc-url "$RPC_URL"
cast balance "$EXECUTOR" --rpc-url "$RPC_URL"
cast call "$USDC" "allowance(address,address)(uint256)" \
  "$WALLET" "$EXECUTOR" --rpc-url "$RPC_URL"
cast call "$AUSDC" "allowance(address,address)(uint256)" \
  "$WALLET" "$EXECUTOR" --rpc-url "$RPC_URL"
```

On Monadscan confirm, in order: flash transfer, Aave `Repay` with the wallet as
`user` and the Executor as `repayer`, aUSDC transfer wallet → Executor, Aave
`Withdraw`, premium funding, repayment and the final USDC sweep. If the
remaining debt was below `$BORROW`, Aave caps the repayment and the surplus
principal returns to the wallet in the sweep; that is expected, not a failure.
With no variable USDC debt at all the Pool rejects the repay and the Executor
bubbles it as `InnerActionFailed`, so the simulation fails and nothing settles.

The repay cube is also available in the UI. It always funds the full repayment
(`BORROW + PREMIUM`) from the wallet, because the v1 USDC-only interface cannot
move aUSDC collateral; whatever Aave does not pull is swept back in the same
transaction. The complete deleverage above stays a cast-level drill until the
UI can fund aTokens.

## 6. Two-hop swap — Uniswap V3 testing mode

The frontend fixes swaps to Uniswap V3 `SwapRouter02` and obtains quotes from
Uniswap `QuoterV2`. Allowlist the reviewed official router once as Registry
owner:

```bash
export UNISWAP_ROUTER=0xfe31f71c1b106eac32f1a19239c9a9a72ddfb900
cast send "$REGISTRY" "setRouter(address,bool)" "$UNISWAP_ROUTER" true \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
cast call "$REGISTRY" "routers(address)(bool)" "$UNISWAP_ROUTER" \
  --rpc-url "$RPC_URL"
```

Expected: the read returns `true`; Monadscan shows one `RouterSet` event with
`allowed = true`.

In the UI:

1. Select **Two-hop swap**.
2. Keep a small flash amount such as **1 USDC**.
3. Confirm action 1 is USDC → WETH and action 2 is WETH → USDC.
4. Keep **100% of previous output** enabled and slippage at **0.5%**.
5. Wait for both estimated outputs to appear.
6. Approve the exact premium, then wait for **Simulation passed**.
7. Send only after simulation passes.

The second route intentionally spends action 1's minimum guaranteed WETH
output. If action 1 returns more, the remainder is swept to the wallet. Expected:
the transaction either atomically succeeds and repays or fully reverts. On
success, Executor USDC, WETH, and MON balances are zero.

On Monadscan confirm two calls to exactly `$UNISWAP_ROUTER`, the flash-loan
repayment, and final token sweeps. Wallet net USDC is
`final swap output - BORROW - PREMIUM`, plus any conservative WETH remainder.
If the call fails `InsufficientOutput`, obtain a fresh quote; do not blindly
widen slippage.

## 7. Pause / unpause drill

Pause as owner:

```bash
cast send "$EXECUTOR" "pause()" \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
cast call "$EXECUTOR" "paused()(bool)" --rpc-url "$RPC_URL"
```

Expected: `true`; Monadscan shows `Paused(OWNER)`.

Rebuild the harmless smoke-test calldata so no stale swap quote is involved:

```bash
export FUND_DATA=$(cast calldata \
  "addFunds(address,uint256)" "$USDC" "$PREMIUM")
export FLASH_DATA=$(cast calldata \
  "flashLoan(address,uint256,address[],bytes[])" \
  "$USDC" "$BORROW" "[$FUNDS]" "[$FUND_DATA]")
```

Repeat the smoke-test `cast call`. Expected: revert with `EnforcedPause()`. Do
not broadcast.

Unpause:

```bash
cast send "$EXECUTOR" "unpause()" \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"
cast call "$EXECUTOR" "paused()(bool)" --rpc-url "$RPC_URL"
cast call "$EXECUTOR" \
  "execute(address[],bytes[])" "[$FLASH]" "[$FLASH_DATA]" \
  --from "$WALLET" --rpc-url "$RPC_URL"
```

Expected: `false`, Monadscan shows `Unpaused(OWNER)`, and the simulation is
allowed again. The drill is complete; no final broadcast is needed.

## Frontend handoff

From the repository root:

```bash
cp web/.env.example web/.env.local
pnpm install
pnpm --dir web test
pnpm --dir web dev
```

Open the app, connect on chain 143, and repeat steps 3, 4, 6 and 7 with the
matching presets. Step 5 stays cast-driven; in the UI, verify the repay cube
with a small wallet-funded repayment against the position from step 5 instead.
Before every send, verify that the UI says “Simulation passed”, the approval
amount equals the exact funding requirement, and the Monadscan link points to
mainnet.

# Monad mainnet manual verification

This maintainer-operated runbook complements the local Foundry unit tests.
Follow it in order, use a dedicated wallet, and stop on the first unexpected
result. Commands assume Foundry (`cast`, `forge`) and `jq` are installed.

All addresses below are Monad mainnet:

```bash
export RPC_URL=https://rpc.monad.xyz
export POOL=0x69a5F9AD4f96ebf0a0C792dD42a01cC5C0102fef
export DATA_PROVIDER=0xB65A68B98274ef7D9a60E0C0747dD1BEc3D32fad
export USDC=0x754704Bc059F8C67012fEd69BC8A327a5aafb603
export AUSDC=0x35a73BAcb179d3740395A3ceCc87FF2e581d6042
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

Deploy. Choose a reviewed, non-zero timelock delay in seconds. Leave router
variables unset until step 5 if the venues are not yet reviewed:

```bash
export OWNER="$DEPLOYER"
export TIMELOCK_DELAY=ReviewedNonZeroDelayInSeconds
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --account "$DEPLOYER_ACCOUNT" \
  --slow
```

The script writes `deployments.json`. Load the addresses:

```bash
export REGISTRY=$(jq -r '."143".Registry' deployments.json)
export REGISTRY_TIMELOCK=$(jq -r '."143".RegistryTimelock' deployments.json)
export EXECUTOR=$(jq -r '."143".Executor' deployments.json)
export FLASH=$(jq -r '."143".FlashLoanHandler' deployments.json)
export AAVE=$(jq -r '."143".HandlerAaveV3' deployments.json)
export SWAP=$(jq -r '."143".HandlerSwap' deployments.json)
export FUNDS=$(jq -r '."143".HandlerFunds' deployments.json)
```

Check code exists at all seven addresses:

```bash
for ADDRESS in "$REGISTRY" "$REGISTRY_TIMELOCK" "$EXECUTOR" "$FLASH" "$AAVE" "$SWAP" "$FUNDS"; do
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

Check the Registry ownership and timelock security boundary:

```bash
export ZERO_ADDRESS=0x0000000000000000000000000000000000000000
export DEFAULT_ADMIN_ROLE=0x0000000000000000000000000000000000000000000000000000000000000000
export PROPOSER_ROLE=$(cast keccak "PROPOSER_ROLE")
export CANCELLER_ROLE=$(cast keccak "CANCELLER_ROLE")
export EXECUTOR_ROLE=$(cast keccak "EXECUTOR_ROLE")

cast call "$REGISTRY" "owner()(address)" --rpc-url "$RPC_URL"
cast call "$REGISTRY_TIMELOCK" "getMinDelay()(uint256)" --rpc-url "$RPC_URL"
cast call "$REGISTRY_TIMELOCK" "hasRole(bytes32,address)(bool)" \
  "$DEFAULT_ADMIN_ROLE" "$REGISTRY_TIMELOCK" --rpc-url "$RPC_URL"
cast call "$REGISTRY_TIMELOCK" "hasRole(bytes32,address)(bool)" \
  "$DEFAULT_ADMIN_ROLE" "$OWNER" --rpc-url "$RPC_URL"
cast call "$REGISTRY_TIMELOCK" "hasRole(bytes32,address)(bool)" \
  "$PROPOSER_ROLE" "$OWNER" --rpc-url "$RPC_URL"
cast call "$REGISTRY_TIMELOCK" "hasRole(bytes32,address)(bool)" \
  "$CANCELLER_ROLE" "$OWNER" --rpc-url "$RPC_URL"
cast call "$REGISTRY_TIMELOCK" "hasRole(bytes32,address)(bool)" \
  "$EXECUTOR_ROLE" "$ZERO_ADDRESS" --rpc-url "$RPC_URL"
```

Expected: `Registry.owner()` equals `$REGISTRY_TIMELOCK`; the delay equals
`$TIMELOCK_DELAY`; the timelock itself is the only default admin; `$OWNER` is
the proposer and canceller; and the zero address has the executor role, making
execution permissionless after the delay.

Verify each contract on Monadscan. Constructor arguments must match the
deployment transaction. The official Monad Foundry flow is:

```bash
forge verify-contract "$REGISTRY" src/Registry.sol:Registry \
  --chain 143 --verifier etherscan \
  --etherscan-api-key "$MONADSCAN_API_KEY" \
  --constructor-args "$(cast abi-encode 'constructor(address)' "$DEPLOYER")" --watch
```

Verify the timelock with its explicit delay and proposer:

```bash
forge verify-contract "$REGISTRY_TIMELOCK" src/RegistryTimelock.sol:RegistryTimelock \
  --chain 143 --verifier etherscan \
  --etherscan-api-key "$MONADSCAN_API_KEY" \
  --constructor-args "$(cast abi-encode 'constructor(uint256,address)' "$TIMELOCK_DELAY" "$OWNER")" --watch
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
deployer. The Registry transaction list must show four `HandlerSet` events, one
`CallerSet(POOL, FLASH)` event, and ownership transferred from `$DEPLOYER` to
`$REGISTRY_TIMELOCK`. The timelock deployment must show its non-zero
`MinDelayChange` and expected role grants.

### Existing Registry migration instead of fresh deployment

For the existing Registry, the committed `RegistryTimelock` address is
intentionally zero until maintainers complete the migration. Do not run the
management script against that placeholder.

Preview the migration with the current Registry owner, then broadcast only
after reviewing every printed value:

```bash
TIMELOCK_DELAY="$TIMELOCK_DELAY" \
forge script script/MigrateRegistryTimelock.s.sol:MigrateRegistryTimelock \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"

DRY_RUN=false TIMELOCK_DELAY="$TIMELOCK_DELAY" \
forge script script/MigrateRegistryTimelock.s.sol:MigrateRegistryTimelock \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT" --broadcast --slow
```

Expected: the preview changes nothing. The live run deploys one timelock and
transfers Registry ownership to it. Re-run every ownership, delay, role, source,
and event check above. Only after both transactions are confirmed should a
maintainer replace the zero address in `deployments.json` and regenerate the web
bindings.

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

## 5. Two-hop swap — Uniswap V3 testing mode

The frontend fixes swaps to Uniswap V3 `SwapRouter02` and obtains quotes from
Uniswap `QuoterV2`. Queue the reviewed official router through the Registry
timelock. Use one unique salt for this exact operation:

```bash
export UNISWAP_ROUTER=0xfe31f71c1b106eac32f1a19239c9a9a72ddfb900
export TIMELOCK_SALT=$(cast keccak "manual-uniswap-router-v1")

TIMELOCK_ACTION=queue TIMELOCK_SALT="$TIMELOCK_SALT" \
REGISTRY_ACTION=set-router ROUTER="$UNISWAP_ROUTER" ALLOWED=true \
forge script script/ManageRegistry.s.sol:ManageRegistry \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT"

DRY_RUN=false TIMELOCK_ACTION=queue TIMELOCK_SALT="$TIMELOCK_SALT" \
REGISTRY_ACTION=set-router ROUTER="$UNISWAP_ROUTER" ALLOWED=true \
forge script script/ManageRegistry.s.sol:ManageRegistry \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT" --broadcast --slow

TIMELOCK_ACTION=status TIMELOCK_SALT="$TIMELOCK_SALT" \
REGISTRY_ACTION=set-router ROUTER="$UNISWAP_ROUTER" ALLOWED=true \
forge script script/ManageRegistry.s.sol:ManageRegistry --rpc-url "$RPC_URL"
```

Expected: the live queue emits `CallScheduled` and `CallSalt`; status is
`waiting` and prints the same operation ID and an activation timestamp. A live
execute before that timestamp must revert and leave the router disabled. Wait
until status is `ready`, then execute. Because the executor role is open, the
sender need not be the proposer:

```bash
DRY_RUN=false TIMELOCK_ACTION=execute TIMELOCK_SALT="$TIMELOCK_SALT" \
REGISTRY_ACTION=set-router ROUTER="$UNISWAP_ROUTER" ALLOWED=true \
forge script script/ManageRegistry.s.sol:ManageRegistry \
  --rpc-url "$RPC_URL" --account "$DEPLOYER_ACCOUNT" --broadcast --slow

cast call "$REGISTRY" "routers(address)(bool)" "$UNISWAP_ROUTER" \
  --rpc-url "$RPC_URL"
```

Expected: status becomes `done`, the read returns `true`, and Monadscan shows
one `CallExecuted` plus one `RouterSet` event with `allowed = true`.

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

## 6. Pause / unpause drill

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

Open the app, connect on chain 143, and repeat steps 3–6 with the matching
presets. Before every send, verify that the UI says “Simulation passed”, the
approval amount equals the exact funding requirement, and the Monadscan link
points to mainnet.

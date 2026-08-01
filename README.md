# Knot

> [!WARNING]
> Knot executes transactions with real assets on Monad mainnet and has not
> undergone an independent security audit. Review every transaction, use only
> amounts you are comfortable with, and start small. The software is provided
> as-is under the [MIT License](LICENSE).

Knot is a deliberately small combo executor for Monad mainnet. It
opens an Aave v3 simple flash loan, runs up to two user-selected DeFi actions,
repays, and returns every touched asset to the initiating wallet in one atomic
transaction.

The v1 UI is USDC-only. The contracts are asset-generic and intentionally easy
to extend with new handler contracts.

[Contributing](CONTRIBUTING.md) · [Support](SUPPORT.md) · [Security](SECURITY.md) ·
[Code of Conduct](CODE_OF_CONDUCT.md) · [MIT License](LICENSE)

## Repository

```text
knot/
├── contracts/  Foundry contracts, deployment and calldata fixture scripts
└── web/        Next.js App Router dApp and manifest-driven cube registry
```

There are no automated Solidity tests by design. Mainnet verification is the
manual test suite. The TypeScript encoder does have unit tests because ABI drift
would otherwise be easy to miss.

## Quick start

Normal contributor setup does not broadcast transactions or require a funded
wallet.

Requirements:

- Node.js 22.14.0, pinned in `.nvmrc` and `.node-version`
- pnpm 10.34.0 through Corepack
- Foundry
- Git

```bash
nvm install
nvm use
corepack enable
corepack prepare pnpm@10.34.0 --activate
pnpm setup
cp web/.env.example web/.env.local
```

Add a Reown project ID to `web/.env.local`, then run:

```bash
pnpm dev
```

Open `http://localhost:3000`. UI-only contributors can skip Foundry; follow the
[web-only setup](CONTRIBUTING.md#web-only-setup).

Before opening a pull request:

```bash
pnpm check
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the project layout, focused
workflows, validation commands, and pull-request expectations.

## Architecture

```text
Wallet
  │  Executor.execute([FlashLoanHandler], [flashLoan(...)])
  ▼
Executor ──delegatecall──► FlashLoanHandler ──call──► Aave v3 Pool
  ▲                                                   │
  │ fallback: Pool → registered FlashLoanHandler      │ executeOperation
  └───────────────────────────────────────────────────┘
                 │ delegatecall, whitelist checked
                 ├── HandlerSwap      → allowlisted router
                 ├── HandlerAaveV3    → Aave supply / withdraw / repay
                 └── HandlerFunds     → exact wallet funding / return

Final post-process:
  clear temporary approvals → sweep tracked ERC-20s and MON → assert zero balances
```

- `Registry` owns the handler, callback-caller, and router allowlists.
- `Executor` is the only user entry point. It stores the original sender in a
  namespaced slot, uses that slot as its reentrancy guard, and routes registered
  callbacks through `fallback`.
- `FlashLoanHandler` checks both the Pool caller and Aave `initiator`, then runs
  the inner handler list.
- `HandlerBase` owns the shared touched-token and temporary-approval stack.

There is no proxy or upgrade mechanism. A protocol upgrade is a fresh deployment.

### Legacy contract identifiers

The current mainnet contracts were deployed before the project was renamed to
Knot. The Solidity interface name `IMoncomboRegistry` and storage namespace
`moncombo.execution.storage.v1` are intentionally preserved so the published
source continues to match the deployed bytecode. They are internal compatibility
identifiers, not the public project name. Changing either requires a reviewed
redeployment and new frontend addresses.

## How a combo is encoded

The outer call contains one whitelisted handler:

```solidity
Executor.execute(
  [address(flashLoanHandler)],
  [abi.encodeCall(
    FlashLoanHandler.flashLoan,
    (asset, amount, innerHandlers, innerDatas)
  )]
);
```

The inner arrays are positional. `innerHandlers[i]` receives
`innerDatas[i]` by `delegatecall`. When an action amount is
`type(uint256).max`, the handler consumes its complete current input-token
balance. The web encoder appends a hidden `HandlerFunds.addFunds(asset, premium)`
as the final inner operation. Keeping premium funding last is important: the
first max-input action sees the flash-loan principal, not principal plus premium.

`web/src/lib/encoding.ts` mirrors this layout. The fixture in
`contracts/script/PrintCalldata.s.sol` is hashed and asserted by Vitest.

## Security model

Knot is designed around the lesson from the 2021 Furucombo exploit:
untrusted delegatecall targets combined with user standing approvals are
catastrophic.

- Every outer handler, inner handler, and callback handler is checked against
  `Registry.handlers`.
- A router is called, never delegatecalled, and must be in `Registry.routers`.
  The launch UI fixes this to Uniswap V3 `SwapRouter02`; the generic contract
  parameter remains available for future reviewed integrations.
- The Aave callback must come from the canonical Monad Pool and must report the
  Executor itself as `initiator`.
- The cached sender slot prevents nested `execute` calls and remains available
  while Aave is the immediate caller.
- All temporary approvals are reset to zero.
- Every touched token is swept to the original sender, then its Executor balance
  is asserted to be zero. Native MON is handled the same way.
- `execute` and callback routing are pausable by the owner.
- Direct native transfers outside an active combo revert.

**Never grant the Executor a standing approval.** The app requests an exact USDC
allowance for the current combo only. If a transaction is abandoned after
approval, revoke that residual allowance before doing anything else.

The allowlist owner is a security boundary. Use a hardware-backed multisig for
production ownership, review bytecode before adding a handler, and allowlist
only routers whose calldata and recipient behavior are understood.

## Contracts: build and deploy

Compilation uses the pinned dependency installer and never broadcasts:

```bash
pnpm contracts:deps
pnpm contracts:build
```

The installer pins OpenZeppelin Contracts 5.4.0, Aave Address Book 4.61.2, and
forge-std 1.16.2. Contract changes must also pass
`pnpm check:contracts`.

Deployment requires Monad Foundry, Git, and a funded Monad mainnet deployer. It
is a separate maintainer-operated workflow.

Import an encrypted keystore once:

```bash
cast wallet import knot-deployer --interactive
```

The deployment order and wiring are automated. `OWNER`, `ROUTER_A`, and
`ROUTER_B` are optional. If `OWNER` is omitted, ownership stays with the
keystore account. Omit routers until venue addresses and calldata formats have
been reviewed.

```bash
cd contracts
forge script script/Deploy.s.sol:Deploy \
  --rpc-url monad \
  --account knot-deployer \
  --broadcast \
  --slow
```

Run this yourself; the repository never broadcasts it. The script writes
`contracts/deployments.json` keyed by chain ID and logs all six addresses.
Continue with [MANUAL_TESTING.md](MANUAL_TESTING.md) before using the app.

The script uses argument-free `vm.startBroadcast()`, so Foundry can also select
a Ledger (`--ledger`) or an explicit private key (`--private-key`) without
changing Solidity code.

## Web app

The checked package versions were resolved from the registry at implementation
time. RainbowKit and ConnectKit did not accept stable wagmi 3 without a
downgrade, so the app uses Reown AppKit with its wagmi adapter. It supplies
injected-wallet and WalletConnect flows. WalletConnect requires a free Reown
project ID.

```bash
cp web/.env.example web/.env.local
# Replace NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID with a real Reown project ID.
# Keep NEXT_PUBLIC_APP_URL=http://localhost:3000 for local development.
pnpm install --frozen-lockfile
pnpm --dir web dev
```

Restart the development server after changing either public environment value;
Next.js embeds them into the client bundle at startup.

The launch swap cube uses Uniswap V3 on Monad with the official `SwapRouter02`,
`QuoterV2`, and the active USDC/WETH 0.3% pool. Users select tokens, an amount,
and slippage; the app obtains the quote and builds router calldata internally.
For a chained second swap, it spends the first swap's guaranteed minimum output.
Any better-than-minimum remainder is swept back to the user's wallet.

The deployed Registry owner must allowlist the fixed router once:

```bash
cast send 0x5bb4FffD2DfD3a7B6323FB193542bcCbEC7BA846 \
  "setRouter(address,bool)" \
  0xfe31f71c1b106eac32f1a19239c9a9a72ddfb900 true \
  --rpc-url https://rpc.monad.xyz \
  --account knot-deployer
```

The `predev` and `prebuild` hooks generate `web/src/generated/contracts.ts`
directly from `contracts/deployments.json` and Foundry `out/` ABIs. Placeholder
addresses render an explicit “contracts not deployed yet” state. After a real
deployment, rerun the app unchanged.

Production checks:

```bash
pnpm --dir web test
pnpm --dir web build
```

## Adding a frontend cube

Each file in `web/src/cubes/` exports a manifest with:

- `name`, `description`, and `icon` for presentation;
- `handlerName` for deployment lookup;
- typed `inputs` rendered by the generic cube form;
- `encode(inputs, deployments)` returning exactly `{ handler, data }`.

Add the manifest to `web/src/cubes/index.ts`. Do not add special-case UI code.
If the cube introduces a new ABI, add the contract name to
`web/scripts/codegen.mjs` and add an encoding fixture.

## Writing your own handler

Contributed handlers must satisfy all of these invariants:

1. Inherit `HandlerBase`; assume every external action function runs in the
   Executor's storage and address context.
2. Be stateless. Use immutables/constants only. Never write ordinary handler
   storage; it would write into the Executor.
3. Register every ERC-20 read, received, spent, minted, or burned with
   `_trackToken`.
4. Register every approval with `_trackApproval` and use OpenZeppelin
   `SafeERC20.forceApprove`. Prefer exact approvals and clear them immediately
   when possible.
5. Resolve `type(uint256).max` as the complete current input balance.
6. Never delegatecall a user-provided address. New delegatecall targets must be
   Registry handlers; external targets need their own explicit Registry
   allowlist.
7. Derive the user only from `_comboSender()`, never from `msg.sender` during a
   callback.
8. Validate callback caller and initiator fields independently.
9. Return funds to the Executor context so final post-processing can account for
   them. Do not strand dust.
10. Add NatSpec, update the deploy script and codegen list, and extend both the
    manual runbook and TypeScript encoding fixtures.

Keep handlers small. A separate handler per protocol is easier to review and
revoke than a generic arbitrary-call cube.

## Contributing

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), use
the issue forms for reproducible bugs or scoped proposals, and run
`pnpm check` before submitting a pull request.

Do not report vulnerabilities publicly. Follow [SECURITY.md](SECURITY.md) and
use GitHub private vulnerability reporting.

## License

[MIT](LICENSE)

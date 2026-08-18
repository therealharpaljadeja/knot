# Contributing to Knot

Thanks for helping make Knot safer and more useful. Contributions are
welcome across Solidity, the web app, documentation, design, and security
review.

Knot executes user-selected actions with real assets. Small changes can
alter the security boundary, so favor focused pull requests and explicit
reasoning over clever abstractions.

## How work lands

All changes go through a pull request, and every pull request needs an approving
review from a code owner (@therealharpaljadeja or @portdeveloper) before it can
merge. Direct pushes to the default branch are turned off. A merge means the
work was read and accepted, not just that it was opened.

Knot is a MOST pool repo (https://most.devnads.com). Claim an issue with a
comment before you write code and wait for a maintainer to approve the claim;
one claimed issue per person at a time, across all pool repos. Claiming a
second issue while you already hold one voids all of your claims, and a claim
with no PR or progress update for 7 days gets released. If you contribute with
an AI agent, the agent must read and follow https://most.devnads.com/agents.md.

## Before you start

- Read the [architecture and security model](README.md#security-model).
- Search existing issues before opening a new one.
- For vulnerabilities, follow [SECURITY.md](SECURITY.md) instead of opening a
  public issue.
- Never use real keys, seed phrases, private RPC URLs, or funded keystores in
  examples, fixtures, screenshots, or logs.

No contributor command in this guide broadcasts a transaction. Deployment and
manual mainnet verification are maintainer-operated workflows.

## Toolchain

- Git
- Node.js 22.14.0 (the `.nvmrc` and `.node-version` files pin it)
- pnpm 10.34.0 through Corepack
- Foundry; Monad Foundry is required for deployment, while current stable
  Foundry is sufficient for compilation

With `nvm` installed:

```bash
nvm install
nvm use
corepack enable
corepack prepare pnpm@10.34.0 --activate
```

## Quick start

For the complete contract and web toolchain:

```bash
pnpm setup
cp web/.env.example web/.env.local
```

Set `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` in `web/.env.local` to a Reown
project ID, then start the app:

```bash
pnpm dev
```

Open `http://localhost:3000`.

### Web-only setup

UI contributors can avoid installing Foundry:

```bash
pnpm install --frozen-lockfile
cp web/.env.example web/.env.local
pnpm dev
```

The app uses the committed generated contract bindings when Foundry artifacts
are absent. Do not edit `web/src/generated/contracts.ts` by hand.

## Common commands

| Command | Purpose |
| --- | --- |
| `pnpm dev` | Run the Next.js development server |
| `pnpm test` | Run Vitest once |
| `pnpm --dir web test:watch` | Run Vitest in watch mode |
| `pnpm --dir web typecheck` | Type-check the web app |
| `pnpm contracts:fmt` | Format Solidity |
| `pnpm contracts:build` | Compile contracts without broadcasting |
| `pnpm contracts:test` | Run focused local Foundry unit tests |
| `pnpm check:web` | Test, type-check, and build the web app |
| `pnpm check:contracts` | Check Solidity formatting, compile, and test |
| `pnpm check` | Run the complete local validation suite |

## Project layout

```text
contracts/
  src/       Executor, Registry, and action handlers
  script/    Deployment and cross-language calldata fixture scripts
web/
  src/app/   Single-page combo builder
  src/cubes/ Manifest-driven action cubes
  src/lib/   Encoding, quoting, amount, and error utilities
  scripts/   Foundry artifact and deployment code generation
```

## Making contract changes

Contracts are deliberately small and non-upgradeable. Before changing them:

1. Read `HandlerBase`, `Executor`, and `Registry`.
2. Preserve every invariant in
   [Writing your own handler](README.md#writing-your-own-handler).
3. Preserve the legacy `IMoncomboRegistry` name and
   `moncombo.execution.storage.v1` namespace while the current deployment is
   supported. Renaming them requires a fresh deployment.
4. Do not add arbitrary calls or delegatecalls.
5. Keep approvals exact and temporary.
6. Update NatSpec, deployment wiring, code generation, and the manual runbook.
7. Run:

```bash
pnpm contracts:fmt
pnpm check:contracts
pnpm --dir web codegen
pnpm check:web
```

Focused local Foundry unit tests are required for contract state machines,
authorization boundaries, and other behavior that can be verified without a
fork. Knot v1 intentionally has no contributor-operated fork or mainnet test
suite. Maintainers perform the ordered live checks in
[MANUAL_TESTING.md](MANUAL_TESTING.md) with small amounts after review.

## Adding or changing a cube

The frontend extension point is `web/src/cubes/`. A cube manifest owns its
metadata, typed inputs, and ABI encoding.

1. Add or update the manifest.
2. Export it from `web/src/cubes/index.ts`.
3. Add encoding coverage in Vitest.
4. If an ABI changes, compile contracts and run
   `pnpm --dir web codegen`.
5. Run `pnpm check:web`.

Keep protocol-specific complexity out of the generic canvas. A user should only
see inputs they can reasonably understand and verify.

## Pull requests

- Every pull request must be linked to an existing issue. Open the issue first,
  agree on the problem and scope, then submit the implementation.
- Use `Closes #123` in the pull-request description so GitHub links the work and
  closes the issue when the pull request merges.
- Pull requests without a linked issue may be closed so discussion can happen
  before implementation.
- Keep each pull request focused on one problem.
- Explain the user-facing behavior and security impact.
- Include screenshots for visible UI changes.
- Add or update documentation when behavior changes.
- Run `pnpm check`, or clearly state which checks could not be run and why.
- Do not include generated caches, dependency directories, `.env.local`,
  keystores, broadcast artifacts, or private configuration.
- Do not broadcast deployments or mainnet tests as part of a pull request.

Maintainers may ask for a smaller change set or additional security reasoning
before reviewing implementation details.

## Community

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).
General usage questions belong in GitHub Discussions when enabled; reproducible
bugs and scoped feature proposals belong in Issues.

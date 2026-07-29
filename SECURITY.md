# Security policy

Knot is experimental, unaudited mainnet software. Treat every contract and
frontend release as security-sensitive.

## Supported versions

Security fixes are applied to the latest code on the default branch. Older
deployments are immutable and cannot be patched; a contract fix requires a new
deployment and updated frontend configuration.

## Reporting a vulnerability

Do not open a public issue, discussion, or pull request for a suspected
vulnerability.

Use GitHub's private vulnerability reporting flow:

1. Open the repository's **Security** tab.
2. Select **Report a vulnerability**.
3. Include affected files or contracts, impact, prerequisites, and a minimal
   reproduction.

If private vulnerability reporting is unavailable, contact a maintainer through
a non-public channel listed on their GitHub profile and ask for a secure
reporting channel. Do not send exploit details in the first message.

Please remove private keys, seed phrases, personal wallet information, and
third-party secrets from all reports. Transaction hashes and contract addresses
are public but may still reveal your activity.

## Research guidelines

- Do not test against wallets or funds you do not own.
- Do not exploit the production deployment or attempt to move user funds.
- Prefer local analysis and exact-call simulation.
- Mainnet validation must use your own wallet, small amounts, and the ordered
  manual runbook.
- Allow maintainers reasonable time to investigate before disclosure.

We aim to acknowledge complete reports within three business days and provide a
status update within fourteen days. These are response targets, not a guarantee
of resolution.

## In scope

- Registry allowlist bypasses
- Unauthorized delegatecalls or callback routing
- Sender-slot or reentrancy failures
- Approval, balance-sweep, or token-tracking failures
- Incorrect flash-loan repayment or premium handling
- Frontend encoding that differs from the reviewed Solidity ABI
- Transaction simulation or approval flows that can mislead users
- Supply-chain or secret-exposure issues in this repository

General support questions and feature requests are not security reports.

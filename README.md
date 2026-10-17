# Robobet (ROBOBET)

A fixed-supply ERC-20 for the IdentityMD custom token launch. The complete supply is minted once to the immediate deployer in the constructor.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `Robobet` |
| Source | `src/Robobet.sol` |
| Foundry artifact | `out/Robobet.sol/Robobet.json` |
| Name | `Robobet` |
| Symbol | `ROBOBET` |
| Decimals | `18` |
| Human-readable supply | `1,000,000,000 ROBOBET` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None (`[]`) |
| Deployment ETH value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Intended launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |
| Linked libraries | None |

The constructor does not call external contracts. It needs no owner address, oracle, router, key, environment variable, or post-deployment initialization. The launch can deploy the creation bytecode without appending constructor arguments.

When the launch factory uses CREATE or CREATE2, the factory receives all tokens. An EOA deploying directly receives all tokens instead. `tx.origin` is never used. A wrapper that creates the token would itself receive the supply, so the launch must use the intended factory as the immediate creator.

## Behavior and assumptions

The requested token uses standard OpenZeppelin ERC-20 behavior. There are no transfer taxes, reflection, rebasing, burns, transfer restrictions, hooks, or automatic distributions. `transfer` and `transferFrom` move the exact requested number of smallest units and return `true`; invalid operations revert with ERC-6093 custom errors. Transfers of zero tokens and transfers to the sender are supported. Transfers to the zero address are rejected, including zero-value transfers.

`approve` replaces the caller's allowance for a nonzero spender, and setting it to zero revokes that allowance. `transferFrom` requires allowance even when the caller is also the source address. Finite allowances decrease by the amount spent; `type(uint256).max` represents an unlimited allowance and is not decreased. Failed transfers revert the entire operation, including any allowance update. Successful transfers emit `Transfer`; explicit approvals emit `Approval`. This OpenZeppelin version does not emit `Approval` when `transferFrom` spends an allowance, so integrations should query `allowance` for current authorization.

The constructor is the sole mint path. There is no owner, administrator, proxy, upgrade function, public mint or burn function, blacklist, pause, seizure, or recovery function. The deployer retains only the ordinary rights of a token holder. The factory's launch allocations and pool setup occur outside this contract; the token neither reserves nor distributes any supply itself. No application contracts are included.

## Build and verify

Run from the repository root with Foundry and Solidity `0.8.26` available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x0eaa809d0e4424cb84398fe12883ce734a3e49359102eb6bd00ec90e7bf6dc62 forge test
forge fmt --check
```

All Solidity dependencies are ordinary files in `lib/`; no package installation, submodule checkout, RPC, or network access is required to build or test once the compiler is available. The configuration enables neither FFI nor filesystem permissions. Tests do not read or set environment variables, depend on live chain state, or broadcast transactions. The seed above configures Foundry's test runner only.

Dependencies are copied unchanged from these pinned upstream versions, with their licenses and archive hashes:

- OpenZeppelin Contracts `v5.0.2`: the ERC-20 implementation and its required imports. See [provenance](lib/openzeppelin-contracts/PROVENANCE.md) and [MIT license](lib/openzeppelin-contracts/LICENSE).
- forge-std `v1.9.7`: Solidity testing utilities, used only by tests. See [provenance](lib/forge-std/PROVENANCE.md), [MIT license](lib/forge-std/LICENSE-MIT), and [Apache license](lib/forge-std/LICENSE-APACHE).

## Test coverage

- `test/Robobet.t.sol`: metadata, exact initial supply, mint event, deployer versus transaction origin, transfer/approval events, fractional units, full balances, zero transfers, self transfers, finite and unlimited allowances, revocation, recipient behavior, and unauthorized or invalid operations with state rollback assertions. Four fuzz tests each run 1,000 cases.
- `test/RobobetLaunch.t.sol`: CREATE2 factory deployment, exact 10%/80%/10% distribution transfers, distributor claim transfers, transfers in both pool directions, rejection of common administrative/mint/burn selectors, runtime size, and forbidden opcode checks.
- `test/RobobetInvariant.t.sol`: 256 sequences of 64 handler calls per invariant. An independent model tracks every balance and allowance among four holders through transfers, approvals, delegated transfers, and expected failures. Supply and accounting must remain consistent after each call; unexpected handler reverts fail the test.

The local factory fixture exercises the token's deployment and transfer behavior. It does not execute Uniswap swaps or reproduce the separate IdentityMD admission harness. The supplied protected tests depend on that harness and launch-time configuration and are left to the network verifier.

## After launch and operational responsibilities

No settings or administrative transactions are required after deployment. The launch operator is responsible for deploying the exact compiled artifact through the intended factory, confirming the name, symbol, decimals, total supply and initial recipient, performing the launch allocations and pool setup, and verifying the deployed source. The later manifest step owns `launch.json`; this project does not provide one or send transactions.

Holders are responsible for destination addresses and spender approvals. Use an allowance appropriate to the intended spend; when replacing an existing nonzero allowance, revoking it and confirming that transaction before granting another can reduce the standard ERC-20 allowance replacement race. Unlimited approvals expose future balances to the approved spender. Transfers do not invoke recipient callbacks or check that a contract can recover tokens. Tokens sent to this token contract cannot be recovered, and mistakenly sent assets cannot be rescued by an administrator. Ordinary ETH transfers are rejected.

Review against the supplied security reference focused on the single constructor mint, access to balances and allowances, exact units, arithmetic bounds, and absence of external calls or privileged code paths. Foundry unit, fuzz, and invariant tests are the automated checks used here; Slither and Mythril were not run. Testing and this implementation review are not an independent security audit. The network's independent review and deployment checks remain release responsibilities.

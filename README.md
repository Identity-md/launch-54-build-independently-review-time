# Time Lock

Lock (`LOCK`) is a fixed-supply ERC-20. TimeLock holds irrevocable deposits for named
beneficiaries until their chosen unlock timestamps. Both contracts are immutable,
with no owner, admin, upgradeability, fees, mint backdoor, cancellation, or rescue.

## Build and verify offline

Requires Foundry (`forge`); tested with 1.8.3. Solidity is pinned to 0.8.26, optimizer
200 runs, Paris EVM, and `bytecode_hash = "none"`. No FFI or filesystem cheatcode
permissions are enabled. Test dependencies are vendored as ordinary files in
`lib/forge-std` (v1.9.7, licenses and provenance included).

An official Linux x86-64 Solidity 0.8.26 binary is vendored in `toolchain/svm`,
with its upstream metadata/checksum in `toolchain/solc-provenance.json`.
Foundry resolves the pinned version normally; there is no compiler wrapper or
custom compiler executable configured in `foundry.toml`.

```sh
export XDG_DATA_HOME="$PWD/toolchain"
forge build --offline
forge test --offline
forge fmt --check
# Or run the same checks:
./scripts/check.sh
```

Other platforms need the official compiler for their platform in their existing
Foundry cache. No package installation, RPC, wallet, or network is needed by tests.
Tests cover supply conservation, permissions and rollback, exact timestamp
boundaries, extensions, stable enumeration, repeated withdrawals, multiple locks,
fuzzed amounts/times, failure and malformed-return tokens, reentrancy on deposits
and withdrawals, and factory-style deployment/runtime restrictions.

## Contract interface and assumptions

`src/Lock.sol:Lock` has a zero-argument nonpayable constructor. It mints exactly
1,000,000,000 LOCK (`1000000000000000000000000000` minor units, 18 decimals) to
`msg.sender`. During launch that address is the factory, not a contributor or an
application contract. Standard `transfer`, `approve`, `transferFrom`, `balanceOf`,
and `allowance` are supported. Infinite allowance is not decreased; other allowance
changes emit `Approval`. Supply never changes after the initial `Transfer` event.
When changing an existing allowance, users should revoke it before approving a new
amount if concurrent spender transactions could otherwise consume both allowances.

`src/TimeLock.sol:TimeLock` takes only `address token_`, nonpayably. Its immutable
`token` must be the deployed Lock contract. The constructor rejects addresses
without code; it cannot authenticate arbitrary token implementations.

1. A depositor calls `Lock.approve(timeLockAddress, amount)`.
2. The depositor calls `TimeLock.lock(beneficiary, amount, unlockTime)`. Amount must
   be positive; beneficiary cannot be zero or TimeLock itself; unlock time must be
   strictly later than the current block timestamp. The returned lock ID starts at
   zero. Each call creates a separate lock, even for the same beneficiary.
3. Only that beneficiary may call `withdraw(lockId)` when
   `block.timestamp >= unlockTime`. The entire amount goes to that beneficiary,
   exactly once. There is no caller-selected payout recipient or partial withdrawal.
4. Only the beneficiary may call `extendLock(lockId, newUnlockTime)` before
   withdrawal. The new timestamp must be strictly greater than both the previous
   timestamp and the current block timestamp. Even matured locks can be voluntarily
   extended. Depositors cannot delay another beneficiary's withdrawal.

`getLock(id)` returns depositor, beneficiary, amount, unlockTime, and withdrawn.
`lockCount(beneficiary)` and `lockIdAt(beneficiary, index)` enumerate stable IDs in
creation order without unbounded loops. Withdrawn locks remain in this history;
clients filter by `withdrawn` to display active locks. Invalid IDs/indices revert.
`totalLocked` is the sum of amounts still owed, excluding direct token donations.
`Locked`, `LockExtended`, and `Withdrawn` cover every persistent application change.
Accounting and events precede token interactions, reverting atomically on failure;
a shared reentrancy guard covers all application mutations.

This application is specifically for the included exact-transfer LOCK token.
Fee-on-transfer, rebasing, dishonest, or nonstandard no-return tokens are unsupported.
Mock attacks test defensive behavior, not safe custody of arbitrary malicious tokens.
A token that lies about transfers can invalidate accounting. Deployment must bind
the reviewed LOCK address. Token reverts/false returns cannot create unfunded locks
or consume withdrawal rights. Failed withdrawals can be retried.

Timestamps are Unix seconds on-chain, not an off-chain scheduling guarantee. There
is no maximum duration: a distant timestamp, lost beneficiary key, or beneficiary
contract unable to call `withdraw` can permanently strand funds. Depositors must
check the beneficiary and date. Beneficiary identities are immutable. Direct token
transfers create no lock and cannot be recovered; accidental other tokens also have
no recovery path. Ordinary ETH transfers are rejected. Forced ETH has no rescue.
There are no keepers: each beneficiary submits and pays gas for its withdrawal.

## Sepolia release parameters and responsibilities

`launch.json` declares kind `evm_project`, Sepolia chain ID **11155111**, token
`src/Lock.sol:Lock`, and one application `src/TimeLock.sol:TimeLock`, named
`TimeLock`, with exactly `["$token"]` as constructor arguments. There are no owner
arguments or hard-coded privileged wallets. TimeLock’s constructor makes no token movements; neither
contract requires initialization calls. The token deploys first, then TimeLock.

Pool parameters are native ETH (zero address), fee **3000**, tick spacing **60**,
and initial sqrtPriceX96 **79228162514264337593543950336**. This is a configuration,
not a valuation promise; factory liquidity is seeded with launch tokens only.
The manifest's artifact identifiers and metadata must be admitted by the launch
pipeline's schema/policy checks before release; no factory address or release salt
is invented here. Factory/policy addresses, CREATE2 salts, release artifact hashes,
and allocation details belong to the admitted release, supplied by its deployer.

Contributors prepare and test source; they never broadcast or access funded keys.
The independent contributor/release reviewer must review the final source and
manifest, confirm token identity and constructor arguments, verify artifacts and
runtime restrictions, and resolve any findings before admission. `REVIEW.md`
records the separate local agent review and its limits; passing tests or that review
does not constitute an audit or independent contributor admission.

Only the authorized deployer broadcasts the admitted release through ProjectFactory.
The deployer must verify chain/policy, artifact hashes, the actual `$token` binding,
fixed supply held by the factory immediately after constructors, pool parameters,
and final deployment events/addresses. Publish verified source and addresses after
release. There is no post-deployment administrator able to fix mistakes, change the
token, withdraw user balances, or upgrade these contracts. No deployment has been
performed in this assignment, and no broadcast script is included.

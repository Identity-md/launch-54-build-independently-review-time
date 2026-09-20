# Independent agent review

Date: 2026-09-20. Reviewer: a separate review agent, independently assigned after implementation. This is an independent agent review, not a formal audit or independent contributor admission. No transactions were broadcast. A separate contributor must review the final admitted source, bytecode, manifest, and resolved deployment arguments before the deployer releases it.

## Scope and conclusion

Reviewed `src/Lock.sol`, `src/TimeLock.sol`, the token, application, adversarial and factory-deployment tests, `foundry.toml`, `launch.json`, `README.md`, `scripts/check.sh`, bundled compiler provenance/toolchain resolution, and both supplied protected deployment/token checks. No release-blocking correctness or custody vulnerability was found for deployment with the supplied immutable LOCK token. This conclusion is limited to the inspected implementation and stated token assumptions; it does not approve an arbitrary token address or a production release.

- LOCK mints exactly 10^27 units to its constructor caller. The supply is constant; all reachable functions were inspected for additional issuance, ownership, upgrade, pause, fees and alternate mint paths. None exists. Transfers conserve balances, including self-transfers; insufficient balance reverts also roll back allowance changes.
- TimeLock stores the depositor but authorizes withdrawals and extensions exclusively by the immutable beneficiary recorded in each deposit. Depositors cannot revoke, shorten, redirect, or prolong someone else's lock. Only a strictly later, future timestamp can extend a live lock. Withdrawal is valid at the exact recorded timestamp, once only.
- Deposit records, enumeration and total liabilities are updated before incoming transfers; withdrawal status and liabilities change before outgoing transfers. Every mutating entry point has the same reentrancy guard. False returns, token reverts and malformed return data atomically restore accounting. Cross-function callback tests use an authorized token beneficiary, avoiding a misleading result caused solely by permission denial.
- Historical enumeration is stable and O(1) per index, including withdrawn records. A beneficiary with many unsolicited locks is not forced through an on-chain loop to withdraw a known ID.
- State changes have token or application events. There is no owner, admin, rescue, initialization, delegatecall, selfdestruct, upgrade, fee, or beneficiary-reassignment path in the source. Constructors are nonpayable; TimeLock takes only the token address.
- The manifest identifies `Lock` and `TimeLock` with `$token`, Sepolia chain ID 11155111, supply and decimals matching the source, and the stated native-ETH pool parameters. Compiler 0.8.26, Paris EVM, metadata hash disabled, FFI disabled and empty filesystem permissions match the deployment assumptions. The supplied protected checks establish a deployment baseline, not application correctness.

## Assumptions and operational findings

1. **Token-address validation is deliberately limited.** The constructor checks code exists, not token identity or exact-transfer behavior. A fee, rebasing, dishonest-success or otherwise incompatible token could break liability coverage. Deploy only with the manifest-resolved supplied LOCK address; independently verify that address and runtime. Adversarial-token tests demonstrate callback/failure resilience, not support for arbitrary ERC-20s.
2. **Irrevocability includes mistakes.** Direct token donations create no withdrawal claim and remain stranded. Wrong beneficiaries, beneficiaries unable to call the contract, lost keys and excessively distant timestamps cannot be rescued. The contract rejects itself and zero as beneficiaries but cannot establish control of another address. Interfaces should display beneficiary, units and absolute timestamp clearly before approval and deposit.
3. **Chain time is the release clock.** Unlocks use `block.timestamp`, not an off-chain wall clock or scheduling service. No transaction is automatic; the beneficiary must submit withdrawal and pay gas. The maximum uint256 timestamp is accepted and practically locks forever.
4. **Review/release remains separate.** Factory deployment gives the initial supply to the factory and grants no application privilege to it. Final source/manifest admission, address resolution, pool configuration, distribution and actual broadcasting remain the independent contributor/deployer's responsibilities. This review did not verify a live factory, manifest parser integration, external deployment infrastructure or chain state.

## Independent validation

Executed `XDG_DATA_HOME=/tmp/lock-xdg forge build --offline` and the corresponding offline tests on the initial implementation. Subsequently executed the delivered `./scripts/check.sh`: offline build, all 22 tests and formatting passed, zero tests failed/skipped. This includes 20 delivered implementation/deployment tests and two independent scratch tests. The latter covered randomized interleaved beneficiary extensions and out-of-order withdrawals with conservation/history assertions (256 fuzz cases), plus maximum-timestamp behavior. Scratch tests are intentionally excluded from the submitted deliverable; durable application/adversarial/deployment tests remain in `test/`. The factory-style CREATE2 test verifies the full factory-held supply, immutable token binding, runtime size, and forbidden-opcode scan while correctly skipping PUSH data.

The helper script only sets the repository compiler-cache location and runs offline build/test plus formatting. The bundled Linux x86-64 compiler SHA256 is `d5f23436f443edb85d8e76906d12f0a86ce0490e7663a9e608efeb7a93f149ef`, matching `toolchain/solc-provenance.json`. Foundry retains its standard pinned-version resolver; there is no compiler wrapper or executable override in configuration. This verifies local metadata consistency, not an independent audit of compiler distribution provenance. README accurately describes the source/manifest binding, unsupported-token assumptions and release responsibilities; a minor wording clarification about constructor token movements was requested because LOCK's constructor does mint.

Build lint warnings were inspected. Reentrancy warnings refer to clearing `entered` after external calls; the guard is already set before each call, and hostile callbacks verify rejection. Timestamp warnings reflect the required time-lock clock. The fuzz-test warp warning does not affect its explicitly calculated maturity values. These warnings were not suppressed. Any changes after this review require the implementer's final checks and release review.

Limitations: bounded tests and manual review cannot prove absence of every defect. No formal verification, live deployment, full third-party dependency audit, frontend review, or contributor-network approval was performed.

## Implementer follow-up

The README constructor wording was corrected: TimeLock performs no token movements,
while LOCK mints to its deployer. The implementer additionally ran both supplied
protected suites against the compiled artifacts using scratch-only copies and local
CREATE2 parameters: all eight checks passed with no skips. This is local validation,
not contributor-network admission or deployment approval.

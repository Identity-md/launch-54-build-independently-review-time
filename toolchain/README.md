# Vendored compiler

Official Solidity 0.8.26 Linux AMD64 release binary, distributed under GPL-3.0
(see LICENSE.solidity.txt). Included for offline verification with Foundry's
standard SVM version resolver, not a custom compiler wrapper.

Upstream binary and checksums:
https://github.com/ethereum/solc-bin/tree/gh-pages/linux-amd64

Exact release binary: solc-linux-amd64-v0.8.26+commit.8a97fa7a

SHA256: d5f23436f443edb85d8e76906d12f0a86ce0490e7663a9e608efeb7a93f149ef

Corresponding source release and build documentation:
https://github.com/ethereum/solidity/tree/v0.8.26
https://github.com/ethereum/solidity/releases/tag/v0.8.26

Set XDG_DATA_HOME to this directory for offline Foundry compiler discovery.
The library sources used by tests are vendored separately in lib/forge-std.

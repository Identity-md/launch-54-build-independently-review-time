// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Lock} from "../src/Lock.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract FactoryStandIn {
    function deploy() external returns (Lock token, TimeLock vault) {
        token = new Lock{salt: bytes32(uint256(1))}();
        vault = new TimeLock{salt: bytes32(uint256(2))}(address(token));
    }
}

contract DeploymentTest is Test {
    function testFactoryDeploymentPreservesWholeSupplyAndTokenBinding() public {
        FactoryStandIn factory = new FactoryStandIn();
        (Lock token, TimeLock vault) = factory.deploy();
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(factory)), 1e27);
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(address(vault.token()), address(token));
        assertEq(vault.nextLockId(), 0);
        assertEq(vault.totalLocked(), 0);
        _checkRuntime(address(token).code);
        _checkRuntime(address(vault).code);
    }

    function _checkRuntime(bytes memory code) private pure {
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
        }
    }
}

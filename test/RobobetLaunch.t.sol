// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Robobet} from "../src/Robobet.sol";
import {RobobetTestBase} from "./helpers/RobobetTestBase.sol";

/// @dev Local test fixture for the factory's CREATE2 deployment and ERC-20 transfers.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (Robobet) {
        return new Robobet{salt: salt}();
    }

    function move(Robobet token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract RobobetLaunchTest is RobobetTestBase {
    function test_factoryDeploymentReceivesEntireSupply() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        vm.prank(alice, bob);
        Robobet deployed = factory.deploy(keccak256("Robobet launch test"));
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.balanceOf(address(deployed)), 0);
    }

    function test_launchDistributionClaimsAndPoolTransfersAreExact() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        Robobet deployed = factory.deploy(keccak256("Robobet distribution test"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("poolManager");
        address remainder = makeAddr("remainder");

        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;
        assertTrue(factory.move(deployed, distributor, swarm));
        assertTrue(factory.move(deployed, poolManager, pool));
        assertTrue(factory.move(deployed, remainder, SUPPLY - swarm - pool));
        assertEq(deployed.balanceOf(distributor), swarm);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.balanceOf(remainder), SUPPLY / 10);
        assertEq(deployed.balanceOf(address(factory)), 0);

        vm.prank(distributor);
        assertTrue(deployed.transfer(alice, swarm));
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.balanceOf(alice), swarm);

        // Exercise the token's two transfer directions; this is not an AMM swap simulation.
        vm.prank(poolManager);
        assertTrue(deployed.transfer(bob, 123 ether));
        assertEq(deployed.balanceOf(bob), 123 ether);
        assertEq(deployed.balanceOf(poolManager), pool - 123 ether);
        vm.prank(bob);
        assertTrue(deployed.transfer(poolManager, 123 ether));
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_noMintBurnOrAdministrativeEntryPoints() public {
        assertTrue(token.transfer(alice, 100 ether));
        bytes[] memory calls = new bytes[](23);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        calls[4] = abi.encodeWithSignature("setOwner(address)", bob);
        calls[5] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[6] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[7] = abi.encodeWithSignature("initialize(address)", bob);
        calls[8] = abi.encodeWithSignature("unpause()");
        calls[9] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[10] = abi.encodeWithSignature("pause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[12] = abi.encodeWithSignature("blocklist(address)", alice);
        calls[13] = abi.encodeWithSignature("freeze(address)", alice);
        calls[14] = abi.encodeWithSignature("freezeAccount(address)", alice);
        calls[15] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        calls[16] = abi.encodeWithSignature("setBlocked(address,bool)", alice, true);
        calls[17] = abi.encodeWithSignature("lock(address)", alice);
        calls[18] = abi.encodeWithSignature("disableTransfers()");
        calls[19] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[20] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 100 ether);
        calls[21] = abi.encodeWithSignature("seize(address)", alice);
        calls[22] = abi.encodeWithSignature("burn(uint256)", 100 ether);

        address[3] memory callers = [address(this), alice, bob];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < calls.length; ++j) {
                vm.prank(callers[i]);
                (bool success,) = address(token).call(calls[j]);
                assertFalse(success, "unexpected administrative entry point");
                assertEq(token.totalSupply(), SUPPLY);
                assertEq(token.balanceOf(address(this)), SUPPLY - 100 ether);
                assertEq(token.balanceOf(alice), 100 ether);
                assertEq(token.balanceOf(bob), 0);
            }
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_runtimeFitsDeploymentLimitAndHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4, "DELEGATECALL");
            assertTrue(opcode != 0xf2, "CALLCODE");
            assertTrue(opcode != 0xff, "SELFDESTRUCT");
        }
    }
}

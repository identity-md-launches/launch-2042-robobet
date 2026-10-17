// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Robobet} from "../src/Robobet.sol";
import {RobobetTestBase} from "./helpers/RobobetTestBase.sol";

/// @dev A closed set of holders and an independent balance/allowance model.
contract RobobetHandler is Test {
    Robobet private immutable token;
    address[4] private actors;
    mapping(address => uint256) public modelBalance;
    mapping(address => mapping(address => uint256)) public modelAllowance;

    constructor(Robobet token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        modelBalance[actors_[0]] = 1_000_000_000_000_000_000_000_000_000;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, modelBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        modelBalance[from] -= amount;
        modelBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    /// @dev Make revocation, small approvals and the infinite-allowance boundary frequent.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint8 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[5] memory amounts = [uint256(0), 1, modelBalance[owner], type(uint256).max - 1, type(uint256).max];
        _approve(owner, spender, amounts[mode % amounts.length]);
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = modelAllowance[from][spender];
        uint256 available = modelBalance[from] < approved ? modelBalance[from] : approved;
        amount = bound(amount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        modelBalance[from] -= amount;
        modelBalance[to] += amount;
        if (approved != type(uint256).max) {
            modelAllowance[from][spender] -= amount;
        }
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = modelBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
        vm.prank(from);
        token.transfer(to, balance + 1);
    }

    function rejectAllowanceOverspend(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 approved)
        external
    {
        address from = _fundedActor(fromSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        // Sufficient balance isolates authorization failure from balance failure.
        approved = bound(approved, 0, modelBalance[from] - 1);
        _approve(from, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(from, to, approved + 1);
        // No ghost update: the invariants must observe the entire failed call rolled back.
    }

    function rejectDelegatedOverspend(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, bool infinite) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = modelBalance[from];
        uint256 amount = balance + 1;
        _approve(from, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 action) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        action %= 3;
        if (action == 0) {
            amount = bound(amount, 0, modelBalance[owner]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        } else if (action == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), amount);
        } else {
            uint256 approved = modelAllowance[owner][spender];
            amount = bound(amount, 0, modelBalance[owner] < approved ? modelBalance[owner] : approved);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        }
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        modelAllowance[owner][spender] = amount;
    }

    function _fundedActor(uint256 seed) private view returns (address) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[(start + i) % actors.length];
            if (modelBalance[actor] > 0) return actor;
        }
        revert("conserved supply must have a holder");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract RobobetInvariantTest is RobobetTestBase {
    RobobetHandler private handler;
    address[4] private actors;

    function setUp() public override {
        super.setUp();
        actors = [alice, bob, spender, makeAddr("fourth holder")];
        assertTrue(token.transfer(alice, SUPPLY));
        handler = new RobobetHandler(token, actors);
        // Give every actor spendable funds before random calls begin.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, SUPPLY / actors.length);
        }

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = RobobetHandler.transfer.selector;
        selectors[1] = RobobetHandler.approve.selector;
        selectors[2] = RobobetHandler.transferFrom.selector;
        selectors[3] = RobobetHandler.rejectOverspend.selector;
        selectors[4] = RobobetHandler.approveBoundary.selector;
        selectors[5] = RobobetHandler.rejectAllowanceOverspend.selector;
        selectors[6] = RobobetHandler.rejectDelegatedOverspend.selector;
        selectors[7] = RobobetHandler.rejectZeroAddress.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndAllBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.modelBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_allowancesMatchHolderAuthorizations() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.modelAllowance(actors[i], actors[j]));
            }
        }
    }
}

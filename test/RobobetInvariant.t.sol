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
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        modelAllowance[owner][spender] = amount;
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
}

contract RobobetInvariantTest is RobobetTestBase {
    RobobetHandler private handler;
    address[4] private actors;

    function setUp() public override {
        super.setUp();
        actors = [alice, bob, spender, makeAddr("fourth holder")];
        assertTrue(token.transfer(alice, SUPPLY));
        handler = new RobobetHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = RobobetHandler.transfer.selector;
        selectors[1] = RobobetHandler.approve.selector;
        selectors[2] = RobobetHandler.transferFrom.selector;
        selectors[3] = RobobetHandler.rejectOverspend.selector;
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
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.modelAllowance(actors[i], actors[j]));
            }
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Robobet} from "../src/Robobet.sol";
import {RobobetTestBase} from "./helpers/RobobetTestBase.sol";

contract RobobetAllowanceRelay {
    function pull(Robobet token, address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}

/// @notice Allowance lifecycle, independent authorizations and recovery after rejected operations.
/// forge-config: default.fuzz.runs = 1000
contract RobobetAllowanceTest is RobobetTestBase {
    function test_largestFiniteAllowanceDecreasesByOne() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceCanBeReducedThenRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 1);

        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_sameSpenderHasIndependentAllowancesForDifferentOwners() public {
        assertTrue(token.transfer(alice, 10));
        assertTrue(token.transfer(bob, 20));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));
        vm.prank(bob);
        assertTrue(token.approve(spender, 20));

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 4));
        assertEq(token.allowance(alice, spender), 6);
        assertEq(token.allowance(bob, spender), 20);
        vm.prank(alice);
        assertTrue(token.approve(spender, 0));

        vm.prank(spender);
        assertTrue(token.transferFrom(bob, spender, 7));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(bob, spender), 13);
        assertEq(token.balanceOf(alice), 6);
        assertEq(token.balanceOf(bob), 13);
        assertEq(token.balanceOf(spender), 11);
        assertEq(token.balanceOf(address(this)), SUPPLY - 30);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalCannotBePassedOnToAnotherSpender() public {
        assertTrue(token.approve(spender, 10));
        vm.prank(spender);
        assertTrue(token.approve(bob, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);

        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.allowance(spender, bob), 10);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ownerCanUseTransferFromAfterSelfApproval() public {
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_contractSpenderNeedsItsOwnApprovalRegardlessOfTransactionOrigin() public {
        RobobetAllowanceRelay relay = new RobobetAllowanceRelay();
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(relay), 0, 1));
        vm.prank(spender, spender);
        relay.pull(token, address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        assertTrue(token.approve(address(relay), 1));
        vm.prank(spender, spender);
        assertTrue(relay.pull(token, address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.allowance(address(this), address(relay)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(address(relay)), 0);
    }

    function test_infiniteAllowanceDoesNotBypassBalanceChecks() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, type(uint256).max);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumDirectTransferRevertsWithoutMovingBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroValueCallsStillRejectZeroSpenderAndReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);

        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_repeatingApprovalIsIdempotentAndEmitsAnEvent(uint256 approved) public {
        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit Approval(address(this), spender, approved);
            assertTrue(token.approve(spender, approved));
            assertEq(token.allowance(address(this), spender), approved);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedTransferCanBeRetriedAfterFunding(uint256 balance, uint256 amount, uint256 approved) public {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);

        // Reuse the original authorization after fixing only the balance shortfall.
        assertTrue(token.transfer(alice, amount - balance));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_reducingAllowanceAfterPartialSpendEnforcesNewLimit(
        uint256 approved,
        uint256 spent,
        uint256 revised
    ) public {
        approved = bound(approved, 1, SUPPLY - 1);
        spent = bound(spent, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, spent));
        assertEq(token.allowance(address(this), spender), approved - spent);

        revised = bound(revised, 0, approved - spent);
        assertTrue(token.approve(spender, revised));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, revised, revised + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, revised + 1);
        assertEq(token.allowance(address(this), spender), revised);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(alice), spent);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, revised));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent - revised);
        assertEq(token.balanceOf(alice), spent + revised);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripPreservesBalancesAndAllowances(
        uint256 amount,
        uint256 aliceApproval,
        uint256 bobApproval
    ) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.approve(spender, aliceApproval));
        vm.prank(bob);
        assertTrue(token.approve(spender, bobApproval));

        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), SUPPLY - amount);
        assertEq(token.balanceOf(bob), amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(alice, spender), aliceApproval);
        assertEq(token.allowance(bob, spender), bobApproval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_zeroRecipientFailurePreservesFiniteAllowanceForRetry(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, type(uint256).max - 1);
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_twoSpendersCannotOverdrawTheSameBalance(uint256 firstSpend, uint256 overspend) public {
        firstSpend = bound(firstSpend, 1, SUPPLY);
        uint256 remaining = SUPPLY - firstSpend;
        overspend = bound(overspend, remaining + 1, type(uint256).max);
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(bob, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, firstSpend));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), remaining, overspend)
        );
        vm.prank(bob);
        token.transferFrom(address(this), bob, overspend);
        assertEq(token.balanceOf(address(this)), remaining);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), bob, remaining));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), firstSpend);
        assertEq(token.balanceOf(bob), remaining);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.allowance(address(this), bob), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }
}

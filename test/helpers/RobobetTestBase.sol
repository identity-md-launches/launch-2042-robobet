// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Robobet} from "../../src/Robobet.sol";

abstract contract RobobetTestBase is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    Robobet internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public virtual {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new Robobet();
    }
}

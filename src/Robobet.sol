// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Robobet
/// @notice Fixed-supply ERC-20 with 18 decimals, minted entirely to its deployer.
/// @dev The launch factory receives the supply when it creates this contract.
/// There are no administrative roles or externally callable mint or burn functions.
contract Robobet is ERC20 {
    /// @notice One billion ROBOBET expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Robobet", "ROBOBET") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}

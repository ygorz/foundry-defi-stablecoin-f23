// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Mock DecentralizedStableCoin Fails Minting
 * @author George Gorzhiyev
 * Collateral: Exogenous (wETH & wBTC)
 * Minting: Algorithmic
 * Relative Stability: Pegged to USD
 *
 * A mock contract of the DecentralizedStableCoin that fails minting. Testing minting failed scenario.
 *
 */
contract MockDscMintFailed is ERC20Burnable, Ownable {
    /* --------------- ERRORS --------------- */
    error MockDscMintFailed__MustBeMoreThanZero();
    error MockDscMintFailed__BurnAmountExceedsBalance();
    error MockDscMintFailed__NotZeroAddress();

    /* --------------- CONSTRUCTOR --------------- */
    constructor() ERC20("MockDscMintFailed", "MDSF") {}

    /* --------------- FUNCTIONS --------------- */
    function mint(address _to, uint256 _amount) external view onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert MockDscMintFailed__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert MockDscMintFailed__MustBeMoreThanZero();
        }
        return false;
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert MockDscMintFailed__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert MockDscMintFailed__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }
}

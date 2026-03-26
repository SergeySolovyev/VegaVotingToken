// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VegaVotingToken (VV)
 * @notice ERC-20 token used for staking and governance voting in the Vega Voting Protocol.
 * @dev The owner (admin) can mint tokens. Standard ERC-20 otherwise.
 */
contract VegaVotingToken is ERC20, Ownable {
    constructor(address initialOwner) ERC20("VegaVoting", "VV") Ownable(initialOwner) {}

    /**
     * @notice Mint new VV tokens.
     * @param to Recipient address.
     * @param amount Amount of tokens to mint (in wei).
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

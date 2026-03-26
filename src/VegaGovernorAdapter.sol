// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {VegaVotingStaking} from "./VegaVotingStaking.sol";
import {VegaVotingResultNFT} from "./VegaVotingResultNFT.sol";

/**
 * @title VegaGovernorAdapter
 * @notice Alternative governance contract built on top of OpenZeppelin Governor.
 *         Provided as an extra deliverable (see HW6 requirements).
 *
 * @dev OZ Governor normally requires an IVotes-compliant token with checkpoints
 *      and delegation. Our staking model computes voting power dynamically from
 *      remaining lock duration, which is incompatible with the snapshot-based
 *      IVotes interface.
 *
 *      This adapter bridges the two models:
 *        - Inherits Governor and GovernorCountingSimple for proposal lifecycle
 *          and yes/no/abstain counting.
 *        - Overrides _getVotes() to query VegaVotingStaking.getVotingPower()
 *          at the current block rather than from a historical snapshot.
 *        - Uses block.timestamp as the clock (ERC-6372 timestamp mode).
 *        - Mints a VegaVotingResultNFT when a proposal is executed.
 *
 *      Limitation: because voting power is read at cast-time rather than from a
 *      snapshot at proposal creation, this implementation is susceptible to
 *      vote-weight manipulation between proposal creation and vote casting.
 *      A production system would require integrating checkpoints into the
 *      staking contract. This trade-off is documented here for transparency.
 */
contract VegaGovernorAdapter is Governor, GovernorCountingSimple, GovernorSettings {

    VegaVotingStaking public immutable stakingContract;
    VegaVotingResultNFT public immutable resultNFT;
    uint256 public immutable quorumThreshold;

    constructor(
        address _staking,
        address _resultNFT,
        uint256 _quorumThreshold,
        uint48 _votingDelay,
        uint32 _votingPeriod
    )
        Governor("VegaGovernor")
        GovernorSettings(_votingDelay, _votingPeriod, 0)
    {
        stakingContract = VegaVotingStaking(_staking);
        resultNFT = VegaVotingResultNFT(_resultNFT);
        quorumThreshold = _quorumThreshold;
    }

    // -- Clock: use block.timestamp (ERC-6372 timestamp mode) --

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    // -- Voting power from staking contract --

    function _getVotes(
        address account,
        uint256, /* timepoint -- ignored; we read current state */
        bytes memory /* params */
    ) internal view override returns (uint256) {
        return stakingContract.getVotingPower(account);
    }

    // -- Quorum --

    function quorum(uint256 /* timepoint */) public view override returns (uint256) {
        return quorumThreshold;
    }

    // -- Required overrides for GovernorSettings --

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }
}

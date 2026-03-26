// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VegaVotingStaking} from "./VegaVotingStaking.sol";
import {VegaVotingResultNFT} from "./VegaVotingResultNFT.sol";

/**
 * @title VegaVotingGovernance
 * @notice Manages the voting lifecycle: creation, casting, and finalization.
 *         On finalization, mints an ERC-721 NFT that encapsulates voting results.
 *
 * @dev Voting power comes from VegaVotingStaking. Only the admin (owner) can create votes.
 *      Anyone with voting power can cast yes/no. Finalization can be triggered by anyone once
 *      the deadline is reached or the threshold is met (early finalization).
 *
 *      Roles:
 *        - Admin (owner): creates votes, can pause/unpause, emergency finalize.
 *        - Staker: casts votes using their voting power.
 *        - Anyone: can call finalize() once conditions are met.
 */
contract VegaVotingGovernance is Ownable, Pausable, ReentrancyGuard {

    // ─── State ─────────────────────────────────────────────────
    VegaVotingStaking public immutable staking;
    VegaVotingResultNFT public immutable resultNFT;

    enum VoteStatus {
        Active,
        Finalized
    }

    struct Voting {
        bytes32 id;
        uint256 deadline;
        uint256 votingPowerThreshold;
        string description;
        uint256 yesVotes;
        uint256 noVotes;
        VoteStatus status;
        uint256 resultTokenId;
    }

    /// @notice votingId => Voting struct
    mapping(bytes32 => Voting) public votings;
    /// @notice ordered list of all voting IDs
    bytes32[] public votingIds;
    /// @notice votingId => voter => hasVoted
    mapping(bytes32 => mapping(address => bool)) public hasVoted;

    // ─── Events ────────────────────────────────────────────────
    event VotingCreated(bytes32 indexed id, uint256 deadline, uint256 votingPowerThreshold, string description);
    event VoteCast(bytes32 indexed votingId, address indexed voter, bool support, uint256 votingPower);
    event VotingFinalized(bytes32 indexed votingId, bool passed, uint256 yesVotes, uint256 noVotes, uint256 nftTokenId);

    // ─── Errors ────────────────────────────────────────────────
    error VotingAlreadyExists(bytes32 id);
    error VotingNotFound(bytes32 id);
    error VotingNotActive(bytes32 id);
    error VotingDeadlinePassed(bytes32 id);
    error AlreadyVoted(bytes32 id, address voter);
    error NoVotingPower();
    error VotingCannotBeFinalized(bytes32 id);
    error InvalidDeadline();
    error ZeroThreshold();

    constructor(address _staking, address _resultNFT, address _owner) Ownable(_owner) {
        staking = VegaVotingStaking(_staking);
        resultNFT = VegaVotingResultNFT(_resultNFT);
    }

    // ─── Admin Functions ───────────────────────────────────────

    /**
     * @notice Create a new voting.
     * @param id Unique identifier for the voting.
     * @param deadline Timestamp after which voting ends.
     * @param votingPowerThreshold Minimum yesVotes (in voting power) to pass the vote.
     * @param description Human-readable question being voted on.
     */
    function createVoting(
        bytes32 id,
        uint256 deadline,
        uint256 votingPowerThreshold,
        string calldata description
    ) external onlyOwner whenNotPaused {
        if (deadline <= block.timestamp) revert InvalidDeadline();
        if (votingPowerThreshold == 0) revert ZeroThreshold();
        if (votings[id].deadline != 0) revert VotingAlreadyExists(id);

        votings[id] = Voting({
            id: id,
            deadline: deadline,
            votingPowerThreshold: votingPowerThreshold,
            description: description,
            yesVotes: 0,
            noVotes: 0,
            status: VoteStatus.Active,
            resultTokenId: 0
        });
        votingIds.push(id);

        emit VotingCreated(id, deadline, votingPowerThreshold, description);
    }

    // ─── Voting ────────────────────────────────────────────────

    /**
     * @notice Cast a yes or no vote on a voting.
     * @param votingId The voting identifier.
     * @param support True for yes, false for no.
     */
    function castVote(bytes32 votingId, bool support) external whenNotPaused nonReentrant {
        Voting storage v = votings[votingId];
        if (v.deadline == 0) revert VotingNotFound(votingId);
        if (v.status != VoteStatus.Active) revert VotingNotActive(votingId);
        if (block.timestamp >= v.deadline) revert VotingDeadlinePassed(votingId);
        if (hasVoted[votingId][msg.sender]) revert AlreadyVoted(votingId, msg.sender);

        uint256 vp = staking.getVotingPower(msg.sender);
        if (vp == 0) revert NoVotingPower();

        hasVoted[votingId][msg.sender] = true;

        if (support) {
            v.yesVotes += vp;
        } else {
            v.noVotes += vp;
        }

        emit VoteCast(votingId, msg.sender, support, vp);
    }

    // ─── Finalization ──────────────────────────────────────────

    /**
     * @notice Finalize a voting once the deadline has passed or the threshold is met.
     *         Mints an NFT with the results.
     * @dev Anyone can call this — no special role required.
     *      Early finalization: yesVotes >= votingPowerThreshold.
     *      Normal finalization: block.timestamp >= deadline.
     * @param votingId The voting identifier.
     */
    function finalizeVoting(bytes32 votingId) external nonReentrant {
        Voting storage v = votings[votingId];
        if (v.deadline == 0) revert VotingNotFound(votingId);
        if (v.status != VoteStatus.Active) revert VotingNotActive(votingId);

        bool thresholdMet = v.yesVotes >= v.votingPowerThreshold;
        bool deadlinePassed = block.timestamp >= v.deadline;

        if (!thresholdMet && !deadlinePassed) revert VotingCannotBeFinalized(votingId);

        v.status = VoteStatus.Finalized;
        bool passed = v.yesVotes >= v.votingPowerThreshold;

        // Mint result NFT to the admin (owner of governance)
        uint256 tokenId = resultNFT.mintResult(
            owner(),
            votingId,
            v.description,
            v.yesVotes,
            v.noVotes,
            passed,
            block.timestamp
        );
        v.resultTokenId = tokenId;

        emit VotingFinalized(votingId, passed, v.yesVotes, v.noVotes, tokenId);
    }

    // ─── View Functions ────────────────────────────────────────

    function getVotingCount() external view returns (uint256) {
        return votingIds.length;
    }

    function getVoting(bytes32 votingId) external view returns (
        bytes32 id,
        uint256 deadline,
        uint256 votingPowerThreshold,
        string memory description,
        uint256 yesVotes,
        uint256 noVotes,
        VoteStatus status,
        uint256 resultTokenId
    ) {
        Voting storage v = votings[votingId];
        return (v.id, v.deadline, v.votingPowerThreshold, v.description, v.yesVotes, v.noVotes, v.status, v.resultTokenId);
    }

    // ─── Emergency Controls ────────────────────────────────────

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency: admin can force-finalize a vote.
     */
    function emergencyFinalize(bytes32 votingId) external onlyOwner nonReentrant {
        Voting storage v = votings[votingId];
        if (v.deadline == 0) revert VotingNotFound(votingId);
        if (v.status != VoteStatus.Active) revert VotingNotActive(votingId);

        v.status = VoteStatus.Finalized;
        bool passed = v.yesVotes >= v.votingPowerThreshold;

        uint256 tokenId = resultNFT.mintResult(
            owner(),
            votingId,
            v.description,
            v.yesVotes,
            v.noVotes,
            passed,
            block.timestamp
        );
        v.resultTokenId = tokenId;

        emit VotingFinalized(votingId, passed, v.yesVotes, v.noVotes, tokenId);
    }
}

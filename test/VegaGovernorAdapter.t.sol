// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {VegaVotingToken} from "../src/VegaVotingToken.sol";
import {VegaVotingStaking} from "../src/VegaVotingStaking.sol";
import {VegaVotingResultNFT} from "../src/VegaVotingResultNFT.sol";
import {VegaGovernorAdapter} from "../src/VegaGovernorAdapter.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title VegaGovernorAdapterTest
 * @notice Tests for the OZ Governor-based governance adapter (extra deliverable).
 */
contract VegaGovernorAdapterTest is Test {
    VegaVotingToken public vvToken;
    VegaVotingStaking public staking;
    VegaVotingResultNFT public resultNFT;
    VegaGovernorAdapter public governor;

    address public admin = address(1);
    address public alice = address(2);
    address public bob   = address(3);

    uint256 constant QUARTER = 91 days;

    function setUp() public {
        vm.startPrank(admin);

        vvToken = new VegaVotingToken(admin);
        staking = new VegaVotingStaking(address(vvToken), admin);
        resultNFT = new VegaVotingResultNFT(admin);

        // Governor: 0 voting delay, 7 days voting period, quorum = 1
        governor = new VegaGovernorAdapter(
            address(staking),
            address(resultNFT),
            1,       // quorumThreshold
            0,       // votingDelay (seconds)
            7 days   // votingPeriod (seconds)
        );

        vvToken.mint(alice, 1000 ether);
        vvToken.mint(bob, 500 ether);

        vm.stopPrank();

        // Alice stakes 500 VV for 8 quarters (2 years)
        vm.startPrank(alice);
        vvToken.approve(address(staking), 500 ether);
        staking.stake(500 ether, 8);
        vm.stopPrank();

        // Bob stakes 200 VV for 4 quarters (1 year)
        vm.startPrank(bob);
        vvToken.approve(address(staking), 200 ether);
        staking.stake(200 ether, 4);
        vm.stopPrank();
    }

    function _createEmptyProposal() internal returns (uint256) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(0);
        values[0] = 0;
        calldatas[0] = "";

        vm.prank(alice);
        uint256 proposalId = governor.propose(
            targets, values, calldatas, "Should we upgrade?"
        );
        return proposalId;
    }

    function test_GovernorName() public view {
        assertEq(governor.name(), "VegaGovernor");
    }

    function test_ClockMode() public view {
        assertEq(governor.CLOCK_MODE(), "mode=timestamp");
        assertEq(governor.clock(), uint48(block.timestamp));
    }

    function test_ProposeAndVote() public {
        uint256 proposalId = _createEmptyProposal();

        // Advance past voting delay (0 seconds, but need +1 for snapshot)
        vm.warp(block.timestamp + 1);

        // Alice votes For (support = 1)
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        assertTrue(governor.hasVoted(proposalId, alice));
    }

    function test_VoteSucceedsWithQuorum() public {
        uint256 proposalId = _createEmptyProposal();
        vm.warp(block.timestamp + 1);

        // Alice votes For
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Bob votes Against
        vm.prank(bob);
        governor.castVote(proposalId, 0);

        // Advance past voting period
        vm.warp(block.timestamp + 7 days + 1);

        // Check state is Succeeded (Alice has more voting power than Bob)
        IGovernor.ProposalState state = governor.state(proposalId);
        assertEq(uint256(state), uint256(IGovernor.ProposalState.Succeeded));
    }

    function test_VoteDefeated() public {
        uint256 proposalId = _createEmptyProposal();
        vm.warp(block.timestamp + 1);

        // Only Bob votes Against
        vm.prank(bob);
        governor.castVote(proposalId, 0);

        // Alice votes Against too
        vm.prank(alice);
        governor.castVote(proposalId, 0);

        vm.warp(block.timestamp + 7 days + 1);

        IGovernor.ProposalState state = governor.state(proposalId);
        assertEq(uint256(state), uint256(IGovernor.ProposalState.Defeated));
    }

    function test_CannotVoteTwice() public {
        uint256 proposalId = _createEmptyProposal();
        vm.warp(block.timestamp + 1);

        vm.startPrank(alice);
        governor.castVote(proposalId, 1);
        vm.expectRevert();
        governor.castVote(proposalId, 0);
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {VegaVotingToken} from "../src/VegaVotingToken.sol";
import {VegaVotingStaking} from "../src/VegaVotingStaking.sol";
import {VegaVotingGovernance} from "../src/VegaVotingGovernance.sol";
import {VegaVotingResultNFT} from "../src/VegaVotingResultNFT.sol";

contract VegaVotingTest is Test {
    VegaVotingToken public vvToken;
    VegaVotingStaking public staking;
    VegaVotingGovernance public governance;
    VegaVotingResultNFT public resultNFT;

    address public admin = address(1);
    address public alice = address(2);
    address public bob   = address(3);

    uint256 constant YEAR = 365 days;
    uint256 constant TOKENS = 100 ether; // 100 VV

    function setUp() public {
        vm.startPrank(admin);

        // Deploy token
        vvToken = new VegaVotingToken(admin);

        // Deploy staking
        staking = new VegaVotingStaking(address(vvToken), admin);

        // Deploy result NFT — owner will be set to governance after deployment
        // We deploy governance first, then NFT with governance as owner
        // But governance needs NFT address... so deploy NFT with admin, then transfer ownership.
        resultNFT = new VegaVotingResultNFT(admin);

        // Deploy governance
        governance = new VegaVotingGovernance(address(staking), address(resultNFT), admin);

        // Transfer NFT ownership to governance so only governance can mint
        resultNFT.transferOwnership(address(governance));

        // Mint tokens to alice and bob
        vvToken.mint(alice, 1000 ether);
        vvToken.mint(bob, 500 ether);

        vm.stopPrank();
    }

    // ──────────────────────────────────────────────────────────────
    // Token Tests
    // ──────────────────────────────────────────────────────────────

    function test_TokenNameAndSymbol() public view {
        assertEq(vvToken.name(), "VegaVoting");
        assertEq(vvToken.symbol(), "VV");
    }

    function test_MintOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vvToken.mint(alice, 100 ether);
    }

    // ──────────────────────────────────────────────────────────────
    // Staking Tests
    // ──────────────────────────────────────────────────────────────

    function test_StakeAndGetVotingPower() public {
        vm.startPrank(alice);
        vvToken.approve(address(staking), TOKENS);
        staking.stake(TOKENS, 2); // 2 years
        vm.stopPrank();

        uint256 vp = staking.getVotingPower(alice);
        // VP = D_remain^2 * A = (2 * 365 days)^2 * 100e18
        uint256 expected = uint256(2 * YEAR) * uint256(2 * YEAR) * TOKENS;
        assertEq(vp, expected);
    }

    function test_StakeInvalidDurationReverts() public {
        vm.startPrank(alice);
        vvToken.approve(address(staking), TOKENS);

        vm.expectRevert();
        staking.stake(TOKENS, 0); // 0 years — invalid

        vm.expectRevert();
        staking.stake(TOKENS, 5); // 5 years — invalid

        vm.stopPrank();
    }

    function test_StakeZeroAmountReverts() public {
        vm.startPrank(alice);
        vvToken.approve(address(staking), TOKENS);
        vm.expectRevert();
        staking.stake(0, 1);
        vm.stopPrank();
    }

    function test_VotingPowerDecaysOverTime() public {
        vm.startPrank(alice);
        vvToken.approve(address(staking), TOKENS);
        staking.stake(TOKENS, 2); // 2 years
        vm.stopPrank();

        uint256 vpBefore = staking.getVotingPower(alice);

        // Advance 1 year
        vm.warp(block.timestamp + YEAR);

        uint256 vpAfter = staking.getVotingPower(alice);
        // After 1 year, D_remain = 1 year. VP = (1 year)^2 * 100e18
        uint256 expectedAfter = uint256(YEAR) * uint256(YEAR) * TOKENS;
        assertEq(vpAfter, expectedAfter);
        assertGt(vpBefore, vpAfter);
    }

    function test_VotingPowerZeroAfterExpiry() public {
        vm.startPrank(alice);
        vvToken.approve(address(staking), TOKENS);
        staking.stake(TOKENS, 1);
        vm.stopPrank();

        // Advance past expiry
        vm.warp(block.timestamp + YEAR + 1);
        uint256 vp = staking.getVotingPower(alice);
        assertEq(vp, 0);
    }

    function test_UnstakeAfterExpiry() public {
        vm.startPrank(alice);
        vvToken.approve(address(staking), TOKENS);
        staking.stake(TOKENS, 1);
        vm.stopPrank();

        uint256 balBefore = vvToken.balanceOf(alice);

        vm.warp(block.timestamp + YEAR);
        vm.prank(alice);
        staking.unstake(0);

        uint256 balAfter = vvToken.balanceOf(alice);
        assertEq(balAfter - balBefore, TOKENS);
    }

    function test_UnstakeBeforeExpiryReverts() public {
        vm.startPrank(alice);
        vvToken.approve(address(staking), TOKENS);
        staking.stake(TOKENS, 2);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert();
        staking.unstake(0);
    }

    function test_MultipleStakes() public {
        vm.startPrank(alice);
        vvToken.approve(address(staking), 200 ether);
        staking.stake(100 ether, 1);
        staking.stake(100 ether, 4);
        vm.stopPrank();

        uint256 vp = staking.getVotingPower(alice);
        uint256 expected = uint256(YEAR) * uint256(YEAR) * 100 ether
                         + uint256(4 * YEAR) * uint256(4 * YEAR) * 100 ether;
        assertEq(vp, expected);
        assertEq(staking.getStakeCount(alice), 2);
    }

    // ──────────────────────────────────────────────────────────────
    // Governance Tests
    // ──────────────────────────────────────────────────────────────

    function _stakeForAliceAndBob() internal {
        vm.startPrank(alice);
        vvToken.approve(address(staking), 200 ether);
        staking.stake(200 ether, 2);
        vm.stopPrank();

        vm.startPrank(bob);
        vvToken.approve(address(staking), 100 ether);
        staking.stake(100 ether, 2);
        vm.stopPrank();
    }

    function _createVoting(bytes32 id, uint256 deadline, uint256 threshold) internal {
        vm.prank(admin);
        governance.createVoting(id, deadline, threshold, "Test proposal?");
    }

    function test_CreateVoting() public {
        bytes32 vid = keccak256("vote-1");
        uint256 deadline = block.timestamp + 7 days;

        vm.prank(admin);
        governance.createVoting(vid, deadline, 1000, "Should we do X?");

        (bytes32 id, uint256 dl,,,,,,) = governance.getVoting(vid);
        assertEq(id, vid);
        assertEq(dl, deadline);
    }

    function test_CreateVotingOnlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        governance.createVoting(keccak256("x"), block.timestamp + 1 days, 1000, "desc");
    }

    function test_DuplicateVotingReverts() public {
        bytes32 vid = keccak256("vote-1");
        vm.startPrank(admin);
        governance.createVoting(vid, block.timestamp + 1 days, 1000, "desc");
        vm.expectRevert();
        governance.createVoting(vid, block.timestamp + 2 days, 2000, "desc2");
        vm.stopPrank();
    }

    function test_CastVoteYes() public {
        _stakeForAliceAndBob();
        bytes32 vid = keccak256("vote-1");
        uint256 deadline = block.timestamp + 7 days;
        _createVoting(vid, deadline, type(uint256).max);

        uint256 aliceVP = staking.getVotingPower(alice);

        vm.prank(alice);
        governance.castVote(vid, true);

        (,,,, uint256 yesVotes,,,) = governance.getVoting(vid);
        assertEq(yesVotes, aliceVP);
    }

    function test_CastVoteNo() public {
        _stakeForAliceAndBob();
        bytes32 vid = keccak256("vote-1");
        _createVoting(vid, block.timestamp + 7 days, type(uint256).max);

        uint256 bobVP = staking.getVotingPower(bob);

        vm.prank(bob);
        governance.castVote(vid, false);

        (,,,,, uint256 noVotes,,) = governance.getVoting(vid);
        assertEq(noVotes, bobVP);
    }

    function test_CannotVoteTwice() public {
        _stakeForAliceAndBob();
        bytes32 vid = keccak256("vote-1");
        _createVoting(vid, block.timestamp + 7 days, type(uint256).max);

        vm.startPrank(alice);
        governance.castVote(vid, true);
        vm.expectRevert();
        governance.castVote(vid, false);
        vm.stopPrank();
    }

    function test_CannotVoteWithoutPower() public {
        bytes32 vid = keccak256("vote-1");
        _createVoting(vid, block.timestamp + 7 days, 1000);

        address nobody = address(99);
        vm.prank(nobody);
        vm.expectRevert();
        governance.castVote(vid, true);
    }

    function test_CannotVoteAfterDeadline() public {
        _stakeForAliceAndBob();
        bytes32 vid = keccak256("vote-1");
        uint256 deadline = block.timestamp + 7 days;
        _createVoting(vid, deadline, type(uint256).max);

        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert();
        governance.castVote(vid, true);
    }

    function test_FinalizeAfterDeadline() public {
        _stakeForAliceAndBob();
        bytes32 vid = keccak256("vote-1");
        uint256 deadline = block.timestamp + 7 days;

        // Set threshold unreachably high so it finalizes by deadline
        _createVoting(vid, deadline, type(uint256).max);

        vm.prank(alice);
        governance.castVote(vid, true);

        // Warp past deadline
        vm.warp(deadline);
        governance.finalizeVoting(vid);

        (,,,,,, VegaVotingGovernance.VoteStatus status,) = governance.getVoting(vid);
        assertEq(uint256(status), uint256(VegaVotingGovernance.VoteStatus.Finalized));
    }

    function test_EarlyFinalization() public {
        _stakeForAliceAndBob();
        bytes32 vid = keccak256("vote-1");
        uint256 deadline = block.timestamp + 7 days;

        uint256 aliceVP = staking.getVotingPower(alice);
        // Set threshold equal to Alice's voting power
        _createVoting(vid, deadline, aliceVP);

        vm.prank(alice);
        governance.castVote(vid, true);

        // Finalize early — threshold met
        governance.finalizeVoting(vid);

        (,,,,,, VegaVotingGovernance.VoteStatus status, uint256 nftId) = governance.getVoting(vid);
        assertEq(uint256(status), uint256(VegaVotingGovernance.VoteStatus.Finalized));

        // NFT minted to admin
        assertEq(resultNFT.ownerOf(nftId), admin);
    }

    function test_CannotFinalizeBeforeConditions() public {
        _stakeForAliceAndBob();
        bytes32 vid = keccak256("vote-1");
        _createVoting(vid, block.timestamp + 7 days, type(uint256).max);

        vm.expectRevert();
        governance.finalizeVoting(vid);
    }

    function test_NFTContainsCorrectData() public {
        _stakeForAliceAndBob();
        bytes32 vid = keccak256("vote-1");
        uint256 deadline = block.timestamp + 7 days;

        uint256 aliceVP = staking.getVotingPower(alice);
        _createVoting(vid, deadline, aliceVP);

        vm.prank(alice);
        governance.castVote(vid, true);

        vm.prank(bob);
        governance.castVote(vid, false);

        governance.finalizeVoting(vid);

        (,,,,,,, uint256 nftId) = governance.getVoting(vid);

        (bytes32 storedVotingId,, uint256 yesVotes, uint256 noVotes, bool passed,) = resultNFT.voteResults(nftId);
        assertEq(storedVotingId, vid);
        assertEq(yesVotes, aliceVP);
        assertTrue(passed);
        assertGt(noVotes, 0);

        // tokenURI should not revert
        string memory uri = resultNFT.tokenURI(nftId);
        assertTrue(bytes(uri).length > 0);
    }

    function test_EmergencyFinalize() public {
        _stakeForAliceAndBob();
        bytes32 vid = keccak256("vote-1");
        _createVoting(vid, block.timestamp + 7 days, type(uint256).max);

        vm.prank(admin);
        governance.emergencyFinalize(vid);

        (,,,,,, VegaVotingGovernance.VoteStatus status,) = governance.getVoting(vid);
        assertEq(uint256(status), uint256(VegaVotingGovernance.VoteStatus.Finalized));
    }

    function test_PauseStaking() public {
        vm.prank(admin);
        staking.pause();

        vm.startPrank(alice);
        vvToken.approve(address(staking), TOKENS);
        vm.expectRevert();
        staking.stake(TOKENS, 1);
        vm.stopPrank();

        vm.prank(admin);
        staking.unpause();

        vm.startPrank(alice);
        staking.stake(TOKENS, 1);
        vm.stopPrank();
    }

    function test_PauseGovernance() public {
        _stakeForAliceAndBob();

        vm.prank(admin);
        governance.pause();

        vm.prank(admin);
        vm.expectRevert();
        governance.createVoting(keccak256("x"), block.timestamp + 1 days, 1000, "desc");

        vm.prank(admin);
        governance.unpause();
    }

    // ──────────────────────────────────────────────────────────────
    // Full E2E Scenario
    // ──────────────────────────────────────────────────────────────

    function test_FullE2EScenario() public {
        // 1. Alice and Bob stake
        vm.startPrank(alice);
        vvToken.approve(address(staking), 500 ether);
        staking.stake(500 ether, 4); // 4 years
        vm.stopPrank();

        vm.startPrank(bob);
        vvToken.approve(address(staking), 200 ether);
        staking.stake(200 ether, 1); // 1 year
        vm.stopPrank();

        // 2. Admin creates a vote
        bytes32 vid = keccak256("proposal-alpha");
        uint256 deadline = block.timestamp + 14 days;
        uint256 aliceVP = staking.getVotingPower(alice);

        vm.prank(admin);
        governance.createVoting(vid, deadline, aliceVP, "Should we upgrade the protocol?");

        // 3. Alice votes yes
        vm.prank(alice);
        governance.castVote(vid, true);

        // 4. Early finalization — threshold met by Alice alone
        governance.finalizeVoting(vid);

        // 5. Verify
        (,,,, uint256 yesVotes, uint256 noVotes, VegaVotingGovernance.VoteStatus status, uint256 nftId) =
            governance.getVoting(vid);
        assertEq(uint256(status), uint256(VegaVotingGovernance.VoteStatus.Finalized));
        assertEq(yesVotes, aliceVP);
        assertEq(noVotes, 0);
        assertEq(resultNFT.ownerOf(nftId), admin);
    }
}

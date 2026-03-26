// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {VegaVotingToken} from "../src/VegaVotingToken.sol";
import {VegaVotingStaking} from "../src/VegaVotingStaking.sol";
import {VegaVotingGovernance} from "../src/VegaVotingGovernance.sol";
import {VegaVotingResultNFT} from "../src/VegaVotingResultNFT.sol";

/**
 * @title Deploy
 * @notice Deploy all Vega Voting contracts to Sepolia testnet.
 *
 * Usage:
 *   forge script script/Deploy.s.sol:Deploy \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY
 */
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy VV Token
        VegaVotingToken vvToken = new VegaVotingToken(deployer);
        console.log("VegaVotingToken:", address(vvToken));

        // 2. Deploy Staking
        VegaVotingStaking staking = new VegaVotingStaking(address(vvToken), deployer);
        console.log("VegaVotingStaking:", address(staking));

        // 3. Deploy Result NFT (owner = deployer temporarily)
        VegaVotingResultNFT resultNFT = new VegaVotingResultNFT(deployer);
        console.log("VegaVotingResultNFT:", address(resultNFT));

        // 4. Deploy Governance
        VegaVotingGovernance governance = new VegaVotingGovernance(
            address(staking),
            address(resultNFT),
            deployer
        );
        console.log("VegaVotingGovernance:", address(governance));

        // 5. Transfer NFT ownership to governance
        resultNFT.transferOwnership(address(governance));
        console.log("NFT ownership transferred to governance");

        vm.stopBroadcast();
    }
}

/**
 * @title SetupVote
 * @notice After deployment, run this to set up a demo vote with two addresses.
 *
 * Required env vars:
 *   PRIVATE_KEY        - Deployer (admin) private key
 *   VOTER_PRIVATE_KEY  - Second voter private key
 *   VV_TOKEN           - VegaVotingToken address
 *   STAKING            - VegaVotingStaking address
 *   GOVERNANCE         - VegaVotingGovernance address
 *
 * Usage:
 *   forge script script/Deploy.s.sol:SetupVote \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast
 */
contract SetupVote is Script {
    function run() external {
        uint256 adminKey = vm.envUint("PRIVATE_KEY");
        uint256 voterKey = vm.envUint("VOTER_PRIVATE_KEY");
        address admin = vm.addr(adminKey);
        address voter = vm.addr(voterKey);

        address vvTokenAddr = vm.envAddress("VV_TOKEN");
        address stakingAddr = vm.envAddress("STAKING");
        address governanceAddr = vm.envAddress("GOVERNANCE");

        VegaVotingToken vvToken = VegaVotingToken(vvTokenAddr);
        VegaVotingStaking staking = VegaVotingStaking(stakingAddr);
        VegaVotingGovernance governance = VegaVotingGovernance(governanceAddr);

        // === Admin: mint tokens, stake, create vote ===
        vm.startBroadcast(adminKey);

        // Mint tokens to both addresses
        vvToken.mint(admin, 1000 ether);
        vvToken.mint(voter, 500 ether);

        // Admin stakes
        vvToken.approve(address(staking), 500 ether);
        staking.stake(500 ether, 2); // 2 years

        // Create a voting
        bytes32 votingId = keccak256("proposal-001");
        governance.createVoting(
            votingId,
            block.timestamp + 7 days,
            1, // low threshold for demo
            "Should Vega Protocol upgrade to v2?"
        );

        // Admin votes yes
        governance.castVote(votingId, true);

        vm.stopBroadcast();

        // === Voter: stake and vote ===
        vm.startBroadcast(voterKey);

        vvToken.approve(address(staking), 200 ether);
        staking.stake(200 ether, 1); // 1 year

        governance.castVote(votingId, false);

        vm.stopBroadcast();

        console.log("Vote setup complete.");
        console.log("Admin:", admin);
        console.log("Voter:", voter);
    }
}

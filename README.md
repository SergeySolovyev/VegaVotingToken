# Vega Voting Protocol

HW 6 -- Voting Contract.  
Course: EVM Smart Contracts, Vega Institute Foundation.

## Overview

This repository contains a system of Solidity smart contracts that implements
on-chain governance voting using a dedicated ERC-20 token (VegaVoting, ticker
**VV**).  Participants stake VV tokens for a fixed duration (1--4 years) and
receive time-weighted voting power.  When a vote is finalized, an ERC-721 NFT
encoding the results is minted on-chain.

## Contract architecture

```
VegaVotingToken (ERC-20)
        |
        v
VegaVotingStaking  ------>  VegaVotingGovernance
  (stake / unstake)           (create / cast / finalize)
                                      |
                                      v
                              VegaVotingResultNFT (ERC-721)
```

| Contract | File | Description |
|---|---|---|
| `VegaVotingToken` | `src/VegaVotingToken.sol` | ERC-20 token with owner-restricted minting. |
| `VegaVotingStaking` | `src/VegaVotingStaking.sol` | Accepts VV stakes for 1--4 years; computes voting power. |
| `VegaVotingGovernance` | `src/VegaVotingGovernance.sol` | Voting lifecycle: creation, ballot casting, finalization. |
| `VegaVotingResultNFT` | `src/VegaVotingResultNFT.sol` | ERC-721 minted on finalization; on-chain SVG metadata. |

## Voting power formula

Each user *U* may hold multiple stakes.  The voting power at time *t* is:

```
VP_U(t) = sum_i  D_i_remain(t)^2 * A_i
```

where

```
D_i_remain(t) = T_expiry_i - t
```

- `A_i` -- amount of VV tokens locked in stake *i*.
- `D_i_remain(t)` -- remaining lock duration (seconds).  Zero after expiry.

On-chain, voting power is stored in units of `seconds^2 * wei` to preserve
full precision without floating-point arithmetic.

## Finalization logic

A vote can be finalized under any of the following conditions:

1. **Deadline reached** -- `block.timestamp >= deadline`.  Any address may call
   `finalizeVoting()`.
2. **Threshold met early** -- `yesVotes >= votingPowerThreshold`.  Any address
   may call `finalizeVoting()`.
3. **Emergency** -- the admin calls `emergencyFinalize()` at any time.

On finalization the contract mints an ERC-721 token that records the voting ID,
description, yes/no tallies, outcome, and finalization timestamp.  The NFT
carries on-chain SVG artwork rendered via `tokenURI()`.

## Security measures

- **Access control** -- `Ownable` (OpenZeppelin v5) restricts vote creation and
  emergency actions to the admin.
- **Pausable** -- both the staking and governance contracts can be paused by the
  admin to halt operations in an emergency.
- **ReentrancyGuard** -- applied to all state-mutating external functions.
- **Input validation** -- zero-amount checks, duplicate-vote prevention,
  deadline enforcement, unique voting IDs.

## Dependencies

- Solidity ^0.8.20
- [OpenZeppelin Contracts v5](https://github.com/OpenZeppelin/openzeppelin-contracts)
  (ERC20, ERC721, Ownable, Pausable, ReentrancyGuard, Base64, Strings)
- [Foundry](https://book.getfoundry.sh/) (forge, cast, anvil)

## Build and test

```bash
# Install dependencies
forge install

# Compile
forge build

# Run tests (26 tests)
forge test -vv
```

## Deployment (Sepolia)

```bash
cp .env.example .env
# Fill in SEPOLIA_RPC_URL, PRIVATE_KEY, VOTER_PRIVATE_KEY, ETHERSCAN_API_KEY.

source .env

# Deploy contracts
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Record the deployed addresses in .env (VV_TOKEN, STAKING, GOVERNANCE),
# then set up a demonstration vote from two addresses:
forge script script/Deploy.s.sol:SetupVote \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast
```

## Deployed addresses (Sepolia)

| Contract | Address |
|---|---|
| VegaVotingToken | `0x7d448c1302FFAb6870c3c3132330eE4C240305F1` |
| VegaVotingStaking | `0x502A2603dFF356Aa72a67411f651af3F9Ffb3e33` |
| VegaVotingResultNFT | `0xA5B340389d74AC53EF881A29bFDd0ba31392C986` |
| VegaVotingGovernance | `0x0da3F015fbffFDDBe415d73D77c07e568c1DCF2a` |

A demonstration vote ("Should Vega Protocol upgrade to v2?") was created and
executed using two distinct Sepolia addresses:

- Admin (`0xbb6939f00F3db644A52CFaB604f70947Acec0Ff8`) -- staked 500 VV for
  2 years, voted YES.
- Voter (`0x57F03c3D5821e510154250947522A9423bd26D78`) -- staked 200 VV for
  1 year, voted NO.

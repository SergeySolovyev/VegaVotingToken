# Vega Voting Protocol

HW 6 -- Voting Contract.
Course: EVM Smart Contracts, Vega Institute Foundation.

## Overview

This repository contains a system of Solidity smart contracts that implements
on-chain governance voting using a dedicated ERC-20 token (VegaVoting, ticker
**VV**).  Participants stake VV tokens for a duration D in Q intersect [1, 4]
(expressed in quarter-year increments, i.e. 4 to 16 quarters) and receive
time-weighted voting power.  When a vote is finalized, an ERC-721 NFT encoding
the results is minted on-chain.

## System design

An interactive diagram is provided in Excalidraw format:

    docs/system-design.excalidraw

Open it at https://excalidraw.com by importing the file.

```
VegaVotingToken (ERC-20)
        |
        v  transferFrom
VegaVotingStaking ----------> VegaVotingGovernance
  stake() / unstake()    getVotingPower()   createVoting()
  D in [4..16] quarters                     castVote() / finalize()
        |                                         |
        |  getVotingPower()                       |  mintResult()
        v  (dashed = extra)                       v
VegaGovernorAdapter                       VegaVotingResultNFT
  (OZ Governor -- extra)                    (ERC-721 + on-chain SVG)
```

## Contracts

| Contract | File | Description |
|---|---|---|
| `VegaVotingToken` | `src/VegaVotingToken.sol` | ERC-20 token with owner-restricted minting. |
| `VegaVotingStaking` | `src/VegaVotingStaking.sol` | Accepts VV stakes for 4--16 quarters (1--4 years in 0.25-year steps); computes voting power. |
| `VegaVotingGovernance` | `src/VegaVotingGovernance.sol` | Voting lifecycle: creation, ballot casting, finalization. |
| `VegaVotingResultNFT` | `src/VegaVotingResultNFT.sol` | ERC-721 minted on finalization; on-chain SVG metadata. |
| `VegaGovernorAdapter` | `src/VegaGovernorAdapter.sol` | Alternative governance using OZ Governor as base (extra). |

## Voting power formula

Each user U may hold multiple stakes.  The voting power at time t is:

```
VP_U(t) = sum_i  D_i_remain(t)^2 * A_i
```

where

```
D_i_remain(t) = T_expiry_i - t
```

- `A_i` -- amount of VV tokens locked in stake i.
- `D_i_remain(t)` -- remaining lock duration (seconds).  Zero after expiry.
- `D_i_initial` -- chosen from Q intersect [1, 4] in 0.25-year (quarter)
  increments.  The `stake()` function accepts `durationQuarters` in [4, 16].

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

No additional off-chain logic is required for finalization.  The admin role
(Ownable) is sufficient for vote creation and emergency control.

## OZ Governor adapter (extra)

`VegaGovernorAdapter` inherits from OpenZeppelin `Governor` and
`GovernorCountingSimple`, bridging the OZ proposal lifecycle with our
staking-based voting power.  It overrides `_getVotes()` to query
`VegaVotingStaking.getVotingPower()` and uses `block.timestamp` as the clock.

Limitation: because voting power is read at cast-time rather than from a
historical snapshot, this adapter does not protect against vote-weight
manipulation between proposal creation and vote casting.  A production system
would integrate checkpoints into the staking contract.

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
  (ERC20, ERC721, Ownable, Pausable, ReentrancyGuard, Governor,
  GovernorCountingSimple, GovernorSettings, Base64, Strings)
- [Foundry](https://book.getfoundry.sh/) (forge, cast, anvil)

## Build and test

```bash
forge install
forge build
forge test -vv   # 33 tests
```

## Deployment (Sepolia)

```bash
cp .env.example .env
# Fill in SEPOLIA_RPC_URL, PRIVATE_KEY, VOTER_PRIVATE_KEY.

source .env

forge script script/Deploy.s.sol:Deploy \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

# Record deployed addresses in .env (VV_TOKEN, STAKING, GOVERNANCE),
# then set up a demonstration vote from two addresses:
forge script script/Deploy.s.sol:SetupVote \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast
```

## Deployed addresses (Sepolia)

| Contract | Address |
|---|---|
| VegaVotingToken | `0xc4a8a6147cC7F4F5a94Df16172787d415479DF70` |
| VegaVotingStaking | `0x4eda1567525A203e14456D35Be112f012a4Ba3f4` |
| VegaVotingResultNFT | `0xf8bBbD6a9B7A711594d49e9174Fa50749bbBb2B1` |
| VegaVotingGovernance | `0x7ED0281E5C6Ff1105E017203068890da77F4473a` |

A demonstration vote ("Should Vega Protocol upgrade to v2?") was created and
executed using two distinct Sepolia addresses:

- Admin (`0xbb6939f00F3db644A52CFaB604f70947Acec0Ff8`) -- staked 500 VV for
  8 quarters (2 years), voted YES.
- Voter (`0x57F03c3D5821e510154250947522A9423bd26D78`) -- staked 200 VV for
  4 quarters (1 year), voted NO.



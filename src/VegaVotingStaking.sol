// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VegaVotingStaking
 * @notice Manages staking of VV tokens. Users stake A_i tokens for a duration
 *         D_i in Q intersect [1, 4], expressed in quarter-year increments
 *         (i.e. 4 to 16 quarters, corresponding to 1.0 to 4.0 years).
 *
 *         Voting power is computed as:
 *           VP_U(t) = sum_i D_i_remain(t)^2 * A_i
 *         where D_i_remain(t) = T_expiry_i - t.
 *
 * @dev Duration is stored in seconds internally. The minimum granularity is
 *      one quarter (QUARTER = 91 days). Callers pass durationQuarters in [4, 16].
 */
contract VegaVotingStaking is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -- Constants --
    uint256 public constant QUARTER = 91 days;          // ~0.25 year
    uint256 public constant MIN_QUARTERS = 4;            // 1 year  = 4 quarters
    uint256 public constant MAX_QUARTERS = 16;           // 4 years = 16 quarters

    // -- State --
    IERC20 public immutable vvToken;

    struct Stake {
        uint256 amount;      // A_i: amount of VV tokens staked
        uint256 expiry;      // T_expiry: timestamp when stake expires
        bool withdrawn;      // whether the stake has been withdrawn
    }

    /// @notice user => array of stakes
    mapping(address => Stake[]) public stakes;

    // -- Events --
    event Staked(
        address indexed user,
        uint256 stakeIndex,
        uint256 amount,
        uint256 durationSeconds,
        uint256 expiry
    );
    event Unstaked(address indexed user, uint256 stakeIndex, uint256 amount);

    // -- Errors --
    error InvalidDuration(uint256 durationQuarters);
    error ZeroAmount();
    error StakeNotExpired(uint256 expiry);
    error StakeAlreadyWithdrawn();
    error InvalidStakeIndex();

    constructor(address _vvToken, address _owner) Ownable(_owner) {
        vvToken = IERC20(_vvToken);
    }

    // -- External Functions --

    /**
     * @notice Stake `amount` VV tokens for `durationQuarters` quarters.
     * @dev durationQuarters must be in [4, 16], corresponding to [1.0, 4.0] years
     *      in 0.25-year steps (i.e. D_i in Q intersect [1, 4]).
     * @param amount Amount of VV tokens to stake.
     * @param durationQuarters Lock duration in quarters (4 = 1 year, ..., 16 = 4 years).
     */
    function stake(uint256 amount, uint256 durationQuarters) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (durationQuarters < MIN_QUARTERS || durationQuarters > MAX_QUARTERS) {
            revert InvalidDuration(durationQuarters);
        }

        vvToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 durationSeconds = durationQuarters * QUARTER;
        uint256 expiry = block.timestamp + durationSeconds;
        uint256 idx = stakes[msg.sender].length;
        stakes[msg.sender].push(Stake({
            amount: amount,
            expiry: expiry,
            withdrawn: false
        }));

        emit Staked(msg.sender, idx, amount, durationSeconds, expiry);
    }

    /**
     * @notice Withdraw an expired stake.
     * @param stakeIndex Index of the stake in the user's array.
     */
    function unstake(uint256 stakeIndex) external nonReentrant {
        if (stakeIndex >= stakes[msg.sender].length) revert InvalidStakeIndex();
        Stake storage s = stakes[msg.sender][stakeIndex];
        if (s.withdrawn) revert StakeAlreadyWithdrawn();
        if (block.timestamp < s.expiry) revert StakeNotExpired(s.expiry);

        s.withdrawn = true;
        vvToken.safeTransfer(msg.sender, s.amount);

        emit Unstaked(msg.sender, stakeIndex, s.amount);
    }

    // -- View Functions --

    /**
     * @notice Calculate the current voting power of a user.
     *         VP_U(t) = sum_i D_i_remain(t)^2 * A_i
     *         where D_i_remain(t) = max(T_expiry_i - t, 0)
     * @dev Voting power is expressed in (seconds^2 * token_wei). This preserves
     *      full precision on-chain.
     * @param user The address to query.
     * @return vp The total voting power (in raw units: seconds^2 * wei).
     */
    function getVotingPower(address user) external view returns (uint256 vp) {
        Stake[] storage userStakes = stakes[user];
        uint256 len = userStakes.length;
        for (uint256 i; i < len;) {
            Stake storage s = userStakes[i];
            if (!s.withdrawn && block.timestamp < s.expiry) {
                uint256 remaining = s.expiry - block.timestamp;
                vp += remaining * remaining * s.amount;
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice Get the number of stakes for a user.
     */
    function getStakeCount(address user) external view returns (uint256) {
        return stakes[user].length;
    }

    /**
     * @notice Get details of a specific stake.
     */
    function getStake(address user, uint256 index) external view returns (uint256 amount, uint256 expiry, bool withdrawn) {
        Stake storage s = stakes[user][index];
        return (s.amount, s.expiry, s.withdrawn);
    }

    // -- Admin Functions --

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

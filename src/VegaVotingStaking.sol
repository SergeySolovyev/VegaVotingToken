// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VegaVotingStaking
 * @notice Manages staking of VV tokens. Users stake A_i tokens for a duration D_i in {1, 2, 3, 4} (in years).
 *         Voting power is calculated as: VP_U(t) = sum_i D_i_remain(t)^2 * A_i,
 *         where D_i_remain(t) = T_expiry - t.
 * @dev Duration is expressed in seconds internally but constrained to 1--4 whole years at stake time.
 */
contract VegaVotingStaking is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // -- Constants--
    uint256 public constant MIN_DURATION = 365 days;   // ~1 year
    uint256 public constant MAX_DURATION = 4 * 365 days; // ~4 years
    uint256 public constant DURATION_UNIT = 365 days;   // 1 year granularity ({1, 2, 3, 4} years)

    // -- State--
    IERC20 public immutable vvToken;

    struct Stake {
        uint256 amount;      // A_i: amount of VV tokens staked
        uint256 expiry;      // T_expiry: timestamp when stake expires
        bool withdrawn;      // whether the stake has been withdrawn
    }

    /// @notice user => array of stakes
    mapping(address => Stake[]) public stakes;

    // -- Events--
    event Staked(address indexed user, uint256 stakeIndex, uint256 amount, uint256 duration, uint256 expiry);
    event Unstaked(address indexed user, uint256 stakeIndex, uint256 amount);

    // -- Errors--
    error InvalidDuration(uint256 duration);
    error ZeroAmount();
    error StakeNotExpired(uint256 expiry);
    error StakeAlreadyWithdrawn();
    error InvalidStakeIndex();

    constructor(address _vvToken, address _owner) Ownable(_owner) {
        vvToken = IERC20(_vvToken);
    }

    // -- External Functions--

    /**
     * @notice Stake `amount` VV tokens for `durationYears` years (1, 2, 3, or 4).
     * @param amount Amount of VV tokens to stake.
     * @param durationYears Lock duration in whole years (must be 1, 2, 3, or 4).
     */
    function stake(uint256 amount, uint256 durationYears) external whenNotPaused nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 durationSeconds = durationYears * DURATION_UNIT;
        if (durationSeconds < MIN_DURATION || durationSeconds > MAX_DURATION) {
            revert InvalidDuration(durationYears);
        }

        vvToken.safeTransferFrom(msg.sender, address(this), amount);

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

    // -- View Functions--

    /**
     * @notice Calculate the current voting power of a user.
     *         VP_U(t) = sum_i D_i_remain(t)^2 * A_i
     *         where D_i_remain(t) = max(T_expiry_i - t, 0)
     * @dev Voting power is expressed in (seconds^2 * token_wei). This preserves full precision
     *      on-chain. Off-chain, divide by (365 days)^2 to get "year^2 * tokens" units.
     * @param user The address to query.
     * @return vp The total voting power (in raw units: seconds^2 * wei).
     */
    function getVotingPower(address user) external view returns (uint256 vp) {
        Stake[] storage userStakes = stakes[user];
        uint256 len = userStakes.length;
        for (uint256 i; i < len;) {
            Stake storage s = userStakes[i];
            if (!s.withdrawn && block.timestamp < s.expiry) {
                uint256 remaining = s.expiry - block.timestamp; // D_remain in seconds
                vp += remaining * remaining * s.amount;         // D_remain^2 * A_i
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

    // -- Admin Functions--

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRiskOracle} from "./interfaces/IRiskOracle.sol";

/// @title RiskOracle
/// @notice On-chain risk scoring for registered yield products.
/// @dev Score range is 0-100. Score 0 means "unscored" until updateScore is called.
contract RiskOracle is IRiskOracle {
    mapping(bytes32 => uint256) private scores;

    address public owner;

    event ScoreUpdated(bytes32 indexed productId, uint256 newScore);

    error Unauthorized();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function getScore(bytes32 productId) external view returns (uint256 score) {
        return scores[productId];
    }

    function updateScore(
        bytes32 productId,
        uint256 apyBps,
        uint256 tvlUSD,
        uint256 utilizationBps,
        uint256 contractAgeDays
    ) external onlyOwner returns (uint256 newScore) {
        // --- Utilisation (weight 40) ---
        uint256 utilW = _sub(100, utilizationBps * 100 / 10_000) * 40 / 100;

        // --- TVL (weight 35) ---
        uint256 tvlW = _min(100, tvlUSD * 100 / 10_000_000) * 35 / 100;

        // --- Maturity (weight 15) ---
        uint256 matW = _min(100, contractAgeDays * 100 / 180) * 15 / 100;

        // --- APY sanity (weight 10) ---
        uint256 apyW;
        if (apyBps <= 2_000) {
            apyW = 100 * 10 / 100;
        } else if (apyBps >= 10_000) {
            apyW = 0;
        } else {
            apyW = _sub(100, (apyBps - 2_000) * 100 / 8_000) * 10 / 100;
        }

        uint256 score = _min(100, utilW + tvlW + matW + apyW);
        scores[productId] = score;

        emit ScoreUpdated(productId, score);
        return score;
    }

    function _sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

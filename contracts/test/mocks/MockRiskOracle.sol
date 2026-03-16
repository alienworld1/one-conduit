// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRiskOracle} from "../../src/interfaces/IRiskOracle.sol";

/// @title MockRiskOracle
/// @notice Configurable mock for IRiskOracle — used in ConduitRouter tests.
///         setScore() allows per-test score configuration without deploying the ink! contract.
contract MockRiskOracle is IRiskOracle {
    mapping(uint256 => uint256) private _scores;

    function setScore(uint256 productId, uint256 score) external {
        _scores[productId] = score;
    }

    function getScore(uint256 productId) external view returns (uint256) {
        return _scores[productId];
    }

    function updateScore(
        uint256 productId,
        uint256, // apyBps
        uint256, // tvlUSD
        uint256, // utilizationBps
        uint256  // contractAgeDays
    ) external returns (uint256) {
        return _scores[productId];
    }
}

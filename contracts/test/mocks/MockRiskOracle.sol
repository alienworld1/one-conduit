// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRiskOracle} from "../../src/interfaces/IRiskOracle.sol";

/// @title MockRiskOracle
/// @notice Configurable mock for IRiskOracle used in ConduitRouter tests.
contract MockRiskOracle is IRiskOracle {
    mapping(bytes32 => uint256) private _scores;

    function setScore(bytes32 productId, uint256 score) external {
        _scores[productId] = score;
    }

    function getScore(bytes32 productId) external view returns (uint256) {
        return _scores[productId];
    }

    function updateScore(
        bytes32 productId,
        uint256, // apyBps
        uint256, // tvlUSD
        uint256, // utilizationBps
        uint256  // contractAgeDays
    ) external view returns (uint256) {
        return _scores[productId];
    }
}

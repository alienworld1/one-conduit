// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {RiskOracle} from "../src/RiskOracle.sol";
import {ProductIds} from "../src/libraries/ProductIds.sol";

error Unauthorized();
event ScoreUpdated(bytes32 indexed productId, uint256 newScore);

contract RiskOracleTest is Test {
    RiskOracle oracle;

    address constant alice = address(0xA11CE);
    bytes32 constant PRODUCT = ProductIds.USDC_HUB_LENDING_V1;

    function setUp() public {
        oracle = new RiskOracle();
    }

    function test_getScore_unscored() public view {
        assertEq(oracle.getScore(PRODUCT), 0);
    }

    function test_updateScore_workedExample() public {
        uint256 score = oracle.updateScore(PRODUCT, 500, 5_000_000, 5_000, 180);
        assertEq(score, 62);
    }

    function test_updateScore_persists() public {
        uint256 score = oracle.updateScore(PRODUCT, 2_000, 1_000_000, 7_000, 30);
        assertEq(oracle.getScore(PRODUCT), score);
    }

    function test_updateScore_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(Unauthorized.selector);
        oracle.updateScore(PRODUCT, 2_000, 1_000_000, 7_000, 30);
    }

    function test_updateScore_extremeHighRisk() public {
        uint256 score = oracle.updateScore(PRODUCT, 50_000, 0, 9_500, 0);
        assertEq(score, 2);
    }

    function test_updateScore_extremeLowRisk() public {
        uint256 score = oracle.updateScore(PRODUCT, 100, 10_000_000, 100, 200);
        assertEq(score, 99);
    }

    function test_noUnderflow_highUtilisation() public {
        uint256 score = oracle.updateScore(PRODUCT, 2_000, 0, 15_000, 0);
        assertEq(score, 10);
    }

    function test_noUnderflow_highAPY() public {
        uint256 score = oracle.updateScore(PRODUCT, 50_000, 10_000_000, 0, 180);
        assertEq(score, 90);
    }

    function test_scoreUpdatedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ScoreUpdated(PRODUCT, 45);
        oracle.updateScore(PRODUCT, 2_000, 10_000_000, 10_000, 0);
    }
}

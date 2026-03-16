// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*
 * ILendingPool — minimal interface for a Hub-native Aave-style lending pool.
 * MockLendingPool (src/) implements this for testing and testnet.
 * Single-asset: the pool knows its underlying token from construction.
 *
 * Caller responsibilities:
 *   deposit:   Caller holds underlying and approves this pool before calling.
 *              Pool pulls underlying from caller; mints yield tokens to recipient.
 *   withdraw:  Caller holds yield tokens (pool burns from msg.sender).
 *              Pool sends underlying to recipient.
 */
interface ILendingPool {
    function deposit(uint256 amount, address recipient) external returns (uint256 sharesOut);
    function withdraw(uint256 sharesAmount, address recipient) external returns (uint256 tokensOut);
    function getAPY() external view returns (uint256 apyBps);
    function getTVL() external view returns (uint256 tvlUSD);
    function getUtilizationRate() external view returns (uint256 utilizationBps);
    function yieldToken() external view returns (address);
    function underlyingToken() external view returns (address);
}

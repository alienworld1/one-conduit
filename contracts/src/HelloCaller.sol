// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// IHelloInk — interface matching the ink! v6 HelloInk contract's Solidity ABI.
// get_number() returns uint128 (ink! u128), cast to uint256 at call site.
interface IHelloInk {
    function get_number() external view returns (uint128);
}

// HelloCaller — validates the Solidity → ink! cross-VM call on Paseo Passet Hub.
// Deploy with the HelloInk contract address; then call callInk() to confirm the
// cross-VM path is alive. If this works, RiskOracle.rs in Module 1 is proven.
contract HelloCaller {
    IHelloInk public immutable inkContract;

    constructor(address _inkContract) {
        inkContract = IHelloInk(_inkContract);
    }

    // Calls HelloInk.get_number() across the Solidity↔ink! boundary and returns
    // the result widened to uint256 (safe — uint128 always fits in uint256).
    function callInk() external view returns (uint256) {
        return uint256(inkContract.get_number());
    }
}

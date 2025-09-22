# AstherusVault Oracle Vulnerability Audit Summary

## Executive Summary

**Contract**: AstherusVault (BSC: 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974)
**Audit Focus**: Chainlink Oracle Price Feed Vulnerability
**Date**: 2025-09-22
**Result**: **CONFIRMED - HIGH SEVERITY VULNERABILITY**

## Vulnerability Confirmed

### Missing Oracle Timestamp Validation in `_amountUsd` Function

**Location**: `contracts/AstherusVault.sol` Lines 472-481

The audit confirms that the AstherusVault contract **does NOT check the `updatedAt` timestamp** returned by Chainlink's price oracle. This represents a **HIGH severity security vulnerability**.

## Technical Analysis

### Current Implementation (VULNERABLE)
```solidity
function _amountUsd(address currency, uint256 amount) private view returns (uint256) {
    Token memory token = supportToken[currency];
    uint256 price = token.price;
    if (!token.fixedPrice) {
        AggregatorV3Interface oracle = AggregatorV3Interface(token.priceFeed);
        (, int256 price_,,,) = oracle.latestRoundData();  // ❌ Ignores updatedAt timestamp
        price = uint256(price_);  // ❌ No validation on price value
    }
    return price * amount * (10 ** USD_DECIMALS) / (10 ** (token.priceDecimals + token.currencyDecimals));
}
```

### Key Issues Identified

1. **No Staleness Check**: The function ignores the `updatedAt` timestamp, meaning stale prices could be used indefinitely
2. **No Price Validation**: Direct casting from `int256` to `uint256` without checking for negative or zero values
3. **No Round Validation**: Doesn't verify `answeredInRound >= roundId` to ensure price freshness

## Security Impact

### Attack Scenario
1. **Oracle Failure/Delay**: If Chainlink oracle stops updating (network issues, oracle node failures)
2. **Price Exploitation**: Attacker monitors for price discrepancies between real market and stale oracle
3. **Withdrawal Bypass**: When real price drops but oracle shows old higher price:
   - Attacker can withdraw 2x the intended token amount
   - Withdrawal stays under USD hourly limit based on stale price
   - Example: BNB drops from $600 to $300, attacker withdraws double BNB amount

### Affected Functions
- `withdraw()` - Uses `_amountUsd` for hourly limit checks (Line 432)
- `checkLimit()` - Enforces withdrawal limits based on USD value (Line 512)

## Recommended Fix

### Secure Implementation
```solidity
function _amountUsd(address currency, uint256 amount) private view returns (uint256) {
    Token memory token = supportToken[currency];
    uint256 price = token.price;
    if (!token.fixedPrice) {
        AggregatorV3Interface oracle = AggregatorV3Interface(token.priceFeed);
        (
            uint80 roundId,
            int256 price_,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = oracle.latestRoundData();

        // Critical validation checks
        require(updatedAt > 0, "Invalid oracle response");
        require(block.timestamp - updatedAt <= 3600, "Oracle data is stale"); // 1 hour max
        require(price_ > 0, "Invalid price");
        require(answeredInRound >= roundId, "Stale price round");

        price = uint256(price_);
    }
    return price * amount * (10 ** USD_DECIMALS) / (10 ** (token.priceDecimals + token.currencyDecimals));
}
```

### Additional Recommendations

1. **Configurable Staleness Threshold**: Make the staleness period (currently 3600 seconds) configurable per token
2. **Circuit Breaker**: Implement emergency pause if oracle fails repeatedly
3. **Fallback Oracle**: Consider adding a secondary oracle for critical price feeds
4. **Monitoring**: Set up alerts for oracle staleness events

## Verification Evidence

- **Source Code Review**: Confirmed missing validation in implementation contract (0x31aeb22e148f5b6d0ea5a942c10746caee073378)
- **Chainlink Interface**: Verified that `latestRoundData()` returns 5 values including `updatedAt` timestamp
- **Best Practices**: Chainlink documentation explicitly recommends checking data freshness

## Risk Assessment

- **Severity**: HIGH
- **Likelihood**: MEDIUM (oracle outages are rare but have occurred)
- **Impact**: CRITICAL (could lead to significant fund loss)
- **Urgency**: IMMEDIATE - Should be fixed before any major oracle disruption

## Conclusion

The vulnerability is **REAL and EXPLOITABLE**. The AstherusVault contract fails to implement essential Chainlink oracle safety checks, creating a significant security risk. The provided fix is correct and should be implemented immediately through the contract's upgrade mechanism via the Timelock.

## Files Audited
- `/Users/cyh/ai-work/audit/astherus_vault_impl/contracts/AstherusVault.sol`
- `/Users/cyh/ai-work/audit/astherus_vault_impl/@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol`
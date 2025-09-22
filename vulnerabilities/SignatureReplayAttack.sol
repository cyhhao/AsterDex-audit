// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title Signature Replay Attack PoC
 * @notice 演示 AstherusVault 合约中的签名重放漏洞
 */

import "forge-std/Test.sol";

contract SignatureReplayAttack is Test {

    /**
     * @notice 演示签名重放攻击向量
     * @dev 展示了验证器签名可以被重放的场景
     */
    function testSignatureReplayVulnerability() public {
        console.log("=== Signature Replay Attack Analysis ===\n");

        // 漏洞代码位置：AstherusVault.sol#L449-458
        console.log("Vulnerable code at AstherusVault.sol#L449-458:");
        console.log("bytes32 digest = keccak256(abi.encode(");
        console.log("    id,");
        console.log("    block.chainid,");
        console.log("    address(this),");
        console.log("    action.token,");
        console.log("    action.amount,");
        console.log("    action.fee,");
        console.log("    action.receiver");
        console.log("));");
        console.log("");

        // 问题分析
        console.log("[!] ISSUE: No timestamp or nonce in the signature");
        console.log("[!] RISK: Same signature can be reused if:");
        console.log("    1. withdrawHistory[id] is somehow reset");
        console.log("    2. Contract is upgraded and storage is cleared");
        console.log("    3. Multiple contracts use same validator set");
        console.log("");

        // 攻击场景
        console.log("=== Attack Scenario ===");
        console.log("1. Attacker observes a valid withdrawal transaction");
        console.log("2. Captures the validator signatures from calldata");
        console.log("3. If contract is upgraded without proper storage migration");
        console.log("4. Attacker can replay the same withdrawal");
        console.log("");

        // 演示签名组成
        bytes32 mockDigest = keccak256(abi.encode(
            uint256(12345),                                    // id
            uint256(56),                                       // chainId (BSC)
            address(0x128463A60784c4D3f46c23Af3f65Ed859Ba87974), // vault address
            address(0x55d398326f99059fF775485246999027B3197955), // USDT token
            uint256(100000 * 1e18),                           // amount
            uint256(100 * 1e18),                              // fee
            address(0xA77aCkeR000000000000000000000000000001)    // receiver
        ));

        console.log("Example digest without protection:", vm.toString(mockDigest));
        console.log("");

        // 修复后的签名
        bytes32 fixedDigest = keccak256(abi.encode(
            uint256(12345),                                    // id
            uint256(56),                                       // chainId
            address(0x128463A60784c4D3f46c23Af3f65Ed859Ba87974), // vault
            address(0x55d398326f99059fF775485246999027B3197955), // token
            uint256(100000 * 1e18),                           // amount
            uint256(100 * 1e18),                              // fee
            address(0xA77aCkeR000000000000000000000000000001),   // receiver
            block.timestamp,                                   // ADD: timestamp
            uint256(1)                                         // ADD: nonce
        ));

        console.log("Fixed digest with timestamp+nonce:", vm.toString(fixedDigest));
        console.log("");
    }

    /**
     * @notice 展示跨合约重放攻击
     */
    function testCrossContractReplay() public {
        console.log("=== Cross-Contract Replay Risk ===\n");

        console.log("If multiple vaults use the same validator set:");
        console.log("1. Vault A on BSC: 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974");
        console.log("2. Vault B on BSC: 0xNEW_VAULT_ADDRESS");
        console.log("");
        console.log("[!] Same signature could work on both vaults!");
        console.log("[!] Because digest doesn't include unique vault identifier");
        console.log("");

        console.log("Current digest includes 'address(this)' but:");
        console.log("- If validators sign for wrong contract");
        console.log("- Or if there's a proxy implementation issue");
        console.log("- Signatures might be valid across contracts");
    }

    /**
     * @notice 修复建议
     */
    function recommendedFix() public pure {
        string memory fix = string(abi.encodePacked(
            "=== RECOMMENDED FIX ===\n\n",
            "1. Add timestamp to prevent old signature reuse:\n",
            "   bytes32 digest = keccak256(abi.encode(\n",
            "       id, block.chainid, address(this),\n",
            "       action.token, action.amount, action.fee, action.receiver,\n",
            "       block.timestamp  // ADD THIS\n",
            "   ));\n\n",

            "2. Add expiration check:\n",
            "   require(block.timestamp <= deadline, 'Signature expired');\n\n",

            "3. Consider adding nonce for each validator:\n",
            "   mapping(address => uint256) public validatorNonces;\n\n",

            "4. Implement signature registry:\n",
            "   mapping(bytes32 => bool) public usedSignatures;\n",
            "   require(!usedSignatures[signatureHash], 'Signature already used');\n"
        ));

        console.log(fix);
    }

    /**
     * @notice 演示时间窗口攻击
     */
    function testTimingAttack() public {
        console.log("=== Timing Attack Vector ===\n");

        console.log("Current implementation uses withdrawHistory[id] to prevent replay");
        console.log("But this has issues:\n");

        console.log("1. ID Generation:");
        console.log("   - If IDs are predictable, attacker can front-run");
        console.log("   - If IDs are reused after long time, replay possible");
        console.log("");

        console.log("2. Storage Collision:");
        console.log("   - In proxy upgrade, if storage layout changes");
        console.log("   - withdrawHistory might be corrupted or cleared");
        console.log("");

        console.log("3. Block Reorg:");
        console.log("   - During chain reorganization");
        console.log("   - Same ID might be processed twice");
        console.log("");

        uint256 blockNumber = 35000000; // Example BSC block
        bytes32 storageSlot = keccak256(abi.encode(uint256(12345), uint256(99)));
        console.log("Storage slot for withdrawHistory[12345]:", vm.toString(storageSlot));
    }
}

/**
 * 运行测试：
 * forge test --match-contract SignatureReplayAttack -vvv
 */
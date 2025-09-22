# AsterDex 智能合约详细安全审计报告

## 目录
1. [审计概述](#审计概述)
2. [严重漏洞](#严重漏洞-critical)
3. [高危风险](#高危风险-high)
4. [中等风险](#中等风险-medium)
5. [低风险问题](#低风险问题-low)
6. [代码质量问题](#代码质量问题)
7. [修复建议](#修复建议)
8. [测试命令](#测试命令)

## 审计概述

- **审计日期**: 2025年9月22日
- **审计版本**: v1.0.0
- **审计方法**: 静态代码分析 + 链上验证 + 漏洞PoC开发
- **审计团队**: 独立安全研究员
- **GitHub仓库**: https://github.com/cyhhao/AsterDex-audit

### 审计范围

| 合约名称 | 地址 | 链 | 文件位置 |
|---------|------|-----|---------|
| AstherusVault | 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974 | BSC | contracts/AstherusVault.sol |
| AsBnbMinter | 0x2F31ab8950c50080E77999fa456372f276952fD8 | BSC | src/AsBnbMinter.sol |
| AsBNB Token | 0x77734e70b6E88b4d82fE632a168EDf6e700912b6 | BSC | src/AsBNB.sol |
| asBTC Token | 0x184b72289c0992BDf96751354680985a7C4825d6 | BSC | contracts/oft/asBTC.sol |
| asUSDF Token | 0x917AF46B3C3c6e1Bb7286B9F59637Fb7C65851Fb | BSC | contracts/oft/asUSDF.sol |
| asCAKE Token | 0x9817F4c9f968a553fF6caEf1a2ef6cF1386F16F7 | BSC | src/AssToken.sol |
| AstherusTimelock | 0xdD95D454ea23dE750aa46D093C7B04E3F5b8b6B5 | BSC | contracts/AstherusTimelock.sol |

---

## 严重漏洞 (CRITICAL)

### CRIT-01: Chainlink 价格预言机时间戳验证缺失

**严重等级**: 🔴 Critical
**影响**: 资金损失风险
**可能性**: 中等
**状态**: ✅ 已确认，需立即修复

#### 漏洞位置
- **文件**: `contracts/AstherusVault.sol`
- **函数**: `_amountUsd`
- **行号**: L472-L481

#### 存在问题的代码
```solidity
// contracts/AstherusVault.sol#L472-L481
function _amountUsd(address currency, uint256 amount) private view returns (uint256) {
    Token memory token = supportToken[currency];
    uint256 price = token.price;
    if (!token.fixedPrice) {
        AggregatorV3Interface oracle = AggregatorV3Interface(token.priceFeed);
        (, int256 price_,,,) = oracle.latestRoundData(); // ❌ 问题：忽略了 updatedAt
        price = uint256(price_); // ❌ 问题：没有验证价格有效性
    }
    return price * amount * (10 ** USD_DECIMALS) / (10 ** (token.priceDecimals + token.currencyDecimals));
}
```

#### 技术分析

`latestRoundData()` 返回5个值，但合约只使用了 `price_`：

```solidity
(
    uint80 roundId,        // 未使用 - 回合ID
    int256 answer,         // 使用 - 价格值
    uint256 startedAt,     // 未使用 - 回合开始时间
    uint256 updatedAt,     // ❌ 关键问题 - 价格更新时间被忽略
    uint80 answeredInRound // 未使用 - 计算答案的回合ID
) = oracle.latestRoundData();
```

#### 攻击场景

1. **T0时刻**: Chainlink 预言机正常，BNB 价格 = $600
2. **T0+1小时**: 预言机因故障停止更新
3. **T0+2小时**: 实际市场 BNB 价格跌至 $300
4. **攻击执行**:
   - 攻击者调用 `withdraw()` 提取 1000 BNB
   - 合约使用过期的 $600 价格计算：1000 * $600 = $600,000
   - 实际价值：1000 * $300 = $300,000
   - **结果**: 攻击者提取了2倍于限额的资金

#### 影响的功能

此漏洞影响所有依赖价格计算的功能：

1. **withdraw() - L432**: 提款限额检查
2. **checkLimit() - L512**: 每小时限额验证
3. **batchedDepositWithPermit() - L371-420**: 批量存款处理

#### PoC 代码
完整的漏洞证明代码：[vulnerabilities/PriceOracleExploit.sol](./vulnerabilities/PriceOracleExploit.sol)

#### 修复方案

```solidity
// contracts/AstherusVault.sol#L472-L481 - 建议修改
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

        // 添加完整的验证
        require(updatedAt > 0, "Invalid timestamp");
        require(block.timestamp - updatedAt <= 3600, "Price data is stale"); // 1小时最大延迟
        require(price_ > 0, "Invalid price");
        require(answeredInRound >= roundId, "Stale round");

        price = uint256(price_);
    }
    return price * amount * (10 ** USD_DECIMALS) / (10 ** (token.priceDecimals + token.currencyDecimals));
}
```

---

## 高危风险 (HIGH)

### HIGH-01: 验证器签名重放攻击

**严重等级**: 🟠 High
**影响**: 未授权的提款
**可能性**: 中等

#### 漏洞位置
- **文件**: `contracts/AstherusVault.sol`
- **函数**: `verifyValidatorSignature`
- **行号**: L487-L509

#### 存在问题的代码
```solidity
// contracts/AstherusVault.sol#L487-L509
function verifyValidatorSignature(
    uint256 id,
    Action[] memory actions,
    bytes32 validatorHash,
    uint256 deadline,
    bytes[] calldata signatures
) private {
    require(block.timestamp <= deadline, "must process request before deadline");
    require(!withdrawHistory[id], "withdrawal already processed");

    bytes32 digest = keccak256(abi.encode(
        id,
        block.chainid,
        address(this),
        actions[0].token,
        actions[0].amount,
        actions[0].fee,
        actions[0].receiver
    )); // ❌ 缺少 nonce 或时间戳

    // ... 验证签名逻辑
}
```

#### 技术分析

签名消息中只包含：
- `id`: 提款ID
- `chainid`: 链ID
- `address(this)`: 合约地址
- 提款详情（代币、金额、费用、接收者）

**缺失的安全要素**：
- ❌ 没有 nonce（防止重放）
- ❌ 没有时间戳（限制有效期）
- ❌ 没有合约版本标识

#### 攻击场景

1. 攻击者监听并收集有效的验证器签名
2. 在合约升级或重新部署后
3. 重放旧签名执行未授权提款

#### PoC 代码
[vulnerabilities/SignatureReplayAttack.sol](./vulnerabilities/SignatureReplayAttack.sol)

#### 修复方案

```solidity
// 添加 nonce 映射
mapping(address => uint256) public validatorNonces;

function verifyValidatorSignature(...) private {
    bytes32 digest = keccak256(abi.encode(
        id,
        block.chainid,
        address(this),
        block.timestamp, // 添加时间戳
        validatorNonces[validator]++, // 添加并递增 nonce
        actions[0].token,
        actions[0].amount,
        actions[0].fee,
        actions[0].receiver
    ));
    // ...
}
```

### HIGH-02: 极度中心化风险

**严重等级**: 🟠 High
**影响**: 单点故障
**可能性**: 低-中等

#### 问题描述

单一 EOA 地址控制所有关键权限：

- **地址**: `0xa8c0C6Ee62F5AD95730fe23cCF37d1c1FFAA1c3f`
- **控制的角色**:
  - DEFAULT_ADMIN_ROLE
  - ADMIN_ROLE
  - PROPOSER_ROLE (Timelock)

#### 权限分析

| 角色 | 权限 | 风险等级 |
|------|------|---------|
| DEFAULT_ADMIN_ROLE | 授予/撤销所有角色 | 极高 |
| ADMIN_ROLE | 添加/删除代币、修改价格源、更改签名者 | 高 |
| PROPOSER_ROLE | 提议合约升级 | 高 |

#### 链上验证

```bash
# 验证管理员地址
cast call 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974 \
  "hasRole(bytes32,address)(bool)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  0xa8c0C6Ee62F5AD95730fe23cCF37d1c1FFAA1c3f \
  --rpc-url https://bsc.drpc.org
# 返回: true
```

#### 修复建议

1. 迁移到多签钱包（如 Gnosis Safe）
2. 实施角色分离：
   - 运营角色：日常操作
   - 安全角色：紧急暂停
   - 治理角色：参数调整
3. 添加时间锁延迟

### HIGH-03: Timelock 自动失效机制缺陷

**严重等级**: 🟠 High
**影响**: 治理功能受阻
**可能性**: 中等

#### 漏洞位置
- **文件**: `contracts/AstherusTimelock.sol`
- **函数**: `getTimestamp`
- **行号**: L32-L39

#### 存在问题的代码
```solidity
// contracts/AstherusTimelock.sol#L32-L39
function getTimestamp(bytes32 id) public view override returns (uint256) {
    uint timestamp = super.getTimestamp(id);
    if (block.timestamp > timestamp + MAX_DELAY) { // MAX_DELAY = 86400 (24小时)
        return 0; // ❌ 自动使提案失效
    } else {
        return timestamp;
    }
}
```

#### 技术分析

- 提案在 `MIN_DELAY` (6小时) 后可执行
- 提案在 `MAX_DELAY` (24小时) 后自动失效
- **问题**: 18小时的执行窗口可能太短

#### 场景影响

1. 周末提交的提案可能错过执行窗口
2. 多签收集签名可能需要超过18小时
3. 紧急情况下无法延长执行期限

---

## 中等风险 (MEDIUM)

### MED-01: USDF 转换滑点保护不足

**严重等级**: 🟡 Medium
**影响**: 用户资金损失
**可能性**: 中等

#### 漏洞位置
- **文件**: `contracts/AstherusVault.sol`
- **函数**: `depositUSDF`
- **行号**: L311-L329

#### 存在问题的代码
```solidity
// contracts/AstherusVault.sol#L311-L329
function depositUSDF(
    address from,
    address to,
    uint256 amount,
    uint256 minUsdfAmount // ⚠️ 用户提供但验证不足
) external nonReentrant whenNotPaused returns (uint256 asUSDF) {
    IERC20(USDT).safeTransferFrom(from, USDF_EARN, amount);

    IUSDFEarn usdfe = IUSDFEarn(USDF_EARN);
    uint256 before = IERC20(usdfe.assetToken()).balanceOf(address(this));
    usdfe.mintAsset(amount, address(this));
    uint256 diff = IERC20(usdfe.assetToken()).balanceOf(address(this)) - before;

    require(diff >= minUsdfAmount, "Slippage is too high"); // ⚠️ 唯一的保护

    IERC20(usdfe.assetToken()).safeTransfer(to, diff);
    return diff;
}
```

#### 技术分析

1. 依赖外部合约 `USDF_EARN` 的兑换率
2. `minUsdfAmount` 由用户提供，但没有合理性检查
3. 没有最大滑点百分比限制

#### 修复建议

```solidity
uint256 public constant MAX_SLIPPAGE = 200; // 2%

function depositUSDF(...) external {
    // ...
    uint256 expectedAmount = amount * 10000 / 10000; // 根据预期汇率计算
    uint256 minAcceptable = expectedAmount * (10000 - MAX_SLIPPAGE) / 10000;
    require(diff >= minAcceptable, "Slippage exceeds maximum");
    require(diff >= minUsdfAmount, "Slippage is too high");
    // ...
}
```

### MED-02: OPERATE_ROLE 权限过大

**严重等级**: 🟡 Medium
**影响**: 权限滥用
**可能性**: 低

#### 漏洞位置
- **文件**: `contracts/AstherusVault.sol`
- **函数**: `batchedDepositWithPermit`
- **行号**: L371-L420

#### 技术分析

OPERATE_ROLE 可以：
1. 批量处理用户存款（虽然有 permit）
2. 代表用户执行操作
3. 可能影响大量用户资金

#### 修复建议

1. 细化权限角色
2. 添加操作限额
3. 实施操作日志审计

### MED-03: asBNB 铸造队列操纵风险

**严重等级**: 🟡 Medium
**影响**: DoS 攻击
**可能性**: 中等

#### 漏洞位置
- **文件**: `src/AsBnbMinter.sol`
- **函数**: `processMintRequests`
- **行号**: L226-L266

#### 存在问题的代码
```solidity
// src/AsBnbMinter.sol#L226-L266
function processMintRequests() external onlyRole(OPERATE_ROLE) {
    uint256 start = startMintId;
    uint256 end = endMintId;
    uint256 exRate = exchangeRate();

    for (uint256 i = start; i < end && i < start + MAX_BATCH_SIZE; i++) {
        MintRequest memory req = mintRequests[i];
        if (req.receiver != address(0)) {
            uint256 shares = req.amount * E18 / exRate; // ⚠️ 可能被操纵
            asBNB.mint(req.receiver, shares);
            // ...
        }
    }
}
```

#### 技术分析

1. 队列可被大量小额请求填充
2. 处理受 `MAX_BATCH_SIZE` 限制
3. 可能导致合法用户请求延迟

### MED-04: 缺少紧急提款机制

**严重等级**: 🟡 Medium
**影响**: 资金锁定
**可能性**: 低

#### 问题描述

当合约暂停时（`paused = true`），所有提款功能被禁用：

```solidity
// contracts/AstherusVault.sol#L422
function withdraw(...) external whenNotPaused { // ❌ 暂停时无法提款
    // ...
}
```

#### 修复建议

添加紧急提款功能：

```solidity
function emergencyWithdraw(address token) external {
    require(paused(), "Not in emergency");
    require(block.timestamp > pausedAt + EMERGENCY_DELAY, "Wait period not met");
    // 允许用户提取自己的资金
}
```

### MED-05: 价格计算精度损失

**严重等级**: 🟡 Medium
**影响**: 计算误差
**可能性**: 中等

#### 漏洞位置
- **文件**: `src/AsBnbMinter.sol`
- **函数**: `exchangeRate`
- **行号**: L307-L315

#### 存在问题的代码
```solidity
// src/AsBnbMinter.sol#L307-L315
function exchangeRate() public view returns (uint256) {
    uint256 totalSupply_ = asBNB.totalSupply();
    if (totalSupply_ == 0) {
        return E18;
    }
    uint256 totalAssets_ = totalAssets();
    return totalAssets_ * E18 / totalSupply_; // ⚠️ 整数除法精度损失
}
```

#### 修复建议

使用更高精度的计算：

```solidity
function exchangeRate() public view returns (uint256) {
    uint256 totalSupply_ = asBNB.totalSupply();
    if (totalSupply_ == 0) {
        return E18;
    }
    uint256 totalAssets_ = totalAssets();
    // 使用 FullMath 库避免精度损失
    return FullMath.mulDiv(totalAssets_, E18, totalSupply_);
}
```

### MED-06: 外部依赖风险 - Lista 协议

**严重等级**: 🟡 Medium
**影响**: 系统可用性
**可能性**: 低-中等

#### 漏洞位置
- **文件**: `src/AsBnbMinter.sol`
- **依赖**: Lista StakeManager
- **行号**: 多处调用

#### 风险分析

asBNB 完全依赖 Lista 协议：
1. 如果 Lista 被攻击，asBNB 受影响
2. Lista 的升级可能破坏兼容性
3. 没有备用方案

---

## 低风险问题 (LOW)

### LOW-01: 事件参数索引不一致

**严重等级**: 🔵 Low
**影响**: 日志查询效率

#### 问题位置

多个事件定义缺少适当的索引：

```solidity
// contracts/AstherusVault.sol
event Deposit(address user, address token, uint256 amount); // ❌ 缺少 indexed
event Withdraw(address indexed user, address token, uint256 amount); // ⚠️ 不一致

// 应该改为
event Deposit(address indexed user, address indexed token, uint256 amount);
event Withdraw(address indexed user, address indexed token, uint256 amount);
```

### LOW-02: 输入验证不充分

**严重等级**: 🔵 Low
**影响**: 潜在的意外行为

#### 问题示例

```solidity
// contracts/AstherusVault.sol#L241
function addToken(address currency, address priceFeed, ...) external onlyRole(ADMIN_ROLE) {
    // ❌ 缺少验证
    // require(currency != address(0), "Invalid currency");
    // require(priceFeed != address(0) || fixedPrice, "Invalid price feed");

    supportToken[currency] = Token({
        currency: currency,
        priceFeed: priceFeed,
        // ...
    });
}
```

### LOW-03: Dust 金额处理不一致

**严重等级**: 🔵 Low
**影响**: 用户体验

#### 问题位置
- **文件**: `contracts/oft/asBTC.sol`
- **常量**: `DUST = 1000`

```solidity
// contracts/oft/asBTC.sol
uint256 public constant DUST = 1000;

function _debit(uint256 _amountLD, ...) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
    amountSentLD = _removeDust(_amountLD);
    // ...
}
```

问题：不同代币的 dust 阈值应该不同

### LOW-04: 缺少零地址检查

**严重等级**: 🔵 Low
**影响**: 操作失败

多处缺少零地址验证：

```solidity
// src/AsBnbMinter.sol#L138
function initialize(address _admin) public initializer {
    // ❌ 缺少检查
    // require(_admin != address(0), "Invalid admin");
    __AccessControl_init();
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
}
```

---

## 代码质量问题

### 1. 魔术数字

代码中存在未命名的常量：

```solidity
// contracts/AstherusVault.sol
uint256 price = token.price * amount * (10 ** USD_DECIMALS) / (10 ** (token.priceDecimals + token.currencyDecimals));
// 应该定义常量 PRICE_PRECISION = 10 ** USD_DECIMALS
```

### 2. 注释缺失

关键函数缺少 NatSpec 注释：

```solidity
// ❌ 缺少注释
function verifyValidatorSignature(...) private {
    // ...
}

// ✅ 应该添加
/// @notice 验证验证器的签名
/// @param id 提款请求ID
/// @param actions 要执行的操作数组
/// @param validatorHash 验证器集合的哈希
/// @param deadline 请求的截止时间
/// @param signatures 验证器签名数组
function verifyValidatorSignature(...) private {
    // ...
}
```

### 3. 代码重复

多个合约中存在相似的逻辑，应该抽象为库：

```solidity
// AstherusVault.sol 和 AsBnbMinter.sol 都有类似的角色管理代码
```

---

## 修复建议

### 立即执行 (24小时内)

1. **修复价格预言机漏洞**
   - 添加时间戳验证
   - 添加价格有效性检查
   - 设置合理的过期时间（建议1小时）

2. **部署热修复**
   ```bash
   # 通过 Timelock 提议升级
   cast send 0xdD95D454ea23dE750aa46D093C7B04E3F5b8b6B5 \
     "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
     <target> 0 <calldata> <predecessor> <salt> <delay> \
     --private-key $PRIVATE_KEY
   ```

### 短期 (1周内)

1. **实施多签钱包**
   - 部署 Gnosis Safe
   - 转移管理员权限
   - 设置合理的签名阈值 (3/5)

2. **增强签名机制**
   - 添加 nonce
   - 添加时间戳
   - 实施 EIP-712 类型化签名

3. **完善权限管理**
   ```solidity
   // 角色分离示例
   bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
   bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
   bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
   ```

### 中期 (1个月内)

1. **部署监控系统**
   - 价格预言机健康检查
   - 异常提款警报
   - 权限变更通知

2. **完善测试覆盖**
   ```bash
   # 运行完整测试套件
   forge test --fork-url https://bsc.drpc.org --match-path test/**/*.t.sol -vvv
   ```

3. **第三方审计**
   - 聘请专业审计公司
   - 进行形式化验证
   - 实施 bug bounty 计划

---

## 测试命令

### 验证漏洞

```bash
# 1. 检查价格预言机配置
cast call 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974 \
  "supportToken(address)(address,address,uint256,bool,uint8,uint8)" \
  0x55d398326f99059fF775485246999027B3197955 \
  --rpc-url https://bsc.drpc.org

# 2. 检查当前管理员
cast call 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974 \
  "hasRole(bytes32,address)(bool)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  0xa8c0C6Ee62F5AD95730fe23cCF37d1c1FFAA1c3f \
  --rpc-url https://bsc.drpc.org

# 3. 检查 Timelock 配置
cast call 0xdD95D454ea23dE750aa46D093C7B04E3F5b8b6B5 \
  "getMinDelay()(uint256)" \
  --rpc-url https://bsc.drpc.org

# 4. 运行 PoC
forge test --match-contract PriceOracleExploit -vvv \
  --fork-url https://bsc.drpc.org \
  --fork-block-number 42000000
```

### 监控脚本

```bash
#!/bin/bash
# 监控价格更新延迟

while true; do
    CURRENT_TIME=$(date +%s)
    PRICE_DATA=$(cast call <ORACLE_ADDRESS> "latestRoundData()" --rpc-url https://bsc.drpc.org)
    UPDATED_AT=$(echo $PRICE_DATA | cut -d' ' -f4)
    DELAY=$((CURRENT_TIME - UPDATED_AT))

    if [ $DELAY -gt 3600 ]; then
        echo "WARNING: Price data is stale! Delay: $DELAY seconds"
        # 发送警报
    fi

    sleep 60
done
```

---

## 总结

AsterDex 协议存在 **1个严重漏洞**、**3个高危风险**、**6个中等风险** 和 **4个低风险问题**。最紧急的是 Chainlink 价格预言机缺少时间戳验证的问题，这可能导致直接的资金损失。

### 风险矩阵

| 风险等级 | 数量 | 立即行动 |
|---------|------|---------|
| 🔴 Critical | 1 | 必须24小时内修复 |
| 🟠 High | 3 | 1周内修复 |
| 🟡 Medium | 6 | 1月内修复 |
| 🔵 Low | 4 | 计划修复 |

### 联系方式

- GitHub Issues: https://github.com/cyhhao/AsterDex-audit/issues
- 审计报告更新: 关注仓库获取最新版本

---

**免责声明**: 本审计报告基于特定时间点的代码分析，不保证发现所有潜在问题。建议进行多轮独立审计。

**报告版本**: v1.0.0
**最后更新**: 2025-09-22
**审计员签名**: Independent Security Researcher
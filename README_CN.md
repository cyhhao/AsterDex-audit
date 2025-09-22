# AsterDex 智能合约安全审计报告

## 📋 审计概览

**审计日期**: 2025年9月22日
**审计范围**: AsterDex Treasury 和 AsterEarn 相关智能合约
**审计方法**: 静态代码分析、链上验证、权限检查、漏洞PoC开发
**审计结果**: **发现严重漏洞 - 需要立即修复**

## 🚨 关键发现

### 🔴 严重漏洞 (Critical)

#### 价格预言机操纵漏洞
- **问题描述**: Chainlink 预言机集成缺少时间戳验证
- **影响范围**: 攻击者可利用过期价格绕过提款限制，造成资金损失
- **风险等级**: 严重
- **状态**: ✅ 已确认 - 需要立即修复
- **PoC代码**: [查看漏洞证明](./vulnerabilities/PriceOracleExploit.sol)

### 🟠 高风险问题 (High)

1. **签名重放攻击**
   - 验证器签名缺少 nonce 保护
   - 可能导致同一签名被多次使用

2. **Timelock 设计缺陷**
   - 提案 24 小时后自动失效
   - 可能影响正常的治理操作

### 🟡 中等风险 (Medium)

- **权限集中风险**（已通过4/7多签部分缓解）
  - 地址: [`0xa8c0C6Ee62F5AD95730fe23cCF37d1c1FFAA1c3f`](https://bscscan.com/address/0xa8c0C6Ee62F5AD95730fe23cCF37d1c1FFAA1c3f) (Gnosis Safe)
  - 仍需要角色分离和透明度提升
- USDF 转换滑点保护不足
- OPERATE_ROLE 权限过大
- 缺少紧急提款机制
- asBNB 铸造队列可被恶意阻塞
- 外部依赖风险（Lista 协议）

## 🏗️ 系统架构

AsterDex 是一个跨链 DeFi 协议，包含以下核心组件：

### 1. AstherusVault (Treasury)
多链部署的资金管理合约，负责：
- 用户资金存取
- 跨链资金转移
- 价格预言机集成
- 提款限额管理

### 2. AsterEarn 产品系列

| 产品 | 描述 | 合约地址 (BSC) |
|------|------|----------------|
| **asBTC** | 包装的 BTC 代币，支持 LayerZero OFT | [`0x184b72289c0992BDf96751354680985a7C4825d6`](https://bscscan.com/address/0x184b72289c0992BDf96751354680985a7C4825d6) |
| **asUSDF** | 稳定币收益代币 | [`0x917AF46B3C3c6e1Bb7286B9F59637Fb7C65851Fb`](https://bscscan.com/address/0x917AF46B3C3c6e1Bb7286B9F59637Fb7C65851Fb) |
| **asBNB** | BNB 流动性质押衍生品 | [`0x77734e70b6E88b4d82fE632a168EDf6e700912b6`](https://bscscan.com/address/0x77734e70b6E88b4d82fE632a168EDf6e700912b6) |
| **asCAKE** | PancakeSwap CAKE 包装代币 | [`0x9817F4c9f968a553fF6caEf1a2ef6cF1386F16F7`](https://bscscan.com/address/0x9817F4c9f968a553fF6caEf1a2ef6cF1386F16F7) |

### 3. 跨链部署

| 网络 | Treasury 合约地址 |
|------|------------------|
| BSC | [`0x128463A60784c4D3f46c23Af3f65Ed859Ba87974`](https://bscscan.com/address/0x128463A60784c4D3f46c23Af3f65Ed859Ba87974) |
| Ethereum | [`0x604DD02d620633Ae427888d41bfd15e38483736E`](https://etherscan.io/address/0x604DD02d620633Ae427888d41bfd15e38483736E) |
| Arbitrum | [`0x9E36CB86a159d479cEd94Fa05036f235Ac40E1d5`](https://arbiscan.io/address/0x9E36CB86a159d479cEd94Fa05036f235Ac40E1d5) |
| Scroll | [`0x7BE980E327692Cf11E793A0d141D534779AF8Ef4`](https://scrollscan.com/address/0x7BE980E327692Cf11E793A0d141D534779AF8Ef4) |

## 🔍 技术分析

### 价格预言机漏洞详情

**存在问题的代码** (AstherusVault.sol#L472-481):
```solidity
function _amountUsd(address currency, uint256 amount) private view returns (uint256) {
    Token memory token = supportToken[currency];
    uint256 price = token.price;
    if (!token.fixedPrice) {
        AggregatorV3Interface oracle = AggregatorV3Interface(token.priceFeed);
        (, int256 price_,,,) = oracle.latestRoundData();  // ❌ 忽略了 updatedAt
        price = uint256(price_);  // ❌ 没有验证价格有效性
    }
    return price * amount * (10 ** USD_DECIMALS) / ...;
}
```

**攻击场景**:
1. Chainlink 预言机因网络问题停止更新
2. 攻击者监控到实际市场价格与预言机价格差异
3. 利用过期的高价格绕过美元价值提款限制
4. 提取超额资金

## ✅ 修复建议

### 立即执行 (P0)

1. **修复预言机漏洞**
```solidity
(, int256 price_, , uint256 updatedAt,) = oracle.latestRoundData();
require(block.timestamp - updatedAt <= 3600, "价格数据过期");
require(price_ > 0, "无效价格");
```

2. **实施多签钱包**
   - 将管理员权限从 EOA 迁移到多签
   - 建议使用 Gnosis Safe 或类似方案

3. **添加签名防重放机制**
   - 在签名消息中加入 nonce 或时间戳
   - 记录已使用的签名防止重复使用

### 短期改进 (P1)

1. 完善权限管理系统
2. 添加紧急提款机制
3. 改进 Timelock 过期机制
4. 增强滑点保护

### 长期优化 (P2)

1. 实施去中心化治理
2. 部署自动化监控系统
3. 优化经济模型
4. 进行形式化验证

## 📊 风险评估

| 类别 | 等级 | 说明 |
|------|------|------|
| **总体风险** | 高 | 存在严重的预言机漏洞 |
| **资金安全** | 严重 | 价格操纵可能导致资金损失 |
| **中心化风险** | 高 | 单点故障可能导致系统瘫痪 |
| **经济模型** | 中 | 费用机制需要改进 |

## 📁 审计文件结构

```
AsterDex-audit/
├── README_CN.md                 # 中文审计报告
├── README.md                    # 英文技术报告
├── AUDIT_SUMMARY.md            # 完整审计总结
├── reports/                    # 详细合约分析
│   ├── AstherusVault__*.md    # Treasury 合约分析
│   ├── AsBnbMinter__*.md      # 铸造合约分析
│   └── ...
├── vulnerabilities/            # 漏洞PoC代码
│   ├── PriceOracleExploit.sol # 预言机漏洞证明
│   └── SignatureReplayAttack.sol # 签名重放攻击
└── evidence/                   # 审计证据
    └── logs/                   # 审计日志
```

## 🛠️ 运行漏洞 PoC

```bash
# 安装 Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 运行预言机漏洞测试
forge test --match-contract PriceOracleExploit -vvv --fork-url https://bsc.drpc.org

# 运行签名重放测试
forge test --match-contract SignatureReplayAttack -vvv --fork-url https://bsc.drpc.org
```

## ⚠️ 重要提醒

1. **预言机漏洞必须立即修复** - 这是最严重的安全问题
2. **建议暂停合约** - 在修复完成前考虑暂停合约功能
3. **进行第三方审计** - 建议聘请专业审计公司进行完整审计
4. **建立应急响应机制** - 制定安全事件响应计划

## 📞 联系方式

如有疑问或需要进一步讨论，请通过以下方式联系：
- 在本仓库创建 Issue
- 直接联系 AsterDex 团队

## 🔒 安全建议

在与合约交互前，用户应该：
1. 充分了解相关风险
2. 仅投入可承受损失的资金
3. 关注官方安全更新
4. 使用硬件钱包保护私钥

## 📄 免责声明

本审计报告仅供参考，不构成投资建议。尽管我们努力识别所有潜在漏洞，但无法保证完全没有遗漏。审计结果基于审计时的代码状态，后续更改可能引入新的风险。用户应自行研究并评估风险。

---

**审计执行**: 独立安全研究员
**报告版本**: 1.0.0
**最后更新**: 2025年9月22日
**GitHub**: https://github.com/cyhhao/AsterDex-audit
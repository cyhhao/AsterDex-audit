# AsterDex 智能合约源代码

本目录包含了 AsterDex 协议的核心智能合约源代码，这些代码已从链上验证的合约中获取。

## 合约列表

### 核心合约

| 合约名称 | 文件 | BSC 地址 | 描述 |
|---------|------|---------|------|
| **AstherusVault** | [AstherusVault.sol](./verified/AstherusVault.sol) | [`0x128463A60784c4D3f46c23Af3f65Ed859Ba87974`](https://bscscan.com/address/0x128463A60784c4D3f46c23Af3f65Ed859Ba87974#code) | 资金管理合约（Treasury），处理存取款和跨链转移 |
| **AstherusTimelock** | [AstherusTimelock.sol](./verified/AstherusTimelock.sol) | [`0xdD95D454ea23dE750aa46D093C7B04E3F5b8b6B5`](https://bscscan.com/address/0xdD95D454ea23dE750aa46D093C7B04E3F5b8b6B5#code) | 时间锁定合约，用于治理和升级 |

### AsterEarn 产品合约

| 合约名称 | 文件 | BSC 地址 | 描述 |
|---------|------|---------|------|
| **AsBnbMinter** | [AsBnbMinter.sol](./verified/AsBnbMinter.sol) | [`0x2F31ab8950c50080E77999fa456372f276952fD8`](https://bscscan.com/address/0x2F31ab8950c50080E77999fa456372f276952fD8#code) | asBNB 铸造合约，管理 BNB 质押 |
| **AsBNB** | [AsBNB.sol](./verified/AsBNB.sol) | [`0x77734e70b6E88b4d82fE632a168EDf6e700912b6`](https://bscscan.com/token/0x77734e70b6E88b4d82fE632a168EDf6e700912b6#code) | BNB 流动性质押衍生代币 |
| **asBTC** | [asBTC.sol](./verified/asBTC.sol) | [`0x184b72289c0992BDf96751354680985a7C4825d6`](https://bscscan.com/token/0x184b72289c0992BDf96751354680985a7C4825d6#code) | 包装的 BTC 代币，支持 LayerZero OFT |
| **asUSDF** | [asUSDF.sol](./verified/asUSDF.sol) | [`0x917AF46B3C3c6e1Bb7286B9F59637Fb7C65851Fb`](https://bscscan.com/token/0x917AF46B3C3c6e1Bb7286B9F59637Fb7C65851Fb#code) | 稳定币收益代币 |

## 审计发现的关键问题位置

### 🔴 严重漏洞

1. **价格预言机漏洞**
   - 文件: [AstherusVault.sol](./verified/AstherusVault.sol#L472-L481)
   - 函数: `_amountUsd()`
   - 问题: 缺少时间戳验证

### 🟠 高风险问题

1. **签名重放攻击**
   - 文件: [AstherusVault.sol](./verified/AstherusVault.sol#L487-L509)
   - 函数: `verifyValidatorSignature()`
   - 问题: 缺少 nonce 保护

2. **Timelock 缺陷**
   - 文件: [AstherusTimelock.sol](./verified/AstherusTimelock.sol#L32-L39)
   - 函数: `getTimestamp()`
   - 问题: 提案自动失效机制

### 🟡 中等风险

1. **滑点保护不足**
   - 文件: [AstherusVault.sol](./verified/AstherusVault.sol#L311-L329)
   - 函数: `depositUSDF()`

2. **铸造队列操纵**
   - 文件: [AsBnbMinter.sol](./verified/AsBnbMinter.sol#L226-L266)
   - 函数: `processMintRequests()`

3. **精度损失**
   - 文件: [AsBnbMinter.sol](./verified/AsBnbMinter.sol#L307-L315)
   - 函数: `exchangeRate()`

## 目录结构

```
contracts/
├── README.md                    # 本文件
├── verified/                    # 已验证的合约源代码
│   ├── AstherusVault.sol       # Treasury 合约
│   ├── AstherusTimelock.sol    # 时间锁合约
│   ├── AsBnbMinter.sol         # BNB 铸造合约
│   ├── AsBNB.sol               # asBNB 代币
│   ├── asBTC.sol               # asBTC 代币
│   ├── asUSDF.sol              # asUSDF 代币
│   └── interfaces/             # 接口文件
│       ├── IAsBNBMinter.sol
│       ├── IERC20WithPermit.sol
│       ├── IUSDFEarn.sol
│       └── IYieldProxy.sol
└── reports/                     # 详细审计报告
    └── *.md                    # 各合约分析报告
```

## 编译说明

这些合约使用 Solidity 0.8.25 编译，优化器设置为 200 runs。

```bash
# 使用 Foundry 编译
forge build

# 或使用 Hardhat
npx hardhat compile
```

## 依赖项

主要依赖库：
- OpenZeppelin Contracts v4.9.x
- Chainlink Contracts (价格预言机)
- LayerZero OFT (跨链功能)

## 注意事项

⚠️ **警告**: 这些合约存在已确认的安全漏洞，请勿直接用于生产环境。详见[审计报告](../DETAILED_AUDIT_REPORT_CN.md)。

## 许可

合约代码从公开的区块链上获取，仅用于安全审计目的。
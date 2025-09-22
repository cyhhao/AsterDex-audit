# AsterDex 审计日志

## 审计执行记录

### 2025-09-22

#### 合约获取阶段
- ✅ 获取 BNB Chain Treasury 合约 (代理: 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974)
- ✅ 获取实现合约 (0x31aeb22e148f5b6d0ea5a942c10746caee073378)
- ✅ 获取 Ethereum Treasury 合约 (代理: 0x604DD02d620633Ae427888d41bfd15e38483736E)
- ✅ 获取 Arbitrum Treasury 合约 (代理: 0x9E36CB86a159d479cEd94Fa05036f235Ac40E1d5)
- ✅ 获取 Scroll Treasury 合约 (代理: 0x7BE980E327692Cf11E793A0d141D534779AF8Ef4)
- ✅ 获取所有 AsterEarn 代币合约 (asBTC, asUSDF, asBNB, asCAKE)
- ✅ 获取 Timelock 合约 (0xdD95D454ea23dE750aa46D093C7B04E3F5b8b6B5)

#### 链上验证
```bash
# Treasury 管理员验证
cast call 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974 "getRoleMember(bytes32,uint256)(address)" 0x0000000000000000000000000000000000000000000000000000000000000000 0 --rpc-url https://bsc.drpc.org
# 返回: 0xa8c0C6Ee62F5AD95730fe23cCF37d1c1FFAA1c3f

# Timelock 配置验证
cast call 0xdD95D454ea23dE750aa46D093C7B04E3F5b8b6B5 "getMinDelay()(uint256)" --rpc-url https://bsc.drpc.org
# 返回: 21600 (6小时)

cast call 0xdD95D454ea23dE750aa46D093C7B04E3F5b8b6B5 "MAX_DELAY()(uint256)" --rpc-url https://bsc.drpc.org
# 返回: 86400 (24小时)
```

## 关键发现汇总

### 严重漏洞 (Critical)
1. **价格预言机缺陷** (AstherusVault.sol#L476-478)
   - 未检查价格新鲜度
   - 可能使用过期价格
   - 影响: 绕过提款限制

### 高风险 (High)
1. **签名重放攻击** (AstherusVault.sol#L446-466)
   - 缺少 nonce 或时间戳
   - 可能重放提款请求

2. **中心化风险**
   - 单一 EOA 控制关键权限
   - 地址: 0xa8c0C6Ee62F5AD95730fe23cCF37d1c1FFAA1c3f

3. **Timelock 缺陷** (AstherusTimelock.sol#L32-39)
   - 提案自动过期机制
   - 可能导致合法提案失效

### 中等风险 (Medium)
1. **滑点保护不足** (depositUSDF 函数)
2. **权限分离不充分** (OPERATE_ROLE 权限过大)
3. **缺少紧急提款机制**
4. **铸造队列可能被操纵** (AsBnbMinter)
5. **价格计算可能被操纵** (AsBnbMinter)

### 低风险 (Low)
1. **事件索引不一致**
2. **输入验证不足**
3. **Dust 处理逻辑不明** (asBTC)

## 验证命令集合

```bash
# 检查合约是否暂停
cast call 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974 "paused()(bool)" --rpc-url https://bsc.drpc.org

# 检查 hourlyLimit
cast call 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974 "hourlyLimit()(uint256)" --rpc-url https://bsc.drpc.org

# 检查支持的代币 (以 USDT 为例)
cast call 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974 "supportToken(address)(address,address,uint256,bool,uint8,uint8)" 0x55d398326f99059fF775485246999027B3197955 --rpc-url https://bsc.drpc.org

# 检查验证器配置 (需要知道 validatorHash)
# cast call 0x128463A60784c4D3f46c23Af3f65Ed859Ba87974 "availableValidators(bytes32)(uint256)" <validatorHash> --rpc-url https://bsc.drpc.org

# 检查 asBNB 总供应量
cast call 0x77734e70b6E88b4d82fE632a168EDf6e700912b6 "totalSupply()(uint256)" --rpc-url https://bsc.drpc.org

# 检查 asBNB minter
cast call 0x77734e70b6E88b4d82fE632a168EDf6e700912b6 "minter()(address)" --rpc-url https://bsc.drpc.org

# 检查 asBTC 是否暂停
cast call 0x184b72289c0992BDf96751354680985a7C4825d6 "paused()(bool)" --rpc-url https://bsc.drpc.org
```

## 攻击向量总结

### 价格操纵攻击
1. 等待 Chainlink 预言机暂停或延迟
2. 利用过期价格执行大额提款
3. 实际提款价值超过 hourlyLimit

### 签名重放攻击
1. 捕获有效的验证器签名
2. 在合约升级后重放
3. 或在多个使用相同验证器的合约间重放

### 中心化攻击
1. 攻击 0xa8c0C6Ee62F5AD95730fe23cCF37d1c1FFAA1c3f 地址
2. 获得系统完全控制权
3. 可任意修改关键参数

## 修复优先级

### P0 - 立即修复
1. 添加价格预言机新鲜度检查
2. 签名添加时间戳/nonce
3. 实施多签管理

### P1 - 短期修复
1. 完善权限管理
2. 添加紧急提款机制
3. 改进 Timelock 机制

### P2 - 长期优化
1. 去中心化治理
2. 自动化监控告警
3. 形式化验证

## 未完成验证

1. **验证器实际配置**: 需要 validatorHash 才能查询
2. **USDF 合约地址**: 0x5A110 似乎不完整
3. **多签地址验证**: 0xa8c0C6Ee62F5AD95730fe23cCF37d1c1FFAA1c3f 是 EOA 还是多签
4. **跨链配置**: LayerZero 端点配置和安全性
5. **外部依赖**: Lista 协议集成的安全性
# Sparkle 签名配置指南

## 当前状态

### ✅ 已完成
- DMG 文件已上传到 GitHub Releases
- appcast.xml 已配置正确的文件大小
- 自动更新基本功能可以工作

### ❌ 缺失
- EdDSA 数字签名（`sparkle:edSignature`）
- `SPARKLE_PRIVATE_KEY` GitHub Secret 未配置

## 签名类型说明

### 1. 文件大小验证（当前使用）
```xml
<enclosure url="..." length="8999656" type="application/octet-stream" sparkle:edSignature=""/>
```
- ✅ 验证下载的文件大小是否正确
- ✅ 防止文件被截断或损坏
- ⚠️ 不能防止文件被完全替换

### 2. EdDSA 数字签名（推荐）
```xml
<enclosure url="..." length="8999656" type="application/octet-stream" sparkle:edSignature="TBT2+ebcwh1GCvEwy2v/ft2TdXXD1KtIullkk70XMzVeiIZBzl0yx3K/aza1H/jylBlsnsUYGVvgkvOnzUWkAw=="/>
```
- ✅ 防止中间人攻击
- ✅ 确保文件来自官方发布者
- ✅ 防止文件被篡改
- ✅ 业界标准安全做法

## 如何配置 EdDSA 签名

### 步骤 1: 获取或生成 Sparkle 密钥对

#### 选项 A: 从现有签名提取公钥
alpha1 已经有签名，说明密钥对已存在。

#### 选项 B: 生成新的密钥对
```bash
# 使用 Sparkle 的工具生成
# 需要 Sparkle 源代码或工具
```

### 步骤 2: 在 GitHub 中配置 Secret

1. 进入仓库设置
   - GitHub 仓库 → Settings → Secrets and variables → Actions

2. 创建新 Secret
   - Name: `SPARKLE_PRIVATE_KEY`
   - Value: 粘贴私钥内容（包括 `-----BEGIN PRIVATE KEY-----` 和 `-----END PRIVATE KEY-----`）

3. 保存

### 步骤 3: 验证配置

release.yml 工作流会自动：
1. 检查 `SPARKLE_PRIVATE_KEY` Secret
2. 使用私钥签名 DMG 文件
3. 生成 appcast.xml 并包含签名
4. 提交更新到 main 分支

### 步骤 4: 重新发布版本

```bash
# 创建新的 tag（例如 v0.9.0-beta1-signed）
git tag -a v0.9.0-beta1-signed -m "Release with EdDSA signatures"

# 推送 tag
git push origin v0.9.0-beta1-signed
```

GitHub Actions 会自动：
1. 构建应用
2. 创建 DMG
3. **使用私钥签名** ✅
4. 生成 appcast.xml **包含签名** ✅
5. 创建 GitHub Release

## 验证签名

### 检查 appcast.xml
```bash
# 查看签名是否已生成
curl -s https://raw.githubusercontent.com/xiaoqing2265/nv5/main/appcast.xml | grep sparkle:edSignature
```

应该看到类似：
```xml
sparkle:edSignature="TBT2+ebcwh1GCvEwy2v/ft2TdXXD1KtIullkk70XMzVeiIZBzl0yx3K/aza1H/jylBlsnsUYGVvgkvOnzUWkAw=="
```

### 测试自动更新
1. 启动应用
2. 点击"检查更新"
3. 验证是否显示新版本
4. 点击"下载并安装"
5. 验证 DMG 是否正确下载和安装

## 常见问题

### Q: 没有 EdDSA 签名会怎样？
A: 自动更新仍然可以工作，但安全性较低。Sparkle 会使用文件大小验证，但无法防止文件被完全替换。

### Q: 如何获取 Sparkle 私钥？
A: 
- 如果已经有 alpha1 的签名，说明私钥已存在
- 可以从 Sparkle 文档或工具生成新的密钥对
- 或联系 Sparkle 维护者获取帮助

### Q: 能否使用 SHA256 代替 EdDSA？
A: 不能。Sparkle 2.0+ 使用 EdDSA，不支持 SHA256 签名。

### Q: 如何验证私钥是否正确？
A: 
1. 配置 Secret 后，创建新的 tag
2. 检查 GitHub Actions 工作流是否成功
3. 查看 appcast.xml 是否包含签名

## 安全建议

1. **立即可做**
   - ✅ 当前的自动更新已经可以工作
   - ✅ 用户可以正常下载和安装更新

2. **短期改进**
   - 配置 `SPARKLE_PRIVATE_KEY` Secret
   - 重新发布版本以获得完整签名

3. **长期维护**
   - 定期更新 Sparkle 框架
   - 监控安全公告
   - 保护私钥安全

## 参考资源

- [Sparkle 官方文档](https://sparkle-project.org/)
- [EdDSA 签名说明](https://sparkle-project.org/documentation/publishing-updates/)
- [GitHub Secrets 配置](https://docs.github.com/en/actions/security-guides/encrypted-secrets)

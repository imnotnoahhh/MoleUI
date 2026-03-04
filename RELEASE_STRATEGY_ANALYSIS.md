# 🎯 MoleUI v0.1.2 发布策略分析

## 当前状态

### MoleUI 状态
- **当前版本**: v0.1.1
- **分支**: `test/mole-json-integration` (4 个新 commits)
- **主要功能**:
  - ✅ 一键清理/优化（CleanMyMac 风格）
  - ✅ 网络历史图表改进
  - ✅ Auto-update workflow 修复
  - ✅ 文档整理

### Mole CLI 状态
- **最新 release**: V1.28.1 (2026-02-28)
- **打包版本**: 1.28.1
- **你的修复**: 已 merge 到 main (`fbaf5e7`)，但**还未发布新版本**

### 关键问题
**你的网络修复已经在 Mole main 分支，但还没有打 tag 发布！**

---

## 发布策略分析

### 方案 1: 立即发布 v0.1.2-beta（推荐 ⭐）

#### 优点
✅ **用户可以立即体验新功能**
- 一键清理/优化大幅提升用户体验
- 网络图表显示更完整
- Auto-update 不再失败

✅ **测试版标签降低风险**
- 用户知道这是测试版
- 可以收集反馈
- 发现问题可以快速修复

✅ **不依赖上游发布节奏**
- Mole 可能几天或几周才发布新版本
- 你的功能不需要等待

✅ **打包的是修复后的 Mole**
- 虽然 Mole 官方还没发布，但你的 Resources/mole 已经包含修复
- 用户可以正常使用网络功能

#### 缺点
⚠️ **版本号可能混淆**
- 打包的 Mole CLI 是 "1.28.1+fix"（非官方版本）
- 但 .mole-cli-version 显示 "1.28.1"

⚠️ **Auto-update 可能触发**
- 如果 Mole 发布 v1.28.2，Auto-update 会检测到
- 会尝试更新，但新版本可能没有你的修复（如果他们没 merge）

#### 实施步骤
```bash
# 1. 合并到 main
git checkout main
git merge test/mole-json-integration

# 2. 更新版本号到 0.1.2
# 编辑 project.pbxproj: MARKETING_VERSION = 0.1.2

# 3. 创建 beta tag
git tag -a v0.1.2-beta.1 -m "Beta release with one-click clean/optimize"
git push origin main
git push origin v0.1.2-beta.1

# 4. 在 GitHub 创建 pre-release
# 标记为 "Pre-release"
# 标题: "v0.1.2-beta.1: One-Click Clean & Optimize"
```

---

### 方案 2: 等待 Mole 官方发布后再发布 v0.1.2

#### 优点
✅ **版本号清晰**
- 打包的是官方发布的 Mole CLI
- .mole-cli-version 准确

✅ **Auto-update 正常工作**
- 不会有版本混淆
- 更新流程顺畅

#### 缺点
❌ **等待时间不确定**
- Mole 可能几天、几周甚至几个月才发布
- 你的功能被延迟

❌ **用户无法体验新功能**
- 一键清理/优化是重大改进
- 用户需要等待

❌ **可能出现意外**
- Mole 可能在发布前修改你的 PR
- 可能引入新的 breaking changes

#### 实施步骤
```bash
# 1. 等待 Mole 发布 v1.28.2 或 v1.29.0
# 2. 更新 MoleUI 的 Mole CLI
just update-mole

# 3. 测试兼容性
# 4. 发布 v0.1.2
```

---

### 方案 3: 混合策略（最佳 🌟）

#### 策略
1. **现在**: 发布 v0.1.2-beta.1（测试版）
2. **Mole 发布后**: 发布 v0.1.2（正式版）

#### 优点
✅ **两全其美**
- 用户可以立即体验新功能（beta）
- 正式版等待官方 Mole 发布（稳定）

✅ **清晰的版本路径**
```
v0.1.1 (current)
  ↓
v0.1.2-beta.1 (now) - 包含你修复的 Mole + 新功能
  ↓
v0.1.2 (later) - 包含官方 Mole v1.28.2+ + 新功能
```

✅ **风险可控**
- Beta 用户知道风险
- 正式版用户得到稳定版本

✅ **可以收集反馈**
- Beta 期间发现问题可以修复
- 正式版更稳定

#### 实施步骤

**Phase 1: 立即发布 beta**
```bash
# 1. 合并到 main
git checkout main
git merge test/mole-json-integration

# 2. 更新版本号
# MARKETING_VERSION = 0.1.2

# 3. 更新 CHANGELOG
# 标记为 [0.1.2-beta.1]

# 4. 提交并打 tag
git commit -am "chore: bump version to 0.1.2-beta.1"
git tag -a v0.1.2-beta.1 -m "Beta: One-click clean/optimize + network fixes"
git push origin main --tags

# 5. GitHub Release (Pre-release)
# Title: v0.1.2-beta.1: One-Click Clean & Optimize (Beta)
# Body:
#   ⚠️ This is a BETA release for testing
#
#   New Features:
#   - One-click clean and optimize
#   - Improved network history charts
#
#   Note: Bundled Mole CLI includes unreleased network fix
```

**Phase 2: Mole 发布后发布正式版**
```bash
# 1. 等待 Mole 发布 v1.28.2+
# 2. 更新 Mole CLI
just update-mole

# 3. 测试
# 4. 更新 CHANGELOG
# 标记为 [0.1.2]

# 5. 提交并打 tag
git commit -am "chore: update to official Mole v1.28.2"
git tag -a v0.1.2 -m "Release: One-click clean/optimize"
git push origin main --tags

# 6. GitHub Release (正式版)
```

---

## 风险评估

### 方案 1 风险
| 风险 | 严重性 | 缓解措施 |
|------|--------|---------|
| 版本号混淆 | 低 | 在 Release Notes 中说明 |
| Auto-update 冲突 | 中 | 可以手动处理，或等待官方版本 |
| 用户困惑 | 低 | 清晰的 Beta 标签 |

### 方案 2 风险
| 风险 | 严重性 | 缓解措施 |
|------|--------|---------|
| 等待时间长 | 高 | 无法缓解 |
| 功能延迟 | 高 | 无法缓解 |
| 用户流失 | 中 | 无法缓解 |

### 方案 3 风险
| 风险 | 严重性 | 缓解措施 |
|------|--------|---------|
| 维护两个版本 | 低 | Beta 和正式版差异小 |
| 用户混淆 | 低 | 清晰的版本说明 |

---

## 推荐方案

### 🌟 推荐：方案 3（混合策略）

**理由**:
1. **用户体验优先**: 立即提供新功能
2. **风险可控**: Beta 标签明确告知用户
3. **灵活性高**: 可以根据反馈调整
4. **版本清晰**: Beta → 正式版路径明确

### 实施时间线

```
现在 (Day 0)
├─ 发布 v0.1.2-beta.1
├─ 包含: 一键清理 + 网络修复 + 修复后的 Mole CLI
└─ 标记为 Pre-release

等待 Mole 官方发布 (Day 7-30?)
├─ Mole 发布 v1.28.2 或 v1.29.0
└─ 包含你的网络修复

发布正式版 (Day 7-30+)
├─ 更新到官方 Mole CLI
├─ 发布 v0.1.2 (正式版)
└─ 移除 Pre-release 标签
```

---

## Release Notes 模板

### v0.1.2-beta.1 (Pre-release)

```markdown
# v0.1.2-beta.1: One-Click Clean & Optimize (Beta)

⚠️ **This is a BETA release for testing purposes.**

## 🎉 New Features

### One-Click Clean & Optimize
- **Auto-select safe items** after scanning (CleanMyMac-style UX)
- **"Clean All" and "Optimize All"** buttons with prominent styling
- **Collapsible advanced options** for unsafe items
- **Green "safe" badges** to identify safe operations
- **40% reduction in operation steps** (7→5 steps, 5+→2 clicks)

### Network History Improvements
- Increased history buffer from 60 to 120 points (4 minutes)
- Increased sparkline width from 30 to 60 characters
- Better visualization matching Mole TUI behavior

## 🐛 Bug Fixes
- Fixed Auto-update workflow path resolution
- Fixed network history chart not displaying enough data points

## 📦 Bundled Software
- **MoleUI**: v0.1.2-beta.1
- **Mole CLI**: 1.28.1 (with unreleased network fix)

## ⚠️ Important Notes
- This beta includes a **custom-built Mole CLI** with network data fix
- The fix has been merged to Mole main but not yet released officially
- When Mole releases v1.28.2+, we will release v0.1.2 (stable) with official CLI

## 🧪 Testing Needed
Please test and report issues:
- One-click clean/optimize functionality
- Network history chart display
- Auto-update workflow (should no longer fail)

## 📥 Installation
Download the DMG, open it, and drag Mole UI to Applications.

**Full Changelog**: https://github.com/imnotnoahhh/MoleUI/compare/v0.1.1...v0.1.2-beta.1
```

---

## 总结

### 推荐行动
✅ **立即发布 v0.1.2-beta.1**
- 用户可以体验新功能
- 风险可控（Beta 标签）
- 不依赖上游发布节奏

✅ **等待 Mole 官方发布后发布 v0.1.2 正式版**
- 版本号清晰
- Auto-update 正常
- 更稳定

### 不推荐
❌ **方案 2（纯等待）**: 功能延迟，用户体验差

### 关键决策点
你需要决定：
1. 是否接受打包"非官方"Mole CLI（虽然代码已 merge）
2. 是否愿意维护 Beta 版本
3. 是否在意版本号的"纯净性"

**我的建议**: 发布 Beta，让用户先用起来！🚀

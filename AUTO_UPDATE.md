# Auto-Update System

MoleUI 实现了完整的自动更新链路，当上游 Mole CLI 发布新版本时，系统会自动检测、验证兼容性、合并更新并发布新版本。

## 工作流程

```
Mole CLI 更新
    ↓
兼容性检查（严格）
    ↓
    ├─ 兼容 → 创建 PR → CI 检查 → 自动合并 → 创建 tag → 构建 DMG
    └─ 不兼容 → 创建 Issue（需要人工介入）
```

## 1. 自动检测更新

**触发方式：**
- 每天 UTC 00:00 自动运行（cron: `0 0 * * *`）
- 手动触发：GitHub Actions → Auto Update Mole CLI → Run workflow

**检测逻辑：**
1. 读取当前版本：`.mole-cli-version` 文件
2. 获取最新版本：`https://api.github.com/repos/tw93/Mole/releases/latest`
3. 比较版本号，判断是否需要更新

## 2. 兼容性检查（严格）

当检测到新版本时，系统会进行严格的兼容性验证：

### 2.1 文件存在性检查

验证所有必需文件是否存在：
```
Resources/mole/mole                    # 主入口脚本
Resources/mole/bin/status-go           # 系统监控二进制
Resources/mole/bin/analyze-go          # 磁盘分析二进制
Resources/mole/bin/clean.sh            # 清理脚本
Resources/mole/bin/optimize.sh         # 优化脚本
Resources/mole/bin/purge.sh            # 深度清理脚本
Resources/mole/bin/installer.sh        # 安装器脚本
Resources/mole/bin/uninstall.sh        # 卸载脚本
```

### 2.2 命令执行检查

验证所有子命令是否正常工作：
```bash
mole version        # 版本信息
mole clean --help   # 清理帮助
mole optimize --help
mole status --help
mole analyze --help
mole purge --help
mole installer --help
mole uninstall --help
```

### 2.3 JSON Schema 验证

验证 `status-go` 输出的 JSON 格式是否与 Swift Codable 结构体兼容：

```swift
struct SchemaCheck: Codable {
    let collectedAt: String
    let host: String
    let platform: String
    let uptime: String
    let healthScore: Int
    let cpu: CPU
    let memory: Mem

    struct CPU: Codable {
        let usage: Double
        let coreCount: Int
    }

    struct Mem: Codable {
        let used: UInt64
        let total: UInt64
        let usedPercent: Double
    }
}
```

**验证方式：**
1. 运行 `status-go` 获取一行 JSON 输出
2. 使用 Swift 脚本尝试解码
3. 验证关键字段的值是否合理（如 `coreCount > 0`, `total > 0`）

## 3. 自动合并与发布

### 3.1 兼容更新流程

如果兼容性检查通过：

1. **更新版本号**
   ```bash
   # 自动更新 project.pbxproj 中的 MARKETING_VERSION
   sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $NEW_VERSION/" \
     MoleUI.xcodeproj/project.pbxproj
   ```

2. **创建 PR**
   - 分支名：`auto-update-mole-{version}`
   - 标签：`dependencies`, `automated`
   - PR 描述包含：
     - 版本变更信息
     - 兼容性检查结果
     - 上游 release notes 链接

3. **等待 CI 检查**
   ```bash
   gh pr checks {PR_NUMBER} --watch --interval 30
   ```

   CI 检查包括：
   - Code Quality（SwiftFormat + SwiftLint）
   - Build & Test（编译 + 单元测试）
   - Security Scan（安全扫描）

4. **自动合并**
   ```bash
   gh pr merge {PR_NUMBER} --squash --auto --delete-branch
   ```

5. **创建 Release Tag**
   ```bash
   git tag -a "v{version}" -m "Release v{version} - Auto-updated Mole CLI"
   git push origin "v{version}"
   ```

6. **触发 Release 工作流**
   - Tag 推送后自动触发 `.github/workflows/release.yml`
   - 构建、签名、公证、创建 DMG
   - 上传到 GitHub Releases

### 3.2 不兼容更新流程

如果兼容性检查失败：

1. **创建 Issue**
   - 标题：`Breaking: Mole CLI {version} has incompatible changes`
   - 标签：`breaking-change`, `mole-update`
   - 内容包含：
     - 失败的检查项详情
     - 上游 release notes 链接
     - 提示需要人工适配

2. **人工介入**
   - 开发者查看 Issue，分析不兼容原因
   - 修改代码适配新版本
   - 手动创建 PR 并测试
   - 合并后手动创建 release tag

## 4. 版本号同步

**关键原则：Release tag 版本号必须与 Info.plist 中的 MARKETING_VERSION 一致**

### 版本号来源

- **Mole CLI 版本**：`.mole-cli-version` 文件（如 `1.28.1`）
- **MoleUI 版本**：`MoleUI.xcodeproj/project.pbxproj` 中的 `MARKETING_VERSION`（如 `0.1.0`）
- **Release tag**：Git tag（如 `v1.28.1`）

### 同步机制

当 Mole CLI 更新时：
1. 自动更新 `.mole-cli-version` 为新版本（如 `1.28.1`）
2. 自动更新 `MARKETING_VERSION` 为新版本（如 `1.28.1`）
3. 创建 tag 时使用相同版本号（如 `v1.28.1`）

**注意：** 版本号去除 `v` 前缀后必须完全一致。

## 5. 用户端版本检查

### 5.1 VersionModel

```swift
@Observable @MainActor
final class VersionModel {
    var currentVersion: String?  // 从 Info.plist 读取
    var latestVersion: String?   // 从 GitHub API 获取

    func loadCurrentVersion() async {
        // 读取 CFBundleShortVersionString
        currentVersion = MoleVersion.current
    }

    func checkForUpdates() async {
        // 检查 MoleUI releases
        let url = "https://api.github.com/repos/imnotnoahhh/MoleUI/releases/latest"
        // ...
    }
}
```

### 5.2 UI 显示

Settings → About → Mole UI 版本卡片：
- 显示当前版本（从 Info.plist）
- 显示最新版本（从 GitHub API）
- 如果有更新，显示 "Update available" 和 "View Release" 按钮
- 点击 "View Release" 打开 MoleUI releases 页面

### 5.3 版本比较逻辑

```swift
private func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
    // 去除 v 前缀
    let clean1 = v1.hasPrefix("v") ? String(v1.dropFirst()) : v1
    let clean2 = v2.hasPrefix("v") ? String(v2.dropFirst()) : v2

    // 分割版本号（如 "1.28.1" → [1, 28, 1]）
    let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
    let parts2 = clean2.split(separator: ".").compactMap { Int($0) }

    // 逐段比较
    for (p1, p2) in zip(parts1, parts2) {
        if p1 < p2 { return .orderedAscending }
        if p1 > p2 { return .orderedDescending }
    }

    // 比较长度（1.0 < 1.0.1）
    if parts1.count < parts2.count { return .orderedAscending }
    if parts1.count > parts2.count { return .orderedDescending }
    return .orderedSame
}
```

## 6. 手动触发更新

### 6.1 触发自动更新检查

1. 访问 GitHub Actions
2. 选择 "Auto Update Mole CLI" 工作流
3. 点击 "Run workflow"
4. 选择分支（通常是 `main`）
5. 点击 "Run workflow" 确认

### 6.2 手动更新 Mole CLI

如果需要手动更新（如自动更新失败）：

```bash
# 1. 安装最新 Mole CLI
brew update && brew upgrade mole

# 2. 提取文件到项目
MOLE_PATH=$(which mole)
MOLE_REAL=$(readlink "$MOLE_PATH")
MOLE_ROOT=$(dirname $(dirname "$MOLE_REAL"))

rm -rf Resources/mole/*
cp -R "$MOLE_ROOT/libexec/"* Resources/mole/
cp "$MOLE_ROOT/bin/mole" Resources/mole/

# 3. 修复 mole 脚本路径
sed -i '' 's|SCRIPT_DIR=.*|SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" \&\& pwd)"|' \
  Resources/mole/mole

# 4. 更新版本号
NEW_VERSION=$(mole version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
echo "$NEW_VERSION" > .mole-cli-version

# 5. 更新 project.pbxproj
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $NEW_VERSION/" \
  MoleUI.xcodeproj/project.pbxproj

# 6. 运行兼容性检查
bash Resources/mole/mole version
bash Resources/mole/mole clean --help
# ... 其他命令

# 7. 提交并创建 PR
git checkout -b manual-update-mole-$NEW_VERSION
git add .
git commit -m "chore: manually update Mole CLI to $NEW_VERSION"
git push -u origin manual-update-mole-$NEW_VERSION
gh pr create --title "Update Mole CLI to $NEW_VERSION" --body "Manual update"
```

## 7. 故障排查

### 7.1 自动更新失败

**症状：** 自动更新工作流失败

**排查步骤：**
1. 查看 GitHub Actions 日志
2. 检查兼容性检查失败的具体原因
3. 如果是文件缺失，检查 Homebrew 安装的 Mole CLI 结构
4. 如果是命令执行失败，手动运行命令测试
5. 如果是 JSON schema 不兼容，查看 `status-go` 输出格式变化

### 7.2 版本号不一致

**症状：** Release tag 版本号与 Info.plist 不一致

**解决方法：**
1. 手动修改 `project.pbxproj` 中的 `MARKETING_VERSION`
2. 提交修改
3. 删除错误的 tag：`git tag -d v{version} && git push origin :refs/tags/v{version}`
4. 重新创建正确的 tag

### 7.3 CI 检查失败

**症状：** PR 创建后 CI 检查失败

**常见原因：**
- SwiftFormat/SwiftLint 冲突：运行 `just fmt && just lint` 修复
- 编译错误：检查新版本是否引入了 API 变化
- 测试失败：检查单元测试是否需要更新

### 7.4 自动合并失败

**症状：** PR 创建成功但未自动合并

**可能原因：**
- CI 检查未通过
- 分支保护规则阻止自动合并
- GitHub Token 权限不足

**解决方法：**
1. 检查 CI 状态
2. 检查分支保护规则设置
3. 手动合并 PR

## 8. 安全考虑

### 8.1 自动合并安全性

- ✅ 只有兼容性检查通过才会创建 PR
- ✅ 必须等待所有 CI 检查通过才会合并
- ✅ 使用 squash merge 保持提交历史清晰
- ✅ 自动删除分支避免分支堆积

### 8.2 版本验证

- ✅ 使用 Swift Codable 结构体验证 JSON schema
- ✅ 验证关键字段的值是否合理
- ✅ 测试所有子命令是否正常工作
- ✅ 检查所有必需文件是否存在

### 8.3 回滚机制

如果发现自动更新引入了问题：

1. **立即回滚**
   ```bash
   git revert {commit-hash}
   git push origin main
   ```

2. **删除错误的 release**
   ```bash
   gh release delete v{version} --yes
   git tag -d v{version}
   git push origin :refs/tags/v{version}
   ```

3. **恢复旧版本**
   - 从之前的 release 下载 DMG
   - 或者从 Git 历史恢复 `Resources/mole/` 目录

## 9. 未来改进

### 9.1 应用内自动更新

**当前：** 用户需要手动下载 DMG 并安装

**计划：** 集成 Sparkle 框架实现真正的应用内自动更新

```swift
import Sparkle

@main
struct MoleApp: App {
    @StateObject private var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}
```

**优势：**
- 用户点击 "Update" 后自动下载并安装
- 支持增量更新（delta updates）
- 自动验证签名和公证
- 更好的用户体验

### 9.2 增强兼容性检查

**计划：**
- 添加更多 JSON schema 字段验证
- 测试磁盘分析功能（`analyze-go`）
- 验证清理脚本的输出格式
- 添加性能基准测试

### 9.3 通知机制

**计划：**
- 自动更新成功后发送通知（GitHub Discussions 或 Issue）
- 兼容性检查失败时发送邮件通知维护者
- 在 README 中显示最新版本徽章

## 10. 相关文件

- `.github/workflows/auto-update-mole.yml` - 自动更新工作流
- `.github/workflows/release.yml` - Release 构建工作流
- `.github/workflows/ci.yml` - CI 检查工作流
- `MoleUI/Model/VersionModel.swift` - 版本检查逻辑
- `MoleUI/View/MoleVersionView.swift` - 版本显示 UI
- `.mole-cli-version` - 当前 Mole CLI 版本
- `MoleUI.xcodeproj/project.pbxproj` - Xcode 项目配置（包含 MARKETING_VERSION）

## 11. 参考资料

- [Mole CLI Repository](https://github.com/tw93/Mole)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Sparkle Framework](https://sparkle-project.org/)
- [Apple Code Signing Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)

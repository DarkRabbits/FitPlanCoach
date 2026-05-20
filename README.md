# FitPlanCoach

FitPlanCoach 是一款基于 SwiftUI + HealthKit 的 iPhone 健身助手。它会读取 Apple 健康中的体重、体脂和运动数据，结合当天食谱、身体变化、目标体重体脂和训练分化，生成当天健身房计划。食谱支持自然语言输入，可本地估算营养，也可以接入 DeepSeek 做 AI 拆解；训练结束后还能统计全天摄入与消耗，判断热量缺口是否合理。

## 功能

- 读取 HealthKit 中最新体重和体脂率，并与上一次数据对比。
- 设置目标日期、目标体重和目标体脂，显示距离目标还需要减少多少。
- 用自然语言记录今日食谱，自动估算热量、蛋白质、碳水和脂肪。
- 支持一周 5 练分化：背 + 肩、胸 + 手臂、臀腿 + 腹部、背 + 肩强化、臀腿 + 手臂 + 腹部。
- 根据食谱、身体数据、上一次变化和目标动态生成训练计划。
- 可选接入 DeepSeek API，生成 AI 食谱拆解和 AI 训练计划。
- 晚间读取活动能量、静息能量和 workout 数据，估算全天热量缺口。

## 隐私与安全

- 仓库不包含真实 DeepSeek API Key，默认 `DeepSeekConfig.apiKey` 为空字符串。
- HealthKit 数据只在用户授权后读取，App 不会把健康数据自动上传到任何服务器。
- 食谱、目标和历史对比数据保存在设备本机 `UserDefaults`。
- 不勾选 `AI 解析` 时，食谱估算完全使用本地规则，不会联网。
- 勾选 `AI 解析` 或点击 `AI 生成今日训练` 时，会把用户输入的食谱、身体数据摘要和目标信息发送给 DeepSeek API 用于生成结果。
- `PrivacyInfo.xcprivacy` 声明了 UserDefaults 使用原因，并声明不追踪用户、不收集数据类型。
- `.gitignore` 已排除 `.DS_Store`、`tmp/`、Xcode 用户状态文件和构建产物。

## 运行

1. 用 Xcode 打开 `FitPlanCoach/FitPlanCoach.xcodeproj`。
2. 在 target `FitPlanCoach` 的 Signing & Capabilities 里选择你的 Apple Developer Team。
3. 确认 HealthKit capability 已开启。
4. 连接 iPhone 真机运行，并在首次启动时允许读取体重、体脂率、活动能量、静息能量和运动记录。

HealthKit 需要真机和用户授权；普通 macOS 环境无法直接读取你的 iPhone 健康数据。

## DeepSeek API Key

需要 AI 功能时，在本地打开 `FitPlanCoach/FitPlanCoach/DeepSeekNutritionClient.swift`，把下面这一行从空字符串改成自己的 DeepSeek API Key：

```swift
static let apiKey = ""
```

示例：

```swift
static let apiKey = "sk-..."
```

重新运行 App 后，在“今日食谱”区域勾选 `AI 解析` 可使用 DeepSeek 拆解营养；在“当日健身项目”区域点击 `AI 生成今日训练` 可生成动态训练计划。

## 项目结构

- `FitPlanCoach/FitPlanCoach/ContentView.swift`：主要 SwiftUI 页面。
- `FitPlanCoach/FitPlanCoach/HealthKitManager.swift`：HealthKit 权限和数据读取。
- `FitPlanCoach/FitPlanCoach/PlanGenerator.swift`：本地训练计划生成。
- `FitPlanCoach/FitPlanCoach/NutritionEstimator.swift`：本地食谱营养估算。
- `FitPlanCoach/FitPlanCoach/DeepSeekNutritionClient.swift`：DeepSeek 食谱解析和共享 API Key 配置。
- `FitPlanCoach/FitPlanCoach/DeepSeekWorkoutClient.swift`：DeepSeek 训练计划生成。
- `FitPlanCoach/FitPlanCoach/Assets.xcassets/AppIcon.appiconset/`：App 图标资源。


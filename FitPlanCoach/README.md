# FitPlanCoach

FitPlanCoach 是一个 SwiftUI + HealthKit iPhone App：

- 每次打开 App 自动请求/读取健康 App 中最新体重和体脂率。
- 将最新身体数据与上一次读取到的新数据对比。
- 根据体重/体脂变化生成今日健身房计划。
- 设置目标日期、目标体重、目标体脂，并显示与当前数据的差距。
- 让你填写今日食物描述，并自动估算热量/宏量营养素。
- 今日训练会参考食谱、最新身体数据、上次身体变化和目标期限；有 DeepSeek Key 时可一键生成 AI 训练计划。
- 晚上训练后读取健康/Fitness 中的今日运动、活动能量、静息能量，并计算全天热量缺口是否合理。

## 分享介绍

FitPlanCoach 是一款面向健身房训练和减脂管理的 iPhone App。它会读取 Apple 健康里的最新体重、体脂和运动数据，结合当天食谱、身体变化、训练分化和目标日期，生成更贴近当天状态的训练计划。食谱支持自然语言输入，既可以用本地词库估算热量和三大营养素，也可以在代码中配置 DeepSeek API Key 后启用 AI 拆解；晚上训练结束后，App 会汇总全天摄入、活动消耗和静息消耗，判断热量缺口是否合理。

## 运行

1. 用 Xcode 打开 `FitPlanCoach.xcodeproj`。
2. 在 target `FitPlanCoach` 的 Signing & Capabilities 里选择你的 Team。
3. 确认 HealthKit capability 已开启。
4. 连接 iPhone 真机运行。HealthKit 不能从普通 macOS App 或未配置好的模拟器读取你的手机健康数据。
5. 第一次运行时允许读取体重、体脂率、活动能量、静息能量和运动记录。

## 数据说明

- 食谱、上一次身体数据和晚间统计保存在本机 `UserDefaults`，不会上传。
- 体脂率来自 HealthKit 的 `bodyFatPercentage`，运动来自 HealthKit workout/active energy。
- 如果健康 App 没有静息能量，晚间热量缺口会显示为趋势参考；Apple Watch 或健康 App 产生静息能量后统计会更完整。
- 食谱估算使用本地内置食物词库和份量规则，例如 `鸡胸肉200g 米饭一碗 西兰花`，不需要联网或 API Key。
- 如果在代码中填写 DeepSeek API Key，食谱页面可勾选 `AI 解析`，用 DeepSeek AI 拆解食谱；不勾选则使用本地词库估算。
- 训练计划也可以调用 DeepSeek，根据今日食谱、身体变化、目标和所选训练部位生成。

## DeepSeek API Key

GitHub 版本不会提交真实 API Key。需要 AI 功能时，请在本地代码中填写自己的 DeepSeek Key 后再运行。

1. 打开 DeepSeek Platform，创建 API Key。
2. 打开 `FitPlanCoach/FitPlanCoach/DeepSeekNutritionClient.swift`。
3. 把 `DeepSeekConfig.apiKey` 从空字符串改成你的 Key，例如：
   ```swift
   static let apiKey = "sk-..."
   ```
4. 重新运行 App。
5. 在“今日食谱”区域勾选 `AI 解析`，再点 `加入今天`。
6. 在“当日健身项目”区域点 `AI 生成今日训练`，即可按目标和当天食谱生成训练计划。

当前使用模型为 `deepseek-v4-flash`，请求格式为 DeepSeek 官方 OpenAI-compatible Chat Completions。

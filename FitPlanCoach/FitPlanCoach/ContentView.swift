import SwiftUI

struct ContentView: View {
    @StateObject private var health = HealthKitManager()
    @StateObject private var store = LocalStore()

    @State private var isRefreshing = false
    @State private var isSettling = false
    @State private var isAnalyzingFood = false
    @State private var isGeneratingPlan = false
    @State private var message: String?
    @State private var selectedSplit = WorkoutSplit.defaultForToday()
    @State private var selectedMeal: Meal = .breakfast
    @State private var food = ""
    @State private var useAIParsing = false
    @State private var aiPlan: GymPlan?
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var targetWeight = ""
    @State private var targetBodyFat = ""
    @State private var loadedGoalDraft = false

    private var plan: GymPlan {
        aiPlan ?? localPlan
    }

    private var localPlan: GymPlan {
        PlanGenerator.makePlan(
            current: store.currentMetrics,
            previous: store.previousMetrics,
            split: selectedSplit,
            goal: store.bodyGoal,
            intakeCalories: store.todayIntakeCalories
        )
    }

    private var currentNutritionEstimate: NutritionEstimate {
        NutritionEstimator.estimate(description: food)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    healthSection
                    goalSection
                    dietSection
                    planSection
                    settlementSection
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("今日健身计划")
            .task {
                await refreshHealthData()
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("目标")
                Spacer()
                if let goal = store.bodyGoal {
                    Text("\(goal.daysRemaining) 天")
                        .font(.headline)
                        .monospacedDigit()
                }
            }

            DatePicker("目标日期", selection: $targetDate, displayedComponents: .date)

            HStack {
                decimalField("目标体重 kg", text: $targetWeight)
                decimalField("目标体脂 %", text: $targetBodyFat)
            }

            HStack {
                Button {
                    saveGoal()
                } label: {
                    Label("保存目标", systemImage: "target")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(Double(targetWeight) == nil && Double(targetBodyFat) == nil)

                Button(role: .destructive) {
                    clearGoal()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 44)
                }
                .buttonStyle(.bordered)
                .disabled(store.bodyGoal == nil)
                .accessibilityLabel("清除目标")
            }

            goalComparison
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            loadGoalDraftIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FitPlan Coach")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Spacer()
                Button {
                    Task { await refreshHealthData() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
                .accessibilityLabel("刷新健康数据")
            }

            Text(PlanGenerator.comparisonText(current: store.currentMetrics, previous: store.previousMetrics))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("健康数据")

            HStack(spacing: 12) {
                metricTile(
                    title: "体重",
                    value: store.currentMetrics?.weightKg.map { String(format: "%.1f kg", $0) } ?? "--",
                    date: store.currentMetrics?.weightDate
                )
                metricTile(
                    title: "体脂",
                    value: store.currentMetrics?.bodyFatPercent.map { String(format: "%.1f%%", $0) } ?? "--",
                    date: store.currentMetrics?.bodyFatDate
                )
            }

            Button {
                Task { await refreshHealthData() }
            } label: {
                Label(isRefreshing ? "读取中" : "授权并读取最新数据", systemImage: "heart.text.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRefreshing)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle(plan.title)
                Spacer()
                Text("\(Int(plan.estimatedTotalCalories.rounded())) kcal")
                    .font(.headline)
                    .monospacedDigit()
            }
            Text(plan.intent)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("训练部位", selection: $selectedSplit) {
                ForEach(WorkoutSplit.allCases) { split in
                    Text(split.rawValue).tag(split)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedSplit) { _, _ in
                aiPlan = nil
            }

            Button {
                Task { await generateAIWorkoutPlan() }
            } label: {
                Label(isGeneratingPlan ? "AI 生成中" : "AI 生成今日训练", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!DeepSeekConfig.hasAPIKey || isGeneratingPlan)

            Text(aiPlan == nil ? "当前为本地动态计划：已参考今日食谱、身体数据变化和目标。" : "当前为 DeepSeek AI 计划：已参考今日食谱、身体数据变化和目标。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(plan.blocks) { block in
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.name)
                        .font(.headline)
                    Text(block.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            ForEach(plan.exercises) { exercise in
                exerciseRow(exercise)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.notes, id: \.self) { note in
                    Label(note, systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var dietSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("今日食谱")
                Spacer()
                Text("\(Int(store.todayIntakeCalories)) kcal")
                    .font(.headline)
                    .monospacedDigit()
            }

            Picker("餐次", selection: $selectedMeal) {
                ForEach(Meal.allCases) { meal in
                    Text(meal.rawValue).tag(meal)
                }
            }
            .pickerStyle(.segmented)

            TextField("例如 鸡胸肉200g 米饭一碗 西兰花", text: $food, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            estimatePreview(currentNutritionEstimate)

            Toggle(isOn: $useAIParsing) {
                Label("AI 解析", systemImage: "sparkles")
                    .font(.headline)
            }
            .toggleStyle(.switch)
            .disabled(!DeepSeekConfig.hasAPIKey)
            .onChange(of: useAIParsing) { _, enabled in
                if enabled && !DeepSeekConfig.hasAPIKey {
                    message = "请先在 DeepSeekNutritionClient.swift 中填写 DeepSeek API Key。"
                    useAIParsing = false
                }
            }

            Text(DeepSeekConfig.hasAPIKey ? "勾选后使用 DeepSeek 拆解；不勾选使用本地食物库匹配。" : "未在代码中填写 DeepSeek API Key，目前只能使用本地匹配。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { await addDietEntry() }
            } label: {
                Label(isAnalyzingFood ? "解析中" : "加入今天", systemImage: useAIParsing ? "sparkles" : "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(food.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzingFood)

            if store.todayDietEntries.isEmpty {
                Text("还没有填写今天的饮食。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.todayDietEntries) { entry in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entry.meal.rawValue) · \(entry.food)")
                                .font(.headline)
                            macroText(entry)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(entry.calories))")
                            .font(.headline)
                            .monospacedDigit()
                        Button {
                            store.deleteDietEntry(id: entry.id)
                            aiPlan = nil
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .accessibilityLabel("删除 \(entry.food)")
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var settlementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("晚间结算")

            Button {
                Task { await settleToday() }
            } label: {
                Label(isSettling ? "统计中" : "读取今日运动并统计缺口", systemImage: "figure.strengthtraining.traditional")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSettling)

            if let summary = store.latestEnergySummary, Calendar.current.isDateInToday(summary.date) {
                VStack(alignment: .leading, spacing: 10) {
                    energyRow("摄入", value: summary.intakeCalories)
                    energyRow("活动能量", value: summary.activeEnergyCalories)
                    energyRow("静息能量", value: summary.basalEnergyCalories)
                    energyRow("运动", value: summary.workoutSummary.workoutCalories, suffix: "kcal · \(Int(summary.workoutSummary.durationMinutes)) 分钟")
                    Divider()
                    energyRow("热量缺口", value: summary.calorieDeficit)
                    Text(PlanGenerator.deficitJudgement(for: summary))
                        .font(.subheadline)
                        .foregroundStyle(summary.hasReliableBasalEnergy ? .primary : .secondary)
                        .padding(.top, 4)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("晚上训练后点这里，会读取今日 Fitness/健康中的运动记录、活动能量和静息能量。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .rounded, weight: .semibold))
    }

    private func metricTile(title: String, value: String, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
            Text(date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "暂无数据")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var goalComparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let goal = store.bodyGoal {
                HStack(spacing: 12) {
                    goalTile(
                        title: "需减重",
                        value: goal.weightDelta(from: store.currentMetrics).map { String(format: "%.1f kg", max(0, $0)) } ?? "--"
                    )
                    goalTile(
                        title: "需降体脂",
                        value: goal.bodyFatDelta(from: store.currentMetrics).map { String(format: "%.1f%%", max(0, $0)) } ?? "--"
                    )
                }

                if let pace = goal.weeklyWeightPace(from: store.currentMetrics), pace > 0 {
                    Text("按目标期限，平均每周需减少约 \(String(format: "%.2f", pace)) kg。")
                        .font(.caption)
                        .foregroundStyle(pace > 1 ? .orange : .secondary)
                } else {
                    Text("已保存目标。读取最新身体数据后会显示差距。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("设置目标日期、目标体重和目标体脂后，训练计划会一起参考目标压力。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func goalTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func decimalField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
    }

    private func exerciseRow(_ exercise: PlanExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(.headline)
                    Text(exercise.equipment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(exercise.estimatedCalories.rounded())) kcal")
                    .font(.headline)
                    .monospacedDigit()
            }

            HStack {
                Label(exercise.prescription, systemImage: "repeat")
                Spacer()
                Label("\(Int(exercise.minutes.rounded())) 分钟", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func macroText(_ entry: DietEntry) -> Text {
        var parts: [String] = ["\(Int(entry.calories)) kcal"]
        if let protein = entry.proteinGrams { parts.append("蛋白 \(Int(protein))g") }
        if let carb = entry.carbGrams { parts.append("碳水 \(Int(carb))g") }
        if let fat = entry.fatGrams { parts.append("脂肪 \(Int(fat))g") }
        return Text(parts.joined(separator: " · "))
    }

    private func estimatePreview(_ estimate: NutritionEstimate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("估算营养")
                    .font(.headline)
                Spacer()
                Text("\(Int(estimate.calories.rounded())) kcal")
                    .font(.headline)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                nutritionPill("蛋白", value: estimate.proteinGrams)
                nutritionPill("碳水", value: estimate.carbGrams)
                nutritionPill("脂肪", value: estimate.fatGrams)
            }

            if estimate.hasMatches {
                Text("识别：\(estimate.matchedFoods.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(estimate.note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func nutritionPill(_ label: String, value: Double) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))g")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func energyRow(_ label: String, value: Double, suffix: String = "kcal") -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(Int(value.rounded())) \(suffix)")
                .font(.headline)
                .monospacedDigit()
        }
    }

    private func addDietEntryLocally() {
        let trimmedFood = food.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFood.isEmpty else { return }

        let estimate = NutritionEstimator.estimate(description: trimmedFood)
        addDietEntry(food: trimmedFood, estimate: estimate)
        message = "已用本地规则估算并加入。"
    }

    private func addDietEntry() async {
        if useAIParsing {
            await addDietEntryUsingAI()
        } else {
            addDietEntryLocally()
        }
    }

    private func addDietEntryUsingAI() async {
        let trimmedFood = food.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFood.isEmpty else { return }
        guard DeepSeekConfig.hasAPIKey else {
            message = DeepSeekNutritionError.missingAPIKey.localizedDescription
            return
        }

        isAnalyzingFood = true
        defer { isAnalyzingFood = false }

        do {
            let estimate = try await DeepSeekNutritionClient().estimate(description: trimmedFood)
            addDietEntry(food: trimmedFood, estimate: estimate)
            message = "已用 DeepSeek 拆解食谱并加入。"
        } catch {
            message = "\(error.localizedDescription) 可先用本地估算加入。"
        }
    }

    private func addDietEntry(food trimmedFood: String, estimate: NutritionEstimate) {

        let entry = DietEntry(
            meal: selectedMeal,
            food: trimmedFood,
            calories: estimate.calories,
            proteinGrams: estimate.proteinGrams,
            carbGrams: estimate.carbGrams,
            fatGrams: estimate.fatGrams
        )
        store.addDietEntry(entry)

        food = ""
        aiPlan = nil
    }

    private func loadGoalDraftIfNeeded() {
        guard !loadedGoalDraft else { return }
        loadedGoalDraft = true

        guard let goal = store.bodyGoal else { return }
        targetDate = goal.targetDate
        targetWeight = goal.targetWeightKg.map { String(format: "%.1f", $0) } ?? ""
        targetBodyFat = goal.targetBodyFatPercent.map { String(format: "%.1f", $0) } ?? ""
    }

    private func saveGoal() {
        let goal = BodyGoal(
            targetDate: targetDate,
            targetWeightKg: Double(targetWeight),
            targetBodyFatPercent: Double(targetBodyFat),
            updatedAt: Date()
        )
        store.updateBodyGoal(goal)
        aiPlan = nil
        message = "目标已保存，今日训练计划会参考这个目标。"
    }

    private func clearGoal() {
        store.clearBodyGoal()
        targetDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        targetWeight = ""
        targetBodyFat = ""
        aiPlan = nil
        message = "目标已清除。"
    }

    private func generateAIWorkoutPlan() async {
        guard DeepSeekConfig.hasAPIKey else {
            message = "请先在 DeepSeekNutritionClient.swift 中填写 DeepSeek API Key。"
            return
        }

        isGeneratingPlan = true
        defer { isGeneratingPlan = false }

        do {
            aiPlan = try await DeepSeekWorkoutClient().makePlan(
                split: selectedSplit,
                current: store.currentMetrics,
                previous: store.previousMetrics,
                goal: store.bodyGoal,
                dietEntries: store.todayDietEntries
            )
            message = "已用 DeepSeek 生成今日训练计划。"
        } catch {
            message = "\(error.localizedDescription) 当前仍可使用本地动态计划。"
        }
    }

    private func refreshHealthData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await health.requestAuthorization()
            let metrics = try await health.fetchLatestBodyMetrics()
            store.ingest(metrics: metrics)
            aiPlan = nil
            message = "已读取最新健康数据。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func settleToday() async {
        guard !isSettling else { return }
        isSettling = true
        defer { isSettling = false }

        do {
            try await health.requestAuthorization()
            let summary = try await health.fetchTodayEnergySummary(intakeCalories: store.todayIntakeCalories)
            store.updateEnergySummary(summary)
            message = "晚间统计已更新。"
        } catch {
            message = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}

// MacroDepthTests/ProfileAndDashboardTests.swift

import Foundation
import SwiftData
import Testing
@testable import MacroDepth

private let referenceDate: Date = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .gmt
    return calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12)) ?? .distantPast
}()

private let referenceCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .gmt
    return calendar
}()

/// 80 kg, 180 cm, aged 30 on the reference date.
private func makeProfile(
    weightKg: Double = 80,
    heightCm: Double = 180,
    birthYear: Int = 1996,
    sex: BiologicalSex = .male,
    activity: ActivityLevel = .moderate,
    goal: FitnessGoal = .maintenance,
    overrides: TargetOverrides = .none
) -> UserProfileDraft {
    UserProfileDraft(
        weightKg: weightKg,
        heightCm: heightCm,
        birthYear: birthYear,
        biologicalSex: sex,
        activityLevel: activity,
        goal: goal,
        overrides: overrides
    )
}

private func targets(_ profile: UserProfileDraft) -> NutritionTargets {
    profile.targets(on: referenceDate, calendar: referenceCalendar)
}

private func isClose(_ lhs: Double, _ rhs: Double, within tolerance: Double = 0.01) -> Bool {
    abs(lhs - rhs) < tolerance
}

// MARK: - Target calculation

struct NutritionTargetTests {
    @Test func bmrMatchesMifflinStJeor() {
        // 10·80 + 6.25·180 − 5·30 = 1775
        #expect(makeProfile(sex: .male).targets(on: referenceDate, calendar: referenceCalendar).basalMetabolicRate == 1780)
        #expect(makeProfile(sex: .female).targets(on: referenceDate, calendar: referenceCalendar).basalMetabolicRate == 1614)
    }

    @Test(arguments: [
        (ActivityLevel.sedentary, 2136.0),
        (ActivityLevel.moderate, 2759.0),
        (ActivityLevel.veryActive, 3070.5),
    ])
    func tdeeUsesActivityMultiplier(level: ActivityLevel, expected: Double) {
        #expect(isClose(targets(makeProfile(activity: level)).totalDailyEnergyExpenditure, expected))
    }

    @Test func leanBulkAddsSurplusAndUsesItsProteinFactor() {
        let result = targets(makeProfile(goal: .leanBulk))
        #expect(isClose(result.calories, 3059))
        #expect(isClose(result.proteinGrams, 160))
    }

    @Test func fatLossSubtractsDeficitAndUsesItsProteinFactor() {
        let result = targets(makeProfile(goal: .fatLoss))
        #expect(isClose(result.calories, 2359))
        #expect(isClose(result.proteinGrams, 176))
    }

    @Test func maintenanceUsesBaselineAndItsProteinFactor() {
        let result = targets(makeProfile(goal: .maintenance))
        #expect(isClose(result.calories, 2759))
        #expect(isClose(result.proteinGrams, 144))
    }

    @Test(arguments: FitnessGoal.allCases)
    func calculatedMacrosAddUpToTheCalorieTarget(goal: FitnessGoal) {
        let result = targets(makeProfile(goal: goal))
        #expect(isClose(result.macroCalories, result.calories))
        #expect(!result.hasMacroMismatch)
        #expect(isClose(result.fatGrams * 9, result.calories * 0.25))
    }

    @Test(arguments: [
        (BiologicalSex.female, 1200.0),
        (BiologicalSex.male, 1500.0),
    ])
    func deficitCannotGoBelowTheCalorieFloor(sex: BiologicalSex, floor: Double) {
        let small = makeProfile(weightKg: 45, heightCm: 150, birthYear: 1950, sex: sex, activity: .sedentary, goal: .fatLoss)
        let result = targets(small)
        #expect(result.calories == floor)
        #expect(result.calorieFloorApplied)
    }

    @Test(arguments: [
        (BiologicalSex.female, 1200.0),
        (BiologicalSex.male, 1500.0),
    ])
    func calorieOverrideCannotGoBelowTheFloor(sex: BiologicalSex, floor: Double) {
        let result = targets(makeProfile(sex: sex, overrides: TargetOverrides(calories: 500)))
        #expect(result.calories == floor)
    }

    @Test func overridesReplaceCalculatedValuesAndCarbsAbsorbTheDifference() {
        let result = targets(makeProfile(overrides: TargetOverrides(calories: 2500, proteinGrams: 200)))
        #expect(result.calories == 2500)
        #expect(result.proteinGrams == 200)
        #expect(isClose(result.fatGrams, 2500 * 0.25 / 9))
        #expect(isClose(result.macroCalories, 2500))
        #expect(!result.calorieFloorApplied)
    }

    @Test func macroOverridesAreClampedAndInvalidValuesIgnored() {
        let result = targets(makeProfile(overrides: TargetOverrides(
            calories: .infinity,
            proteinGrams: 5_000,
            carbohydrateGrams: -50,
            fatGrams: 1
        )))
        #expect(isClose(result.calories, 2759))    // non-finite falls back to calculated
        #expect(result.proteinGrams == TargetLimits.protein.upperBound)
        #expect(result.carbohydrateGrams == 0)
        #expect(result.fatGrams == TargetLimits.fat.lowerBound)
    }

    @Test func inconsistentManualMacrosAreFlagged() {
        let result = targets(makeProfile(overrides: TargetOverrides(calories: 2000, carbohydrateGrams: 800)))
        #expect(result.hasMacroMismatch)
    }

    @Test func proteinHeavyTargetsNeverProduceNegativeCarbs() {
        let result = targets(makeProfile(overrides: TargetOverrides(calories: 1500, proteinGrams: 400)))
        #expect(result.carbohydrateGrams == 0)
        #expect(result.hasMacroMismatch)
    }

    @Test func underweightCutIsFlaggedOnlyForFatLoss() {
        #expect(makeProfile(weightKg: 50, heightCm: 180, goal: .fatLoss).isUnderweightForFatLoss)
        #expect(!makeProfile(weightKg: 50, heightCm: 180, goal: .leanBulk).isUnderweightForFatLoss)
        #expect(!makeProfile(goal: .fatLoss).isUnderweightForFatLoss)
    }
}

struct DailyProgressTests {
    private let baseTargets = targets(makeProfile(overrides: TargetOverrides(calories: 2000)))

    @Test func remainingIsTargetMinusEatenPlusBurned() {
        let eaten = MacroNutrients(proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0, energyKilocalories: 500)
        let progress = DailyProgress(targets: baseTargets, eaten: eaten, burnedCalories: 200)
        #expect(progress.remainingCalories == 1700)
        #expect(!progress.isOverTarget)
        #expect(isClose(progress.calorieFraction, 500.0 / 2200))
    }

    @Test func goingOverTargetIsReportedAndTheRingStaysFull() {
        let eaten = MacroNutrients(proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0, energyKilocalories: 2300)
        let progress = DailyProgress(targets: baseTargets, eaten: eaten)
        #expect(progress.remainingCalories == -300)
        #expect(progress.isOverTarget)
        #expect(progress.calorieFraction == 1)
    }

    @Test func fractionHandlesAZeroTarget() {
        #expect(DailyProgress.fraction(50, of: 0) == 0)
        #expect(DailyProgress.fraction(-5, of: 100) == 0)
    }
}

// MARK: - Persistence

@MainActor
struct ProfilePersistenceTests {
    @Test func savingTwiceKeepsOneProfileWithTheLatestValues() throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        #expect(try service.currentProfile() == nil)

        try service.saveProfile(makeProfile(goal: .leanBulk))
        var updated = makeProfile(weightKg: 82, goal: .fatLoss, overrides: TargetOverrides(calories: 2100))
        updated.birthYear = 1990
        try service.saveProfile(updated)

        #expect(try service.currentProfile() == updated)
        #expect(try service.container.mainContext.fetchCount(FetchDescriptor<UserProfile>()) == 1)
    }

    @Test func invalidProfilesAreRejected() throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        #expect(throws: PersistenceError.self) {
            try service.saveProfile(makeProfile(weightKg: 5))
        }
        #expect(throws: PersistenceError.self) {
            try service.saveProfile(makeProfile(birthYear: Calendar.current.component(.year, from: .now) - 12))
        }
        #expect(try service.currentProfile() == nil)
    }

    /// A store from before `UserProfile` must open, and keep its meals and new-optional fields.
    @Test func existingStoreMigratesAndKeepsItsMeals() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Migration.store")

        do {
            let oldSchema = Schema([MealEntry.self, LoggedFoodItem.self])
            let container = try ModelContainer(for: oldSchema, configurations: ModelConfiguration(schema: oldSchema, url: storeURL))
            container.mainContext.insert(MealEntry(timestamp: referenceDate, mealType: .lunch))
            try container.mainContext.save()
        }

        let schema = SwiftDataPersistenceService.schema
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MealEntry>()) == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<UserProfile>()) == 0)
    }
}

// MARK: - Dashboard reactivity

@MainActor
struct DashboardViewModelTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1_000 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func meal(at date: Date) -> MealDraft {
        MealDraft(timestamp: date, mealType: .lunch, items: SampleScene.sampleFoodItemDrafts())
    }

    @Test func updatesWithoutReloadingWhenMealsAreSavedAndDeleted() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        try service.saveProfile(makeProfile())
        let viewModel = DashboardViewModel(persistence: service)
        let observation = Task { await viewModel.observeChanges() }
        defer { observation.cancel() }

        try await waitUntil { viewModel.profile != nil }
        // Let the observer subscribe before changing anything.
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.eaten == .zero)

        let draft = meal(at: .now)
        let saved = try await service.saveMeal(draft)
        try await waitUntil { viewModel.eaten != .zero }
        #expect(isClose(viewModel.eaten.energyKilocalories, draft.totalMacros.energyKilocalories))
        #expect(isClose(viewModel.eaten.proteinGrams, draft.totalMacros.proteinGrams))

        try await service.deleteMeal(saved)
        try await waitUntil { viewModel.eaten == .zero }
        #expect(viewModel.eaten == .zero)
    }

    @Test func updatesWhenTheProfileChanges() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let viewModel = DashboardViewModel(persistence: service)
        let observation = Task { await viewModel.observeChanges() }
        defer { observation.cancel() }

        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.progress == nil)

        try service.saveProfile(makeProfile(goal: .fatLoss))
        try await waitUntil { viewModel.progress != nil }
        #expect(viewModel.profile?.goal == .fatLoss)
    }

    @Test func countsOnlyTodaysMeals() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        try service.saveProfile(makeProfile())
        let today = Date.now
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: today))
        try await service.saveMeal(meal(at: yesterday))

        let viewModel = DashboardViewModel(persistence: service, now: { today })
        viewModel.load()
        #expect(viewModel.eaten == .zero)

        let moved = DashboardViewModel(persistence: service, now: { yesterday })
        moved.load()
        #expect(moved.eaten != .zero)
    }

    @Test func remainingReflectsWhatWasEaten() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let profile = makeProfile(overrides: TargetOverrides(calories: 2000))
        try service.saveProfile(profile)
        let draft = meal(at: .now)
        try await service.saveMeal(draft)

        let viewModel = DashboardViewModel(persistence: service)
        viewModel.load()

        let progress = try #require(viewModel.progress)
        #expect(isClose(progress.remainingCalories, 2000 - draft.totalMacros.energyKilocalories))
    }
}

// MARK: - Onboarding

@MainActor
struct OnboardingViewModelTests {
    private func makeViewModel(
        existing: UserProfileDraft? = nil
    ) throws -> (OnboardingViewModel, SwiftDataPersistenceService) {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let viewModel = OnboardingViewModel(
            persistence: service,
            existingProfile: existing,
            now: referenceDate,
            calendar: referenceCalendar
        )
        return (viewModel, service)
    }

    private func fillStats(_ viewModel: OnboardingViewModel) {
        viewModel.weightText = "80"
        viewModel.heightText = "180"
        viewModel.ageText = "30"
        viewModel.biologicalSex = .male
        viewModel.activityLevel = .moderate
    }

    @Test func stepsRequireTheirInput() throws {
        let (viewModel, _) = try makeViewModel()
        #expect(viewModel.step == .goal)
        viewModel.advance()
        #expect(viewModel.step == .goal)     // no goal yet

        viewModel.goal = .leanBulk
        viewModel.advance()
        #expect(viewModel.step == .stats)
        viewModel.advance()
        #expect(viewModel.step == .stats)    // no stats yet

        fillStats(viewModel)
        viewModel.advance()
        #expect(viewModel.step == .review)
        viewModel.goBack()
        #expect(viewModel.step == .stats)
    }

    @Test func parsesCommaAndDotDecimals() throws {
        let (viewModel, _) = try makeViewModel()
        viewModel.weightText = "72,5"
        #expect(viewModel.weightKg == 72.5)
        viewModel.weightText = "72.5"
        #expect(viewModel.weightKg == 72.5)
    }

    @Test func outOfRangeInputShowsErrorsAndBlocksTheFlow() throws {
        let (viewModel, _) = try makeViewModel()
        viewModel.goal = .fatLoss
        viewModel.advance()
        fillStats(viewModel)
        viewModel.ageText = "15"
        #expect(viewModel.ageError != nil)
        #expect(!viewModel.canAdvance)

        viewModel.ageText = "30"
        viewModel.weightText = "500"
        #expect(viewModel.weightError != nil)
        #expect(!viewModel.canAdvance)

        viewModel.weightText = ""
        #expect(viewModel.weightError == nil)   // empty isn't an error yet
        #expect(!viewModel.canAdvance)
    }

    @Test func ageBecomesBirthYearAndTargetsMatchTheCalculator() throws {
        let (viewModel, _) = try makeViewModel()
        viewModel.goal = .leanBulk
        fillStats(viewModel)
        #expect(viewModel.draft?.birthYear == 1996)
        #expect(viewModel.targets == targets(makeProfile(goal: .leanBulk)))
    }

    @Test func tweaksAreClampedAndCanBeReset() throws {
        let (viewModel, _) = try makeViewModel()
        viewModel.goal = .maintenance
        fillStats(viewModel)
        let calculated = try #require(viewModel.targets)

        viewModel.adjustProtein(by: 10)
        #expect(viewModel.targets?.proteinGrams == calculated.proteinGrams + 10)
        #expect(viewModel.hasOverrides)

        for _ in 0..<100 { viewModel.adjustCalories(by: -OnboardingViewModel.calorieStep) }
        #expect(viewModel.targets?.calories == TargetLimits.calories(for: .male).lowerBound)
        // One step up moves immediately, rather than undoing accumulated overshoot.
        viewModel.adjustCalories(by: OnboardingViewModel.calorieStep)
        #expect(viewModel.targets?.calories == TargetLimits.calories(for: .male).lowerBound + OnboardingViewModel.calorieStep)

        viewModel.resetOverrides()
        #expect(viewModel.targets == calculated)
        #expect(!viewModel.hasOverrides)
    }

    @Test func savePersistsOverrides() throws {
        let (viewModel, service) = try makeViewModel()
        viewModel.goal = .fatLoss
        fillStats(viewModel)
        viewModel.adjustCalories(by: 50)

        #expect(viewModel.save())

        let stored = try #require(try service.currentProfile())
        #expect(stored.goal == .fatLoss)
        #expect(stored.overrides.calories == viewModel.targets?.calories)
    }

    @Test func editingStartsFromTheExistingProfile() throws {
        let existing = makeProfile(weightKg: 72.5, goal: .fatLoss, overrides: TargetOverrides(proteinGrams: 150))
        let (viewModel, _) = try makeViewModel(existing: existing)

        #expect(viewModel.isEditing)
        #expect(viewModel.goal == .fatLoss)
        #expect(viewModel.weightKg == 72.5)
        #expect(viewModel.age == 30)
        #expect(viewModel.draft == existing)
    }
}

// MARK: - Recipes

struct RecipeCatalogTests {
    @Test func idsAreUnique() {
        #expect(Set(RecipeCatalog.all.map(\.id)).count == RecipeCatalog.all.count)
    }

    @Test(arguments: FitnessGoal.allCases)
    func everyGoalHasEveryMealType(goal: FitnessGoal) {
        for mealType in MealType.allCases {
            #expect(!RecipeRecommender.recommend(goal: goal, mealType: mealType).isEmpty, "\(goal) has no \(mealType)")
        }
    }

    /// Stated energy must agree with the stated macros.
    @Test(arguments: RecipeCatalog.all)
    func caloriesMatchMacros(recipe: RecipeSuggestion) {
        let atwater = MacroNutrients.atwaterEnergy(protein: recipe.proteinG, carbohydrate: recipe.carbsG, fat: recipe.fatG, fiber: 0)
        #expect(abs(atwater - recipe.estimatedCalories) < 5, "\(recipe.title): \(atwater) vs \(recipe.estimatedCalories)")
    }

    @Test(arguments: RecipeCatalog.all)
    func recipesAreComplete(recipe: RecipeSuggestion) {
        #expect(!recipe.ingredientsList.isEmpty)
        #expect(!recipe.preparationInstructions.isEmpty)
        #expect(recipe.scanNotes.count <= MealNotes.maximumLength)
    }

    @Test func recipesAreHighProtein() {
        for recipe in RecipeCatalog.all where recipe.targetGoal != .maintenance {
            #expect(recipe.proteinG >= 25, "\(recipe.title)")
        }
    }

    @Test func scanNotesIncludeIngredientsStepsAndServing() throws {
        let recipe = try #require(RecipeCatalog.all.first { $0.id == "bulk-overnight-protein-oats" })
        let notes = recipe.scanNotes
        #expect(notes.contains("Overnight Protein Oats (serves 1)"))
        #expect(notes.contains("- 80 g rolled oats"))
        #expect(notes.contains("1. Stir the oats"))
    }
}

struct RecipeRecommenderTests {
    private func recipe(_ id: String, calories: Double, protein: Double, goal: FitnessGoal = .fatLoss, meal: MealType = .lunch) -> RecipeSuggestion {
        RecipeSuggestion(
            id: id,
            title: id,
            mealType: meal,
            targetGoal: goal,
            estimatedCalories: calories,
            proteinG: protein,
            carbsG: 0,
            fatG: 0,
            ingredientsList: [],
            preparationInstructions: []
        )
    }

    @Test func filtersByGoalAndMealType() {
        let catalog = [
            recipe("match", calories: 300, protein: 30),
            recipe("wrong-goal", calories: 300, protein: 30, goal: .leanBulk),
            recipe("wrong-meal", calories: 300, protein: 30, meal: .snack),
        ]
        #expect(RecipeRecommender.recommend(from: catalog, goal: .fatLoss, mealType: .lunch).map(\.id) == ["match"])
    }

    @Test func recipesThatFitComeFirstThenByProteinDensity() {
        let catalog = [
            recipe("too-big-but-dense", calories: 800, protein: 100),
            recipe("fits-low", calories: 400, protein: 20),
            recipe("fits-high", calories: 400, protein: 40),
        ]
        let result = RecipeRecommender.recommend(from: catalog, goal: .fatLoss, remainingCalories: 500)
        #expect(result.map(\.id) == ["fits-high", "fits-low", "too-big-but-dense"])
    }

    @Test func withoutARemainingBudgetEverythingFits() {
        #expect(RecipeRecommender.fits(recipe("any", calories: 5_000, protein: 1), remainingCalories: nil))
    }
}

@MainActor
struct RecipesViewModelTests {
    @Test func followsTheProfileGoalUntilTheUserChoosesAnother() throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        try service.saveProfile(makeProfile(goal: .fatLoss))
        let viewModel = RecipesViewModel(persistence: service)

        viewModel.load()
        #expect(viewModel.selectedGoal == .fatLoss)
        #expect(viewModel.recipes.allSatisfy { $0.targetGoal == .fatLoss })

        viewModel.selectedGoal = .leanBulk
        try service.saveProfile(makeProfile(goal: .maintenance))
        viewModel.load()
        #expect(viewModel.selectedGoal == .leanBulk)
    }

    @Test func remainingCaloriesComeFromTodaysMeals() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        try service.saveProfile(makeProfile(overrides: TargetOverrides(calories: 2000)))
        let draft = MealDraft(timestamp: .now, mealType: .lunch, items: SampleScene.sampleFoodItemDrafts())
        try await service.saveMeal(draft)

        let viewModel = RecipesViewModel(persistence: service)
        viewModel.load()

        let remaining = try #require(viewModel.remainingCalories)
        #expect(isClose(remaining, 2000 - draft.totalMacros.energyKilocalories))
    }

    @Test func worksWithoutAProfile() throws {
        let viewModel = RecipesViewModel(persistence: try SwiftDataPersistenceService.makeInMemory())
        viewModel.load()
        #expect(viewModel.remainingCalories == nil)
        #expect(!viewModel.recipes.isEmpty)
    }
}

// MARK: - Recipe → scan

@MainActor
struct RecipePrefillTests {
    private let recipeA = "Recipe A"
    private let recipeB = "Recipe B"

    private func makeViewModel() throws -> ScanViewModel {
        ScanViewModel(
            scanner: SimulatedScannerService(startupDelay: .zero, captureDelay: .zero),
            nutrition: MockNutritionService(latency: .zero),
            persistence: try SwiftDataPersistenceService.makeInMemory(),
            permissions: MockCameraPermissionService()
        )
    }

    private func wait(for phase: ScanViewModel.Phase, in viewModel: ScanViewModel) async throws {
        for _ in 0..<1_000 where viewModel.phase != phase {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(viewModel.phase == phase)
    }

    /// Drives a scan to the review screen.
    private func runToReview(_ viewModel: ScanViewModel) async throws {
        try await wait(for: .ready, in: viewModel)
        viewModel.capturePrimaryPhoto()
        try await wait(for: .awaitingSecondaryPhoto, in: viewModel)
        viewModel.skipSecondaryPhoto()
        viewModel.analyze()
        try await wait(for: .review, in: viewModel)
    }

    @Test func fillsNotesBeforeAScanStarts() throws {
        let viewModel = try makeViewModel()
        viewModel.prefillNotes(recipeA)
        #expect(viewModel.userNotes == recipeA)
    }

    @Test func aSecondRecipeReplacesTheFirstButKeepsTypedNotes() throws {
        let viewModel = try makeViewModel()
        viewModel.prefillNotes(recipeA)
        viewModel.prefillNotes(recipeB)
        #expect(viewModel.userNotes == recipeB)

        viewModel.userNotes = "Extra butter"
        viewModel.prefillNotes(recipeA)
        #expect(viewModel.userNotes == "Extra butter\n\n\(recipeA)")
    }

    /// The unsaved meal keeps its own notes; the recipe waits for the next scan.
    @Test func doesNotChangeAMealAwaitingReview() async throws {
        let viewModel = try makeViewModel()
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        viewModel.userNotes = "Original notes"
        try await runToReview(viewModel)

        viewModel.prefillNotes(recipeA)
        #expect(viewModel.userNotes == "Original notes")
        #expect(viewModel.hasQueuedNotes)
        #expect(!viewModel.drafts.isEmpty)

        viewModel.reset()
        #expect(viewModel.userNotes == recipeA)
        #expect(!viewModel.hasQueuedNotes)
    }

    @Test func startsAFreshScanAfterASavedMeal() async throws {
        let viewModel = try makeViewModel()
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }
        viewModel.userNotes = "Old meal"
        try await runToReview(viewModel)
        await viewModel.saveMeal()
        #expect(viewModel.phase == .saved)

        viewModel.prefillNotes(recipeA)

        #expect(viewModel.userNotes == recipeA)
        #expect(viewModel.phase == .ready)
    }

    @Test func prefilledNotesAreSavedWithTheMeal() async throws {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let viewModel = ScanViewModel(
            scanner: SimulatedScannerService(startupDelay: .zero, captureDelay: .zero),
            nutrition: MockNutritionService(latency: .zero),
            persistence: service,
            permissions: MockCameraPermissionService()
        )
        let activation = Task { await viewModel.activate() }
        defer { activation.cancel() }

        viewModel.prefillNotes(recipeA)
        try await runToReview(viewModel)
        await viewModel.saveMeal()

        #expect(try service.meals(on: .now).first?.notes == recipeA)
    }
}

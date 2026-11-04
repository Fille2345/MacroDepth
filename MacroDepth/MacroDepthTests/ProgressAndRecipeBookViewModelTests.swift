// MacroDepthTests/ProgressAndRecipeBookViewModelTests.swift

import Foundation
import Testing
@testable import MacroDepth

private let stockholm: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .gmt
    return calendar
}()

private func day(_ day: Int, month: Int = 11, hour: Int = 12) -> Date {
    stockholm.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? .distantPast
}

struct ProgressSeriesTests {
    private func point(_ date: Date, _ kilograms: Double) -> WeightPoint {
        WeightPoint(date: stockholm.startOfDay(for: date), kilograms: kilograms)
    }

    @Test(arguments: ProgressRange.allCases)
    func rangeCoversExactlyThatManyDaysIncludingToday(range: ProgressRange) throws {
        let interval = try #require(ProgressSeries.interval(for: range, endingOn: day(20), calendar: stockholm))
        #expect(stockholm.dateComponents([.day], from: interval.start, to: interval.end).day == range.days)
        #expect(interval.contains(day(20, hour: 23)))
        #expect(interval.start == stockholm.startOfDay(for: interval.start))
    }

    @Test func trendIsTheMeanOfTheTrailingSevenDays() {
        let points = [point(day(1), 80), point(day(4), 83), point(day(7), 83), point(day(8), 90)]
        let trend = ProgressSeries.trend(of: points, visibleFrom: stockholm.startOfDay(for: day(1)), calendar: stockholm)

        let onlyItself = 80.0
        let withDayFour = 81.5
        let dayOneIsTheSeventhDayBack: Double = 246.0 / 3
        let dayOneHasLeftTheWindow: Double = 256.0 / 3
        let expected = [onlyItself, withDayFour, dayOneIsTheSeventhDayBack, dayOneHasLeftTheWindow]
        #expect(trend.map(\.kilograms) == expected)
    }

    @Test func trendStartsAtTheVisibleEdgeButAveragesEarlierWeighIns() {
        let points = [point(day(1), 90), point(day(5), 80), point(day(6), 82)]
        let trend = ProgressSeries.trend(of: points, visibleFrom: stockholm.startOfDay(for: day(5)), calendar: stockholm)
        #expect(trend.map(\.kilograms) == [85, 84])
    }

    @Test func intakeIsSummedPerDayAndSkipsUnloggedDays() {
        let macros = MacroNutrients(proteinGrams: 30, carbohydrateGrams: 0, fatGrams: 0, energyKilocalories: 200)
        let intake = ProgressSeries.dailyIntake(
            from: [(day(3, hour: 20), macros), (day(1), macros), (day(3, hour: 8), macros)],
            calendar: stockholm
        )
        #expect(intake.map(\.day) == [stockholm.startOfDay(for: day(1)), stockholm.startOfDay(for: day(3))])
        #expect(intake.map(\.calories) == [200, 400])
        #expect(intake.map(\.proteinGrams) == [30, 60])
    }

    @Test func averagesLeaveOutTodayAndUnloggedDays() throws {
        let intake = [
            DailyIntake(day: stockholm.startOfDay(for: day(1)), calories: 2000, proteinGrams: 100),
            DailyIntake(day: stockholm.startOfDay(for: day(5)), calories: 3000, proteinGrams: 200),
            DailyIntake(day: stockholm.startOfDay(for: day(9)), calories: 100, proteinGrams: 5),
        ]
        let averages = try #require(ProgressSeries.averages(of: intake, excludingDayOf: day(9), calendar: stockholm))
        #expect(averages.calories == 2500)
        #expect(averages.proteinGrams == 150)
        #expect(averages.dayCount == 2)

        #expect(ProgressSeries.averages(of: Array(intake.suffix(1)), excludingDayOf: day(9), calendar: stockholm) == nil)
    }
}

@MainActor
struct ProgressTrackerViewModelTests {
    private let today = day(20)

    private func make(profile: UserProfileDraft? = nil) throws -> (ProgressTrackerViewModel, SwiftDataPersistenceService) {
        let service = try SwiftDataPersistenceService.makeInMemory(calendar: stockholm)
        if let profile { try service.saveProfile(profile) }
        let date = today
        let viewModel = ProgressTrackerViewModel(persistence: service, calendar: stockholm, now: { date })
        viewModel.load()
        return (viewModel, service)
    }

    private var profile: UserProfileDraft {
        UserProfileDraft(weightKg: 80, heightCm: 180, birthYear: 1996, biologicalSex: .male, activityLevel: .moderate, goal: .leanBulk)
    }

    // MARK: Target prompt

    @Test func newWeightAsksAndChangesNothingUntilAnswered() throws {
        let (viewModel, service) = try make(profile: profile)
        viewModel.weightText = "77,5"
        viewModel.logWeight()

        let prompt = try #require(viewModel.targetPrompt)
        #expect(prompt.updatedProfile.weightKg == 77.5)
        #expect(try service.currentProfile()?.weightKg == 80)
        #expect(try service.latestWeightEntry()?.weightKg == 77.5)
        #expect(viewModel.weightText.isEmpty)
    }

    @Test func acceptingUpdatesTheProfileAndItsTargets() throws {
        let (viewModel, service) = try make(profile: profile)
        let before = try #require(viewModel.targets)
        viewModel.weightText = "70"
        viewModel.logWeight()
        let prompt = try #require(viewModel.targetPrompt)

        viewModel.applyTargetUpdate(prompt)

        #expect(viewModel.targetPrompt == nil)
        #expect(try service.currentProfile()?.weightKg == 70)
        #expect(try #require(viewModel.targets).calories < before.calories)
    }

    @Test func decliningKeepsTheProfileAndTheWeighIn() throws {
        let (viewModel, service) = try make(profile: profile)
        viewModel.weightText = "78"
        viewModel.logWeight()

        viewModel.dismissTargetPrompt()

        #expect(viewModel.targetPrompt == nil)
        #expect(try service.currentProfile()?.weightKg == 80)
        #expect(try service.latestWeightEntry()?.weightKg == 78)
    }

    @Test func manualTargetsAreDescribedAsStayingTheSame() throws {
        var manual = profile
        manual.overrides = TargetOverrides(calories: 2500, proteinGrams: 150, carbohydrateGrams: 250, fatGrams: 80)
        let (viewModel, _) = try make(profile: manual)
        viewModel.weightText = "70"
        viewModel.logWeight()

        let prompt = try #require(viewModel.targetPrompt)
        #expect(prompt.message.contains("would stay at"))
        #expect(prompt.updatedProfile.overrides == manual.overrides)
    }

    /// The profile says 80 kg, so it only asks from 1 kg away, in either direction.
    @Test(arguments: [
        ("80", false), ("80.9", false), ("79.1", false), ("79.5", false),
        ("81", true), ("79", true), ("81.1", true), ("78.9", true),
    ])
    func asksOnlyFromOneKilogramAway(text: String, asks: Bool) throws {
        let (viewModel, service) = try make(profile: profile)
        viewModel.weightText = text
        viewModel.logWeight()
        #expect((viewModel.targetPrompt != nil) == asks)
        #expect(try service.latestWeightEntry()?.weightKg == OnboardingViewModel.parse(text))
    }

    @Test func exactlyOneKilogramCountsDespiteRounding() throws {
        var nearby = profile
        nearby.weightKg = 80.1
        let (viewModel, _) = try make(profile: nearby)
        viewModel.weightText = "79.1"   // 80.1 − 79.1 is 0.99999… in floating point
        viewModel.logWeight()
        #expect(viewModel.targetPrompt != nil)
    }

    @Test func thresholdComparesWithTheProfileNotThePreviousWeighIn() throws {
        let (viewModel, service) = try make(profile: profile)
        try service.saveWeight(kilograms: 79.5, on: day(10))
        try service.saveWeight(kilograms: 79.2, on: day(15))
        viewModel.weightText = "79"     // only 0.2 kg from the last weigh-in, but 1 kg from the profile
        viewModel.logWeight()
        #expect(viewModel.targetPrompt != nil)
    }

    @Test func doesNotAskWithoutAProfile() throws {
        let (viewModel, service) = try make()
        viewModel.weightText = "80"
        viewModel.logWeight()
        #expect(viewModel.targetPrompt == nil)
        #expect(try service.latestWeightEntry()?.weightKg == 80)
    }

    @Test func backfillingAnOlderDayDoesNotAsk() throws {
        let (viewModel, service) = try make(profile: profile)
        try service.saveWeight(kilograms: 79, on: day(19))
        viewModel.weightDate = day(10)
        viewModel.weightText = "85"
        viewModel.logWeight()

        #expect(viewModel.targetPrompt == nil)
        #expect(try service.currentProfile()?.weightKg == 80)
    }

    // MARK: Input

    @Test(arguments: ["", "abc", "29", "301"])
    func invalidWeightIsNotLogged(text: String) throws {
        let (viewModel, service) = try make(profile: profile)
        viewModel.weightText = text
        viewModel.logWeight()
        #expect(try service.latestWeightEntry() == nil)
        #expect(viewModel.parsedWeight == nil)
        #expect((viewModel.weightError != nil) == !text.isEmpty)
    }

    // MARK: Charts

    @Test func rangeControlsTheData() async throws {
        let (viewModel, service) = try make(profile: profile)
        try service.saveWeight(kilograms: 80, on: day(20))
        try service.saveWeight(kilograms: 81, on: day(1))              // 19 days ago
        try service.saveWeight(kilograms: 82, on: day(1, month: 9))    // about 80 days ago
        try await service.saveMeal(MealDraft(timestamp: day(1), mealType: .lunch, items: SampleScene.sampleFoodItemDrafts()))

        #expect(viewModel.selectedRange == .month)
        viewModel.load()
        #expect(viewModel.weightPoints.count == 2)
        #expect(viewModel.intake.count == 1)

        viewModel.selectedRange = .week
        #expect(viewModel.weightPoints.map(\.kilograms) == [80])
        #expect(viewModel.intake.isEmpty)

        viewModel.selectedRange = .quarter
        #expect(viewModel.weightPoints.count == 3)
    }

    @Test func trendAndChangeUseWeighInsFromBeforeTheVisibleRange() throws {
        let (viewModel, service) = try make(profile: profile)
        try service.saveWeight(kilograms: 90, on: day(12))    // before the 7-day range, inside the trend window
        try service.saveWeight(kilograms: 80, on: day(15))
        try service.saveWeight(kilograms: 80, on: day(20))
        viewModel.selectedRange = .week

        #expect(viewModel.weightPoints.count == 2)
        #expect(viewModel.weightTrend.map(\.kilograms) == [85, 80])
        #expect(viewModel.weightChange == -5)
        #expect(viewModel.showsTrendLine)
    }

    @Test func oneWeighInShowsAPointButNoLine() throws {
        let (viewModel, service) = try make(profile: profile)
        try service.saveWeight(kilograms: 80, on: day(20))
        viewModel.load()
        #expect(viewModel.weightPoints.count == 1)
        #expect(!viewModel.showsTrendLine)
        #expect(viewModel.weightChange == nil)
    }

    @Test func summaryFindsTheTouchedDay() async throws {
        let (viewModel, service) = try make(profile: profile)
        try service.saveWeight(kilograms: 79.5, on: day(18))
        try await service.saveMeal(MealDraft(timestamp: day(18, hour: 19), mealType: .dinner, items: SampleScene.sampleFoodItemDrafts()))
        viewModel.load()

        let summary = viewModel.summary(for: day(18, hour: 3))
        #expect(summary.weight?.kilograms == 79.5)
        #expect(summary.intake != nil)

        let empty = viewModel.summary(for: day(17))
        #expect(empty.weight == nil && empty.intake == nil)
    }

    @Test func deletingAWeighInUpdatesTheChart() throws {
        let (viewModel, service) = try make(profile: profile)
        try service.saveWeight(kilograms: 80, on: day(20))
        viewModel.load()
        viewModel.deleteWeight(try #require(viewModel.weightEntries.first))
        #expect(viewModel.weightPoints.isEmpty)
    }
}

@MainActor
struct RecipeBookViewModelTests {
    private let component = SavedMealComponentDraft(
        name: "Chicken",
        category: .meat,
        grams: 150,
        macrosPer100Grams: MacroNutrients(proteinGrams: 31, carbohydrateGrams: 0, fatGrams: 3.6, energyKilocalories: 165)
    )

    private func make() throws -> (RecipesViewModel, SwiftDataPersistenceService) {
        let service = try SwiftDataPersistenceService.makeInMemory()
        return (RecipesViewModel(persistence: service), service)
    }

    @Test func listsSavedMealsAlongsideSuggestions() async throws {
        let (viewModel, service) = try make()
        try await service.saveSavedMeal(SavedMealDraft(name: "Chicken plate", components: [component]))
        viewModel.load()
        #expect(viewModel.savedMeals.map(\.name) == ["Chicken plate"])
        #expect(!viewModel.recipes.isEmpty)
    }

    @Test func loggingAddsTodaysMealAndConfirms() async throws {
        let (viewModel, service) = try make()
        let saved = try await service.saveSavedMeal(SavedMealDraft(name: "Chicken plate", components: [component]))
        viewModel.load()

        await viewModel.logToday(saved)

        let meals = try service.meals(on: .now)
        #expect(meals.count == 1)
        #expect(meals.first?.savedMeal?.id == saved.id)
        #expect(viewModel.loggedConfirmation?.contains("Chicken plate") == true)
        #expect(viewModel.errorPresentation == nil)
    }

    @Test func loggingLowersTheCaloriesLeftToday() async throws {
        let (viewModel, service) = try make()
        try service.saveProfile(UserProfileDraft(weightKg: 80, heightCm: 180, birthYear: 1996, biologicalSex: .male, activityLevel: .moderate, goal: .leanBulk))
        let saved = try await service.saveSavedMeal(SavedMealDraft(name: "Chicken plate", components: [component]))
        viewModel.load()
        let before = try #require(viewModel.remainingCalories)

        await viewModel.logToday(saved)

        #expect(abs(before - (try #require(viewModel.remainingCalories)) - 247.5) < 1e-9)
    }

    @Test func deletingRemovesItFromTheBook() async throws {
        let (viewModel, service) = try make()
        let saved = try await service.saveSavedMeal(SavedMealDraft(name: "Chicken plate", components: [component]))
        viewModel.load()
        await viewModel.delete(saved)
        #expect(viewModel.savedMeals.isEmpty)
    }
}

@MainActor
struct SaveAsRecipeTests {
    private func make() async throws -> (LogViewModel, SwiftDataPersistenceService, MealEntry) {
        let service = try SwiftDataPersistenceService.makeInMemory()
        let meal = try await service.saveMeal(MealDraft(timestamp: .now, mealType: .lunch, items: SampleScene.sampleFoodItemDrafts()))
        let viewModel = LogViewModel(persistence: service)
        viewModel.load()
        return (viewModel, service, meal)
    }

    @Test func savesTheMealToTheBookAndConfirms() async throws {
        let (viewModel, service, meal) = try await make()
        await viewModel.saveAsRecipe(meal, name: "Lunch favourite")

        #expect(try service.savedMeals().map(\.name) == ["Lunch favourite"])
        #expect(viewModel.savedConfirmation?.contains("Lunch favourite") == true)
    }

    @Test func blankNameShowsAnErrorAndSavesNothing() async throws {
        let (viewModel, service, meal) = try await make()
        await viewModel.saveAsRecipe(meal, name: "   ")

        #expect(try service.savedMeals().isEmpty)
        #expect(viewModel.errorPresentation != nil)
        #expect(viewModel.savedConfirmation == nil)
    }

    @Test func suggestedNameIsUsableEvenForManyItems() async throws {
        let (viewModel, service, _) = try await make()
        let longNames = (0..<20).map { index in
            FoodItemDraft(
                id: UUID(),
                name: "A very long food item name \(index)",
                category: .other,
                portion: SampleScene.sampleFoodItemDrafts()[0].portion,
                macrosPer100Grams: SampleScene.sampleFoodItemDrafts()[0].macrosPer100Grams
            )
        }
        let meal = try await service.saveMeal(MealDraft(timestamp: .now, mealType: .dinner, items: longNames))

        let name = viewModel.suggestedRecipeName(for: meal)
        #expect(SavedMeal.validatedName(name) != nil)
    }
}

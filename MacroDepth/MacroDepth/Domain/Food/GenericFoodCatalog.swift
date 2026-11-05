// Domain/Food/GenericFoodCatalog.swift

import Foundation

/// Common whole foods, searchable in English and Swedish, with no network needed.
///
/// Open Food Facts is mostly packaged goods, so searching it for "banana" finds banana
/// products rather than bananas. These come first in search results.
///
/// Values per 100 g are from USDA FoodData Central (SR Legacy, public domain), and each
/// entry notes its FDC id. Carbohydrates are available carbs, USDA's "by difference" value
/// minus fibre, to match the app's convention.
enum GenericFoodCatalog {
    static var foods: [FoodProduct] { entries.map(\.food) }

    private struct Entry {
        let food: FoodProduct
        let words: Set<String>
    }

    private static let entries: [Entry] = [
        food("apple", "Apple / Äpple", tags: "äpple apples", .fruit, serving: 150,
             protein: 0.26, carbs: 11.41, fat: 0.17, fiber: 2.4, kcal: 52),   // FDC 171688
        food("banana", "Banana / Banan", tags: "banan bananer bananas", .fruit, serving: 120,
             protein: 1.09, carbs: 20.24, fat: 0.33, fiber: 2.6, kcal: 89),   // FDC 173944
        food("orange", "Orange / Apelsin", tags: "apelsin apelsiner oranges", .fruit, serving: 140,
             protein: 0.94, carbs: 9.35, fat: 0.12, fiber: 2.4, kcal: 47),   // FDC 169097
        food("pear", "Pear / Päron", tags: "päron pears", .fruit, serving: 150,
             protein: 0.36, carbs: 12.13, fat: 0.14, fiber: 3.1, kcal: 57),   // FDC 169118
        food("grapes", "Grapes / Vindruvor", tags: "vindruvor druvor grape", .fruit, serving: 100,
             protein: 0.72, carbs: 17.2, fat: 0.16, fiber: 0.9, kcal: 69),   // FDC 174683
        food("strawberries", "Strawberries / Jordgubbar", tags: "jordgubbar jordgubbe strawberry berries", .fruit, serving: 100,
             protein: 0.67, carbs: 5.68, fat: 0.3, fiber: 2, kcal: 32),   // FDC 167762
        food("blueberries", "Blueberries / Blåbär", tags: "blåbär blueberry berries", .fruit, serving: 75,
             protein: 0.74, carbs: 12.09, fat: 0.33, fiber: 2.4, kcal: 57),   // FDC 171711
        food("avocado", "Avocado", tags: "avokado", .fruit, serving: 70,
             protein: 2, carbs: 1.83, fat: 14.66, fiber: 6.7, kcal: 160),   // FDC 171705
        food("broccoli", "Broccoli, raw / Broccoli, rå", tags: "rå", .vegetable, serving: 100,
             protein: 2.82, carbs: 4.04, fat: 0.37, fiber: 2.6, kcal: 34),   // FDC 170379
        food("carrot", "Carrot / Morot", tags: "morot morötter carrots", .vegetable, serving: 70,
             protein: 0.93, carbs: 6.78, fat: 0.24, fiber: 2.8, kcal: 41),   // FDC 170393
        food("tomato", "Tomato / Tomat", tags: "tomat tomater tomatoes", .vegetable, serving: 100,
             protein: 0.88, carbs: 2.69, fat: 0.2, fiber: 1.2, kcal: 18),   // FDC 170457
        food("cucumber", "Cucumber / Gurka", tags: "gurka", .vegetable, serving: 80,
             protein: 0.65, carbs: 3.13, fat: 0.11, fiber: 0.5, kcal: 15),   // FDC 168409
        food("bell-pepper", "Bell pepper / Paprika", tags: "paprika red sweet peppers", .vegetable, serving: 100,
             protein: 0.99, carbs: 3.93, fat: 0.3, fiber: 2.1, kcal: 26),   // FDC 170108
        food("onion", "Onion / Lök", tags: "lök gullök onions", .vegetable, serving: 60,
             protein: 1.1, carbs: 7.64, fat: 0.1, fiber: 1.7, kcal: 40),   // FDC 170000
        food("mushrooms", "Mushrooms / Champinjoner", tags: "champinjoner champinjon svamp mushroom", .vegetable, serving: 70,
             protein: 3.09, carbs: 2.26, fat: 0.34, fiber: 1, kcal: 22),   // FDC 169251
        food("lettuce", "Lettuce / Sallad", tags: "sallad grönsallad salad green leaf", .leafyVegetable, serving: 50,
             protein: 1.36, carbs: 1.57, fat: 0.15, fiber: 1.3, kcal: 15),   // FDC 169249
        food("spinach", "Spinach / Spenat", tags: "spenat", .leafyVegetable, serving: 50,
             protein: 2.86, carbs: 1.43, fat: 0.39, fiber: 2.2, kcal: 23),   // FDC 168462
        food("potato", "Potato, boiled / Potatis, kokt", tags: "potatis kokt potatoes", .grainOrStarch, serving: 150,
             protein: 1.71, carbs: 18.21, fat: 0.1, fiber: 1.8, kcal: 86),   // FDC 170440
        food("sweet-potato", "Sweet potato, baked / Sötpotatis, ugnsbakad", tags: "sötpotatis bakad", .grainOrStarch, serving: 150,
             protein: 2.01, carbs: 17.41, fat: 0.15, fiber: 3.3, kcal: 90),   // FDC 168483
        food("white-rice-cooked", "White rice, cooked / Vitt ris, kokt", tags: "ris vitt kokt jasminris basmatiris", .grainOrStarch, serving: 180,
             protein: 2.69, carbs: 27.77, fat: 0.28, fiber: 0.4, kcal: 130),   // FDC 168878
        food("white-rice-dry", "White rice, uncooked / Vitt ris, okokt", tags: "ris vitt okokt torrt dry raw", .grainOrStarch, serving: 70,
             protein: 7.13, carbs: 78.65, fat: 0.66, fiber: 1.3, kcal: 365),   // FDC 168877
        food("brown-rice-cooked", "Brown rice, cooked / Råris, kokt", tags: "råris fullkornsris kokt", .grainOrStarch, serving: 180,
             protein: 2.74, carbs: 23.98, fat: 0.97, fiber: 1.6, kcal: 123),   // FDC 169704
        food("pasta-cooked", "Pasta, cooked / Pasta, kokt", tags: "spaghetti makaroner kokt noodles", .grainOrStarch, serving: 200,
             protein: 5.8, carbs: 29.06, fat: 0.93, fiber: 1.8, kcal: 158),   // FDC 169737
        food("pasta-dry", "Pasta, uncooked / Pasta, okokt", tags: "spaghetti makaroner okokt torr dry raw", .grainOrStarch, serving: 75,
             protein: 13.04, carbs: 71.47, fat: 1.51, fiber: 3.2, kcal: 371),   // FDC 169736
        food("oats", "Oats, dry / Havregryn, torra", tags: "havregryn havre gröt oatmeal porridge", .grainOrStarch, serving: 50,
             protein: 13.15, carbs: 57.6, fat: 6.52, fiber: 10.1, kcal: 379),   // FDC 173904
        food("quinoa", "Quinoa, cooked / Quinoa, kokt", tags: "kokt", .grainOrStarch, serving: 180,
             protein: 4.4, carbs: 18.5, fat: 1.92, fiber: 2.8, kcal: 120),   // FDC 168917
        food("wholewheat-bread", "Whole-wheat bread / Fullkornsbröd", tags: "bröd fullkornsbröd grovt", .bakedGood, serving: 40,
             protein: 12.45, carbs: 36.71, fat: 3.5, fiber: 6, kcal: 252),   // FDC 172688
        food("chicken-breast-raw", "Chicken breast, raw / Kycklingbröst, rå", tags: "kyckling kycklingbröst kycklingfilé filé rå", .meat, serving: 150,
             protein: 22.5, carbs: 0, fat: 2.62, fiber: 0, kcal: 120),   // FDC 171077
        food("chicken-breast-cooked", "Chicken breast, cooked / Kycklingbröst, tillagad", tags: "kyckling kycklingbröst kycklingfilé filé tillagad stekt roasted", .meat, serving: 125,
             protein: 31.02, carbs: 0, fat: 3.57, fiber: 0, kcal: 165),   // FDC 171477
        food("chicken-thigh-raw", "Chicken thigh, raw / Kycklinglår, rå", tags: "kyckling kycklinglår lårfilé rå", .meat, serving: 125,
             protein: 19.66, carbs: 0, fat: 4.12, fiber: 0, kcal: 121),   // FDC 173627
        food("turkey-breast", "Turkey breast, raw / Kalkonbröst, rå", tags: "kalkon kalkonbröst kalkonfilé rå", .meat, serving: 150,
             protein: 23.66, carbs: 0.14, fat: 1.48, fiber: 0, kcal: 114),   // FDC 171098
        food("beef-mince-raw", "Beef mince, 10% fat, raw / Nötfärs, 10% fett, rå", tags: "nötfärs färs köttfärs nöt rå ground", .meat, serving: 125,
             protein: 20, carbs: 0, fat: 10, fiber: 0, kcal: 176),   // FDC 174030
        food("beef-mince-cooked", "Beef mince, 10% fat, cooked / Nötfärs, 10% fett, stekt", tags: "nötfärs färs köttfärs nöt stekt ground", .meat, serving: 100,
             protein: 28.45, carbs: 0, fat: 12.04, fiber: 0, kcal: 230),   // FDC 171794
        food("beef-steak", "Beef sirloin steak, cooked / Biff, tillagad", tags: "biff nötkött entrecote stek nöt", .meat, serving: 150,
             protein: 26.96, carbs: 0, fat: 14.23, fiber: 0, kcal: 243),   // FDC 168727
        food("pork-tenderloin", "Pork tenderloin, cooked / Fläskfilé, tillagad", tags: "fläsk fläskkött fläskfilé tillagad loin", .meat, serving: 125,
             protein: 26.17, carbs: 0, fat: 3.51, fiber: 0, kcal: 143),   // FDC 168250
        food("salmon-raw", "Salmon, raw / Lax, rå", tags: "lax rå", .fish, serving: 125,
             protein: 20.42, carbs: 0, fat: 13.42, fiber: 0, kcal: 208),   // FDC 175167
        food("salmon-cooked", "Salmon, cooked / Lax, tillagad", tags: "lax tillagad ugnsbakad baked", .fish, serving: 125,
             protein: 22.1, carbs: 0, fat: 12.35, fiber: 0, kcal: 206),   // FDC 175168
        food("cod", "Cod, raw / Torsk, rå", tags: "torsk vitfisk rå", .fish, serving: 125,
             protein: 17.81, carbs: 0, fat: 0.67, fiber: 0, kcal: 82),   // FDC 171955
        food("tuna", "Tuna, canned in water / Tonfisk på burk i vatten", tags: "tonfisk burk", .fish, serving: 80,
             protein: 19.44, carbs: 0, fat: 0.96, fiber: 0, kcal: 86),   // FDC 173709
        food("shrimp", "Shrimp, cooked / Räkor, kokta", tags: "räkor räka kokta shrimps prawns", .fish, serving: 100,
             protein: 23.98, carbs: 0.2, fat: 0.28, fiber: 0, kcal: 99),   // FDC 175180
        food("egg-raw", "Egg, raw / Ägg, rått", tags: "ägg rått eggs", .egg, serving: 55,
             protein: 12.56, carbs: 0.72, fat: 9.51, fiber: 0, kcal: 143),   // FDC 171287
        food("egg-boiled", "Egg, boiled / Ägg, kokt", tags: "ägg kokt eggs hard-boiled", .egg, serving: 55,
             protein: 12.58, carbs: 1.12, fat: 10.61, fiber: 0, kcal: 155),   // FDC 173424
        food("whole-milk", "Whole milk, 3% fat / Standardmjölk, 3% fett", tags: "mjölk standardmjölk helmjölk", .dairy, serving: 250,
             protein: 3.15, carbs: 4.8, fat: 3.25, fiber: 0, kcal: 61),   // FDC 171265
        food("reduced-fat-milk", "Reduced-fat milk, 2% fat / Mellanmjölk", tags: "mjölk mellanmjölk lättmjölk semi-skimmed", .dairy, serving: 250,
             protein: 3.3, carbs: 4.8, fat: 1.98, fiber: 0, kcal: 50),   // FDC 171267
        food("greek-yogurt", "Greek yogurt, plain, nonfat / Grekisk yoghurt, naturell, fettfri", tags: "yoghurt grekisk naturell yoghurt", .dairy, serving: 170,
             protein: 10.19, carbs: 3.6, fat: 0.39, fiber: 0, kcal: 59),   // FDC 170894
        food("cottage-cheese", "Cottage cheese, 2% fat / Keso, 2% fett", tags: "keso cottage ost", .dairy, serving: 100,
             protein: 10.45, carbs: 4.76, fat: 2.27, fiber: 0, kcal: 81),   // FDC 172182
        food("cheddar", "Cheddar cheese / Cheddarost", tags: "ost cheddarost hårdost", .cheese, serving: 30,
             protein: 22.87, carbs: 3.37, fat: 33.31, fiber: 0, kcal: 403),   // FDC 173414
        food("butter", "Butter / Smör", tags: "smör", .sauceOrDressing, serving: 10,
             protein: 0.85, carbs: 0.06, fat: 81.11, fiber: 0, kcal: 717),   // FDC 173410
        food("olive-oil", "Olive oil / Olivolja", tags: "olivolja olja oil", .sauceOrDressing, serving: 10,
             protein: 0, carbs: 0, fat: 100, fiber: 0, kcal: 884),   // FDC 171413
        food("lentils", "Lentils, cooked / Linser, kokta", tags: "linser lins kokta lentil", .legume, serving: 180,
             protein: 9.02, carbs: 12.23, fat: 0.38, fiber: 7.9, kcal: 116),   // FDC 172421
        food("chickpeas", "Chickpeas, cooked / Kikärtor, kokta", tags: "kikärtor kikärta kokta chickpea garbanzo", .legume, serving: 160,
             protein: 8.86, carbs: 19.82, fat: 2.59, fiber: 7.6, kcal: 164),   // FDC 173757
        food("black-beans", "Black beans, cooked / Svarta bönor, kokta", tags: "svarta bönor böna kokta bean", .legume, serving: 170,
             protein: 8.86, carbs: 15.01, fat: 0.54, fiber: 8.7, kcal: 132),   // FDC 173735
        food("tofu", "Tofu, firm / Tofu, fast", tags: "fast", .legume, serving: 125,
             protein: 17.27, carbs: 0.48, fat: 8.72, fiber: 2.3, kcal: 144),   // FDC 172475
        food("almonds", "Almonds / Mandlar", tags: "mandel mandlar nötter almond nuts", .nutsOrSeeds, serving: 30,
             protein: 21.15, carbs: 9.05, fat: 49.93, fiber: 12.5, kcal: 579),   // FDC 170567
        food("peanut-butter", "Peanut butter / Jordnötssmör", tags: "jordnötssmör", .nutsOrSeeds, serving: 20,
             protein: 22.21, carbs: 17.31, fat: 51.36, fiber: 5, kcal: 598),   // FDC 172470
    ]

    /// Foods where every word of `query` starts a word of the name or tags, best first.
    /// Matching word starts means "ris" finds rice but not "apricot", and ignoring accents
    /// means "agg" finds "ägg".
    static func search(_ query: String) -> [FoodProduct] {
        let terms = words(in: query)
        guard !terms.isEmpty else { return [] }

        return entries.compactMap { entry -> (food: FoodProduct, exactMatches: Int)? in
            guard terms.allSatisfy({ term in entry.words.contains { $0.hasPrefix(term) } }) else { return nil }
            return (entry.food, terms.filter(entry.words.contains).count)
        }
        // Stable by catalog order within a rank: exact words beat partial ones.
        .enumerated()
        .sorted { ($0.element.exactMatches, $1.offset) > ($1.element.exactMatches, $0.offset) }
        .map(\.element.food)
    }

    // MARK: Private

    private static func food(
        _ key: String,
        _ name: String,
        tags: String,
        _ category: FoodCategory,
        serving: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double,
        kcal: Double
    ) -> Entry {
        Entry(
            food: FoodProduct(
                id: "generic-\(key)",
                name: name,
                category: category,
                macrosPer100Grams: MacroNutrients(
                    proteinGrams: protein,
                    carbohydrateGrams: carbs,
                    fatGrams: fat,
                    fiberGrams: fiber,
                    energyKilocalories: kcal
                ),
                typicalServingGrams: serving,
                isGeneric: true
            ),
            words: Set(words(in: "\(name) \(tags)"))
        )
    }

    private static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}

// Features/Recipes/RecipeCatalog.swift

import Foundation

/// The built-in recipes. Each goal has at least one recipe per meal type.
/// Quantities are raw weights unless stated otherwise.
enum RecipeCatalog {
    static let all: [RecipeSuggestion] = leanBulk + fatLoss + maintenance

    // MARK: Lean bulk

    private static let leanBulk: [RecipeSuggestion] = [
        RecipeSuggestion(
            id: "bulk-overnight-protein-oats",
            title: "Overnight Protein Oats",
            mealType: .breakfast,
            targetGoal: .leanBulk,
            estimatedCalories: 810,
            proteinG: 62,
            carbsG: 91,
            fatG: 22,
            ingredientsList: [
                "80 g rolled oats",
                "30 g whey protein",
                "250 ml semi-skimmed milk",
                "150 g Greek yogurt (2% fat)",
                "1 small banana (100 g), sliced",
                "15 g peanut butter",
            ],
            preparationInstructions: [
                "Stir the oats, whey, milk and yogurt together in a jar.",
                "Cover and refrigerate overnight.",
                "Top with the banana and peanut butter before eating.",
            ]
        ),
        RecipeSuggestion(
            id: "bulk-eggs-cottage-toast",
            title: "Eggs & Avocado on Toast",
            mealType: .breakfast,
            targetGoal: .leanBulk,
            estimatedCalories: 565,
            proteinG: 39,
            carbsG: 39,
            fatG: 28,
            ingredientsList: [
                "3 eggs",
                "2 slices wholegrain bread (80 g)",
                "50 g avocado",
                "100 g cottage cheese (4% fat)",
            ],
            preparationInstructions: [
                "Toast the bread, then spread it with the avocado and cottage cheese.",
                "Scramble or poach the eggs without added fat.",
                "Serve the eggs on the toast.",
            ]
        ),
        RecipeSuggestion(
            id: "bulk-chicken-rice-bowl",
            title: "Chicken Rice Bowl",
            mealType: .lunch,
            targetGoal: .leanBulk,
            estimatedCalories: 670,
            proteinG: 58,
            carbsG: 76,
            fatG: 15,
            ingredientsList: [
                "200 g chicken breast",
                "90 g white rice (dry weight)",
                "150 g broccoli",
                "1 tbsp olive oil (10 g)",
                "1 tbsp soy sauce",
            ],
            preparationInstructions: [
                "Cook the rice according to the packet.",
                "Slice the chicken and fry it in the olive oil until cooked through.",
                "Steam the broccoli, then serve everything in a bowl with the soy sauce.",
            ]
        ),
        RecipeSuggestion(
            id: "bulk-beef-sweet-potato",
            title: "Beef & Sweet Potato Skillet",
            mealType: .dinner,
            targetGoal: .leanBulk,
            estimatedCalories: 645,
            proteinG: 46,
            carbsG: 59,
            fatG: 25,
            ingredientsList: [
                "200 g beef mince (10% fat)",
                "300 g sweet potato, diced",
                "100 g bell pepper, sliced",
                "1 tsp olive oil (5 g)",
                "Paprika, cumin and salt",
            ],
            preparationInstructions: [
                "Fry the sweet potato in the oil, covered, for 12 minutes until tender.",
                "Add the mince and spices and brown thoroughly.",
                "Stir in the pepper and cook for 3 more minutes.",
            ]
        ),
        RecipeSuggestion(
            id: "bulk-salmon-pasta",
            title: "Salmon & Spinach Pasta",
            mealType: .dinner,
            targetGoal: .leanBulk,
            estimatedCalories: 680,
            proteinG: 44,
            carbsG: 65,
            fatG: 27,
            ingredientsList: [
                "150 g salmon fillet",
                "100 g wholewheat pasta (dry weight)",
                "100 g cherry tomatoes, halved",
                "50 g spinach",
                "30 g light crème fraîche",
            ],
            preparationInstructions: [
                "Boil the pasta, saving a splash of the water when you drain it.",
                "Pan-fry the salmon for 4 minutes per side, then flake it.",
                "Soften the tomatoes and spinach, then toss with the pasta, salmon and crème fraîche.",
            ]
        ),
        RecipeSuggestion(
            id: "bulk-cottage-cheese-bagel",
            title: "Cottage Cheese & Honey Bagel",
            mealType: .snack,
            targetGoal: .leanBulk,
            estimatedCalories: 525,
            proteinG: 29,
            carbsG: 64,
            fatG: 17,
            ingredientsList: [
                "1 bagel (90 g)",
                "150 g cottage cheese (4% fat)",
                "15 g honey",
                "15 g walnuts, chopped",
            ],
            preparationInstructions: [
                "Toast the bagel.",
                "Spread with the cottage cheese, then top with the walnuts and honey.",
            ]
        ),
    ]

    // MARK: Fat loss

    private static let fatLoss: [RecipeSuggestion] = [
        RecipeSuggestion(
            id: "cut-egg-white-scramble",
            title: "Egg White & Spinach Scramble",
            mealType: .breakfast,
            targetGoal: .fatLoss,
            estimatedCalories: 305,
            proteinG: 33,
            carbsG: 18,
            fatG: 11,
            ingredientsList: [
                "200 g egg whites",
                "1 whole egg",
                "100 g spinach",
                "1 slice rye bread (35 g)",
                "1 tsp olive oil (5 g)",
            ],
            preparationInstructions: [
                "Wilt the spinach in the oil over medium heat.",
                "Add the egg whites and egg, stirring gently until just set.",
                "Serve with the toasted rye bread.",
            ]
        ),
        RecipeSuggestion(
            id: "cut-lean-protein-oats",
            title: "Lean Overnight Protein Oats",
            mealType: .breakfast,
            targetGoal: .fatLoss,
            estimatedCalories: 360,
            proteinG: 42,
            carbsG: 39,
            fatG: 4,
            ingredientsList: [
                "40 g rolled oats",
                "25 g whey protein",
                "150 g fat-free quark or skyr",
                "100 ml water",
                "100 g mixed berries",
            ],
            preparationInstructions: [
                "Stir the oats, whey, quark and water together in a jar.",
                "Cover and refrigerate overnight.",
                "Top with the berries before eating.",
            ]
        ),
        RecipeSuggestion(
            id: "cut-chicken-cauliflower-bowl",
            title: "Chicken & Cauliflower Rice Bowl",
            mealType: .lunch,
            targetGoal: .fatLoss,
            estimatedCalories: 415,
            proteinG: 48,
            carbsG: 33,
            fatG: 10,
            ingredientsList: [
                "180 g chicken breast",
                "200 g cauliflower, grated",
                "30 g brown rice (dry weight)",
                "100 g bell pepper, sliced",
                "1 tsp olive oil (5 g)",
            ],
            preparationInstructions: [
                "Cook the rice according to the packet.",
                "Fry the sliced chicken and pepper in the oil until the chicken is cooked through.",
                "Stir-fry the cauliflower for 4 minutes, then combine everything in a bowl.",
            ]
        ),
        RecipeSuggestion(
            id: "cut-cod-potatoes-greens",
            title: "Baked Cod with Potatoes & Greens",
            mealType: .dinner,
            targetGoal: .fatLoss,
            estimatedCalories: 390,
            proteinG: 43,
            carbsG: 39,
            fatG: 7,
            ingredientsList: [
                "200 g cod fillet",
                "200 g potatoes",
                "150 g green beans",
                "1 tsp olive oil (5 g)",
                "Lemon, salt and pepper",
            ],
            preparationInstructions: [
                "Boil the potatoes for 15–20 minutes until tender.",
                "Brush the cod with the oil, season, and bake at 200 °C for 12 minutes.",
                "Steam the beans for 4 minutes and serve everything with lemon.",
            ]
        ),
        RecipeSuggestion(
            id: "cut-turkey-chilli",
            title: "Turkey & Bean Chilli",
            mealType: .dinner,
            targetGoal: .fatLoss,
            estimatedCalories: 375,
            proteinG: 43,
            carbsG: 26,
            fatG: 11,
            ingredientsList: [
                "150 g lean turkey mince (7% fat)",
                "100 g canned kidney beans, drained",
                "200 g canned chopped tomatoes",
                "1 small onion, diced",
                "Chilli powder, cumin and garlic",
            ],
            preparationInstructions: [
                "Brown the turkey and onion in a dry non-stick pan.",
                "Add the spices, tomatoes and beans.",
                "Simmer for 15 minutes until thickened.",
            ]
        ),
        RecipeSuggestion(
            id: "cut-cottage-cheese-berries",
            title: "Cottage Cheese & Berries",
            mealType: .snack,
            targetGoal: .fatLoss,
            estimatedCalories: 225,
            proteinG: 25,
            carbsG: 13,
            fatG: 8,
            ingredientsList: [
                "200 g cottage cheese (4% fat)",
                "75 g mixed berries",
            ],
            preparationInstructions: [
                "Spoon the cottage cheese into a bowl and top with the berries.",
            ]
        ),
    ]

    // MARK: Maintenance

    private static let maintenance: [RecipeSuggestion] = [
        RecipeSuggestion(
            id: "maintain-yogurt-granola",
            title: "Greek Yogurt & Granola Bowl",
            mealType: .breakfast,
            targetGoal: .maintenance,
            estimatedCalories: 390,
            proteinG: 30,
            carbsG: 43,
            fatG: 11,
            ingredientsList: [
                "250 g Greek yogurt (2% fat)",
                "40 g granola",
                "100 g mixed berries",
            ],
            preparationInstructions: [
                "Spoon the yogurt into a bowl and top with the granola and berries.",
            ]
        ),
        RecipeSuggestion(
            id: "maintain-tuna-bean-salad",
            title: "Tuna & White Bean Salad",
            mealType: .lunch,
            targetGoal: .maintenance,
            estimatedCalories: 505,
            proteinG: 45,
            carbsG: 52,
            fatG: 13,
            ingredientsList: [
                "120 g canned tuna in water, drained",
                "150 g canned white beans, drained",
                "100 g tomatoes and cucumber, chopped",
                "2 tsp olive oil (10 g)",
                "60 g crusty bread",
            ],
            preparationInstructions: [
                "Toss the tuna, beans and vegetables with the oil.",
                "Season and serve with the bread.",
            ]
        ),
        RecipeSuggestion(
            id: "maintain-pork-noodles",
            title: "Pork & Vegetable Noodle Stir-Fry",
            mealType: .dinner,
            targetGoal: .maintenance,
            estimatedCalories: 570,
            proteinG: 45,
            carbsG: 62,
            fatG: 16,
            ingredientsList: [
                "150 g pork tenderloin, sliced",
                "70 g egg noodles (dry weight)",
                "200 g stir-fry vegetables",
                "2 tsp sesame oil (10 g)",
                "1 tbsp soy sauce",
            ],
            preparationInstructions: [
                "Cook the noodles according to the packet and drain.",
                "Stir-fry the pork in the oil for 4 minutes, then add the vegetables for 3 minutes.",
                "Toss in the noodles and soy sauce.",
            ]
        ),
        RecipeSuggestion(
            id: "maintain-skyr-apple",
            title: "Skyr with Apple & Almonds",
            mealType: .snack,
            targetGoal: .maintenance,
            estimatedCalories: 280,
            proteinG: 25,
            carbsG: 27,
            fatG: 8,
            ingredientsList: [
                "200 g plain skyr",
                "1 apple (150 g), chopped",
                "15 g almonds",
            ],
            preparationInstructions: [
                "Top the skyr with the apple and almonds.",
            ]
        ),
    ]
}

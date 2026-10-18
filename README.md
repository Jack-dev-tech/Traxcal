# Traxcal

An iOS 26 calorie and nutrition tracker. It has AI meal scanning, one search across every restaurant and food database, Apple Health sync, Home Screen widgets, and a Chipotle bowl builder. The UI uses Liquid Glass, spring animations and haptics.

## Features

| Area | What it does |
| --- | --- |
| **Dashboard** | An animated calorie ring that adds Health's active energy to your budget. It also shows macro bars, a water tracker, micronutrient gauges, AI trend cards, a weekly chart you can scrub, today's meals and quick re-add. |
| **Universal search** | One search bar covers USDA FoodData Central, Open Food Facts and bundled menus from 25+ chains (McDonald's, Chipotle, Shake Shack, Chick-fil-A, Taco Bell, Starbucks, In-N-Out, Panda Express, Sweetgreen, Cava and more). Results aren't split by restaurant. Live results rank first, and bundled data fills gaps and covers offline use. Matching tolerates typos and aliases ("mcd nuggets", "chik fil a"). |
| **Chipotle builder** | Build a bowl, burrito, salad, tacos or quesadilla from individual ingredients. Each ingredient can be light, normal, extra or double. Totals update live, there are popular presets, and you can save a build as a favorite. Presets also show up in search. |
| **AI food scan** | Take or pick a photo. The AI finds each item and estimates portions, then you review it: change portions with a slider, edit numbers, remove items, and log items separately or as one meal. You can also type a description ("2 eggs and toast"). |
| **AI providers** | **On-device:** MLX models (Gemma 3/4, Qwen2.5-VL, Qwen3-VL, SmolVLM, Qwen3) that you download in the app. Traxcal recommends one based on your iPhone's RAM. **Apple Intelligence:** Apple's Foundation Models. **Cloud, with your own key:** OpenAI, Anthropic, Gemini, DeepSeek, Qwen (DashScope), xAI, Mistral, Groq, OpenRouter, or any OpenAI-compatible server (Ollama, LM Studio). Models that can't take images fall back to Vision's on-device image classifier. |
| **Nutrients** | Calories, protein, carbs, fat, fiber, sugar, saturated fat, cholesterol, sodium, potassium, calcium, iron, vitamin C, vitamin D and caffeine, each with its own daily goal. |
| **History** | All entries grouped by day, with a 30-day strip, a filter and swipe actions (edit, delete, log again). The full edit sheet covers name, meal, time, servings, every nutrient and notes. Edits update Apple Health. |
| **Trends** | 7/30/90-day charts for calories, stacked macros, macro calorie split and any single nutrient against its goal. Also shows streaks, on-target days, week-over-week change and AI insights. |
| **Apple Health** | Each entry is written as a HealthKit food correlation with a sync identifier, so editing an entry replaces its samples and deleting an entry removes them. Water is synced too. Traxcal reads active energy and weight. |
| **Widgets** | Small, medium and large Home Screen widgets, plus Lock Screen circular, rectangular and inline widgets. A "+250 ml water" button works from the widget itself (App Intent), and logging water is also a Shortcut. |

## Getting started

Requirements: Xcode 26 or later and an iPhone on iOS 26 or later.

```bash
brew install xcodegen
xcodegen            # generates Traxcal.xcodeproj from project.yml
open Traxcal.xcodeproj
```

1. Choose your team under **Signing & Capabilities** for the **Traxcal** and **TraxcalWidgets** targets. HealthKit and App Groups need a signed build. If you change the bundle ID prefix, change the App Group in `project.yml` and `Shared/SharedStore.swift` (`group.com.traxcal.shared`) to match.
2. When Xcode asks, approve the Swift macros from `mlx-swift-lm` with **Trust & Enable**.
3. Build and run with ⌘R. Run the tests with ⌘U.

> On-device MLX models need a real iPhone because they run on the GPU through Metal. The rest of the app works in the Simulator.

## Architecture

```
project.yml                 XcodeGen spec: app, widget extension, unit tests, SPM packages
Shared/                     Compiled into the app and the widget: App Group store, widget snapshot, water, App Intent
Traxcal/
  App/                      App entry, custom animated tab bar and quick-action menu, deep links
  DesignSystem/             Palette, Liquid Glass cards, rings, bars, haptics, aurora mesh background
  Models/                   SwiftData models (FoodEntry, FavoriteFood, InsightRecord), Nutrients, goals and TDEE
  Services/
    Nutrition/              Universal search (USDA + Open Food Facts + bundled), ranking, Chipotle menu
    AI/                     Provider protocol, cloud providers, MLX + Apple Intelligence, model catalog, router, Keychain
    Health/                 HealthKit read/write
    Insights/               Trend statistics, rule-based insights, AI coach
    FoodLogger.swift        Single path for log/edit/delete → SwiftData + HealthKit + widgets
  Features/                 Dashboard, Log (search/detail/quick add/barcode/describe), Scan, Chipotle, History, Trends, Settings, Onboarding
  Resources/                restaurants.json, chipotle.json, generic_foods.json, assets
TraxcalWidgets/             WidgetKit extension
TraxcalTests/               Swift Testing suites (math, datasets, search ranking, Chipotle totals, AI JSON parsing, trends)
```

### Data sources

* **USDA FoodData Central**: free. If you don't add a key in Settings, Traxcal uses the shared, rate-limited `DEMO_KEY`. Free key: <https://fdc.nal.usda.gov/api-key-signup>
* **Open Food Facts**: free, no key. Used for search and barcode lookup.
* **Bundled JSON**: `Traxcal/Resources/*.json`. Values are approximations of publicly posted restaurant nutrition. Edit these files to add chains or menu items. The compact format is documented in each file's `note`.

### On-device model recommendations

| iPhone RAM | Tier | Default recommendation |
| --- | --- | --- |
| ≤ 4 GB | Compact | SmolVLM2 500M (vision), Gemma 3 1B / Qwen3 1.7B (text) |
| 6 GB | Standard | Qwen2.5-VL 3B |
| 8 GB | Pro | Gemma 3 4B |
| 12 GB+ | Max | Gemma 4 E4B |

Models download from Hugging Face (`mlx-community`) into the app's Caches folder, and you can delete them from Settings → AI. The app requests the `increased-memory-limit` entitlement so it can run larger models.

### Privacy

API keys are stored in the Keychain. On-device and Apple Intelligence modes never send food photos off the phone. In cloud mode, photos and descriptions go only to the provider you chose.

## Disclaimer

Nutrition values from restaurants and from AI are estimates. Traxcal is not a medical device.

import SwiftUI

/// Build a Chipotle bowl, burrito, salad, tacos or quesadilla ingredient by ingredient with
/// live macro totals. Tap an ingredient to add it; tap its portion pill to cycle light/normal/extra/double.
struct ChipotleBuilderView: View {
    var onDone: () -> Void

    @Environment(FoodLogger.self) private var logger
    @State private var entree: ChipotleMenu.Entree?
    @State private var selections: [String: ChipotleMenu.Portion] = [:]
    @State private var softTacos = false
    @State private var meal: MealType = .suggested()
    @State private var changeTick = 0
    @State private var savedFavorite = false

    private let menu = BundledFoodProvider.shared.chipotle
    private let chipotleRed = Color(red: 0.75, green: 0.25, blue: 0.15)

    var body: some View {
        if let menu {
            content(menu)
        } else {
            ContentUnavailableView("Menu unavailable", systemImage: "exclamationmark.triangle")
        }
    }

    private func content(_ menu: ChipotleMenu) -> some View {
        let current = entree ?? menu.entrees[0]
        let baseOverride = current.id == "tacos" && softTacos ? "soft-flour-tortillas" : nil
        let total = menu.total(entree: current, baseOverride: baseOverride, selections: selections)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                totalsHeader(total)

                Text("Entrée").font(.headline)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(menu.entrees) { e in
                            Button {
                                withAnimation(Theme.bouncy) { entree = e }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: UIImage(systemName: e.symbol) == nil ? "takeoutbag.and.cup.and.straw.fill" : e.symbol)
                                        .font(.title2)
                                    Text(e.name).font(.caption.weight(.semibold))
                                }
                                .frame(width: 96, height: 76)
                                .foregroundStyle(current.id == e.id ? .white : .secondary)
                                .glassEffect(current.id == e.id ? Glass.regular.tint(chipotleRed.opacity(0.7)).interactive() : Glass.regular.interactive(),
                                             in: .rect(cornerRadius: 18))
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .sensoryFeedback(.selection, trigger: entree)

                if current.id == "tacos" {
                    Picker("Tortillas", selection: $softTacos) {
                        Text("Crispy Corn").tag(false)
                        Text("Soft Flour").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                presets(menu)

                ForEach(menu.visibleCategories) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(category.name).font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(category.items) { ingredient in
                                IngredientChip(
                                    ingredient: ingredient, portion: selections[ingredient.id], accent: chipotleRed,
                                    onTap: { toggle(ingredient) }, onCyclePortion: { cycle(ingredient) }
                                )
                            }
                        }
                    }
                }

                Picker("Meal", selection: $meal) {
                    ForEach(MealType.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Text("Values are approximations of Chipotle's published nutrition. Portions vary by restaurant.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("Chipotle Builder")
        .sensoryFeedback(.impact(weight: .light), trigger: changeTick)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    logger.toggleFavorite(item(total: total, entree: current, menu: menu))
                    savedFavorite = true
                    Haptics.success()
                } label: {
                    Image(systemName: savedFavorite ? "star.fill" : "star")
                        .font(.title3.weight(.bold))
                        .frame(width: 54, height: 54)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .symbolEffect(.bounce, value: savedFavorite)
                }
                .buttonStyle(.pressable)
                .disabled(selections.isEmpty)

                PrimaryButton(title: "Log \(Int(total.calories.rounded())) kcal", symbol: "flame.fill", color: chipotleRed) {
                    logger.log(item(total: total, entree: current, menu: menu), servings: 1, meal: meal)
                    Haptics.celebrate()
                    onDone()
                }
                .disabled(selections.isEmpty && current.base == nil)
            }
            .padding()
        }
    }

    private func totalsHeader(_ total: Nutrients) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(total.calories.rounded()))")
                    .font(.display(44))
                    .contentTransition(.numericText(value: total.calories))
                Text("calories").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Spacer()
            MiniRing(title: "Protein", value: total.protein, goal: max(total.protein, 60), color: Palette.protein)
            MiniRing(title: "Carbs", value: total.carbs, goal: max(total.carbs, 120), color: Palette.carbs)
            MiniRing(title: "Fat", value: total.fat, goal: max(total.fat, 50), color: Palette.fat)
        }
        .animation(Theme.spring, value: total)
        .glassCard(tint: chipotleRed)
    }

    private func presets(_ menu: ChipotleMenu) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Popular Orders").font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(menu.presets, id: \.name) { preset in
                        Button {
                            apply(preset, menu: menu)
                        } label: {
                            Text(preset.name).font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func apply(_ preset: ChipotleMenu.Preset, menu: ChipotleMenu) {
        withAnimation(Theme.spring) {
            entree = menu.entrees.first { $0.id == preset.entree }
            var next: [String: ChipotleMenu.Portion] = [:]
            for id in preset.items { next[id] = next[id] == nil ? .normal : .double }
            selections = next
        }
        changeTick += 1
    }

    private func toggle(_ ingredient: ChipotleMenu.Ingredient) {
        withAnimation(Theme.bouncy) {
            if selections[ingredient.id] == nil { selections[ingredient.id] = .normal } else { selections[ingredient.id] = nil }
        }
        savedFavorite = false
        changeTick += 1
    }

    private func cycle(_ ingredient: ChipotleMenu.Ingredient) {
        let all = ChipotleMenu.Portion.allCases
        guard let current = selections[ingredient.id], let i = all.firstIndex(of: current) else { return }
        withAnimation(Theme.bouncy) { selections[ingredient.id] = all[(i + 1) % all.count] }
        changeTick += 1
    }

    private func item(total: Nutrients, entree: ChipotleMenu.Entree, menu: ChipotleMenu) -> FoodItem {
        let parts = selections
            .sorted { $0.key < $1.key }
            .compactMap { id, portion -> String? in
                guard let name = menu.ingredient(id)?.name else { return nil }
                return portion == .normal ? name : "\(portion.title) \(name)"
            }
        let protein = selections.keys.compactMap { id in
            menu.categories.first { $0.id == "protein" }?.items.first { $0.id == id }?.name
        }.first
        let name = [protein, entree.name].compactMap { $0 }.joined(separator: " ")
        return FoodItem(
            id: "chipotle-custom-\(parts.joined().slug)", name: name, brand: "Chipotle", source: .chipotle,
            servingDescription: parts.isEmpty ? "1 \(entree.name.lowercased())" : parts.joined(separator: ", "),
            servingGrams: nil, nutrients: total, keywords: ["chipotle"]
        )
    }
}

private struct IngredientChip: View {
    var ingredient: ChipotleMenu.Ingredient
    var portion: ChipotleMenu.Portion?
    var accent: Color
    var onTap: () -> Void
    var onCyclePortion: () -> Void

    var body: some View {
        let selected = portion != nil
        HStack(spacing: 6) {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ingredient.name).font(.subheadline.weight(.semibold))
                        Text("\(Int((ingredient.nutrients.calories * (portion?.multiplier ?? 1)).rounded())) cal · P\(Int(ingredient.nutrients.protein * (portion?.multiplier ?? 1)))")
                            .font(.caption2).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
            }
            .buttonStyle(.plain)

            if let portion {
                Button(action: onCyclePortion) {
                    Text(portion == .double ? "2×" : portion.title)
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(accent, in: .capsule)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .buttonStyle(.pressable)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(selected ? Glass.regular.tint(accent.opacity(0.45)).interactive() : Glass.regular.interactive(), in: .capsule)
        .scaleEffect(selected ? 1.02 : 1)
        .animation(Theme.bouncy, value: portion)
    }
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

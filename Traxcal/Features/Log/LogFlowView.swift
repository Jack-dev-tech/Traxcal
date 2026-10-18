import SwiftData
import SwiftUI

/// The sheet behind the + button. Hosts universal search and routes to every logging method.
struct LogFlowView: View {
    var initial: LogAction

    @Environment(\.dismiss) private var dismiss
    @Environment(FoodLogger.self) private var logger
    @State private var search = FoodSearchService()
    @State private var selected: FoodItem?
    @State private var route: LogAction?
    @Query(sort: \FavoriteFood.addedAt, order: .reverse) private var favorites: [FavoriteFood]
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    actionStrip
                    if search.query.trimmingCharacters(in: .whitespaces).count < 2 {
                        idleContent
                    } else {
                        resultsContent
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AuroraBackground(accent: Palette.calories).opacity(0.6))
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search any food or restaurant")
            .searchFocused($searchFocused)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .sheet(item: $selected) { item in
                FoodDetailView(item: item) { dismiss() }
            }
            .navigationDestination(item: $route) { action in
                destination(action)
            }
            .onAppear {
                if initial == .search { searchFocused = true } else { route = initial }
            }
        }
    }

    @ViewBuilder
    private func destination(_ action: LogAction) -> some View {
        switch action {
        case .scan: ScanMealView { dismiss() }
        case .describe: DescribeMealView { dismiss() }
        case .barcode: BarcodeLookupView { dismiss() }
        case .chipotle: ChipotleBuilderView { dismiss() }
        case .quickAdd: QuickAddView { dismiss() }
        case .search: EmptyView()
        }
    }

    private var actionStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                chip(.scan, "Scan Meal", "camera.viewfinder", Palette.fat)
                chip(.chipotle, "Chipotle Bowl", "flame.fill", Color(red: 0.75, green: 0.25, blue: 0.15))
                chip(.barcode, "Barcode", "barcode.viewfinder", Palette.water)
                chip(.describe, "Describe", "text.bubble.fill", Palette.protein)
                chip(.quickAdd, "Quick Add", "bolt.fill", Palette.carbs)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ action: LogAction, _ title: String, _ symbol: String, _ color: Color) -> some View {
        Button {
            Haptics.tap()
            route = action
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(color.opacity(0.25)).interactive(), in: .capsule)
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder
    private var idleContent: some View {
        if !favorites.isEmpty {
            SectionTitle(title: "Favorites", symbol: "star.fill")
            VStack(spacing: 8) {
                ForEach(favorites) { fav in
                    FoodResultRow(item: fav.item).onTapGesture { selected = fav.item }
                }
            }
        }
        let recents = logger.recentItems(limit: 15)
        if !recents.isEmpty {
            SectionTitle(title: "Recent", symbol: "clock")
            VStack(spacing: 8) {
                ForEach(recents) { item in
                    FoodResultRow(item: item).onTapGesture { selected = item }
                }
            }
        }
        if favorites.isEmpty && recents.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(Palette.calories)
                Text("One search for everything").font(.headline)
                Text("Try \"big mac\", \"chipotle chicken bowl\", \"shackburger\", \"greek yogurt\" or a brand name.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        HStack {
            Text("\(search.results.count) results").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if search.isSearching {
                ProgressView().controlSize(.small)
                Text("Searching databases…").font(.caption).foregroundStyle(.secondary)
            } else if search.liveUnavailable {
                Label("Offline results", systemImage: "wifi.slash").font(.caption).foregroundStyle(.secondary)
            }
        }
        LazyVStack(spacing: 8) {
            ForEach(Array(search.results.enumerated()), id: \.element.id) { index, item in
                FoodResultRow(item: item)
                    .onTapGesture { Haptics.tap(); selected = item }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(Theme.spring.delay(Double(min(index, 10)) * 0.02), value: search.results)
            }
        }
        if !search.isSearching && search.results.isEmpty {
            VStack(spacing: 10) {
                Text("No matches").font(.headline)
                Button("Describe it to AI instead") { route = .describe }
                Button("Quick add calories") { route = .quickAdd }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
        }
    }
}

struct FoodResultRow: View {
    var item: FoodItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    if let brand = item.brand { Text(brand).font(.caption.weight(.semibold)).foregroundStyle(Palette.calories) }
                    Text(item.servingDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    SourceBadge(source: item.source)
                    MacroLine(nutrients: item.nutrients)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(item.nutrients.calories.rounded()))").font(.title3.weight(.bold).monospacedDigit())
                Text("kcal").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .contentShape(.rect)
    }
}

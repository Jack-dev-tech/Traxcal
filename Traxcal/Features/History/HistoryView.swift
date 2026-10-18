import SwiftData
import SwiftUI

/// Every logged food, grouped by day, with a scrubbable date strip, search, edit and delete.
struct HistoryView: View {
    @Environment(FoodLogger.self) private var logger
    @Environment(GoalStore.self) private var goals
    @Query(sort: \FoodEntry.date, order: .reverse) private var entries: [FoodEntry]
    @State private var selectedDay: Date?
    @State private var filter = ""
    @State private var editing: FoodEntry?
    @State private var pendingDelete: FoodEntry?

    private var filtered: [FoodEntry] {
        entries.filter { entry in
            (selectedDay == nil || Calendar.current.isDate(entry.date, inSameDayAs: selectedDay!))
                && (filter.isEmpty || entry.displayName.localizedCaseInsensitiveContains(filter))
        }
    }

    private var grouped: [(day: Date, items: [FoodEntry])] {
        Dictionary(grouping: filtered) { $0.date.startOfDay }
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DayStrip(selected: $selectedDay, entries: entries, goal: goals.goal(.calories))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if grouped.isEmpty {
                    ContentUnavailableView(
                        entries.isEmpty ? "No history yet" : "Nothing here",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(entries.isEmpty ? "Foods you log appear here. Everything is editable." : "Try another day or search.")
                    )
                    .listRowBackground(Color.clear)
                }

                ForEach(grouped, id: \.day) { group in
                    Section {
                        ForEach(group.items) { entry in
                            EntryRow(entry: entry)
                                .contentShape(.rect)
                                .onTapGesture { editing = entry }
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        withAnimation { logger.delete(entry) }
                                        Haptics.warning()
                                    }
                                    Button("Edit", systemImage: "pencil") { editing = entry }.tint(Palette.fat)
                                }
                                .swipeActions(edge: .leading) {
                                    Button("Log Again", systemImage: "arrow.clockwise") {
                                        logger.duplicate(entry)
                                        Haptics.success()
                                    }
                                    .tint(Palette.protein)
                                }
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = entry }
                                    Button("Log Again Now", systemImage: "arrow.clockwise") { logger.duplicate(entry) }
                                    Button("Add to Favorites", systemImage: "star") { logger.toggleFavorite(entry.asFoodItem) }
                                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = entry }
                                }
                                .listRowBackground(Color.white.opacity(0.04))
                        }
                    } header: {
                        dayHeader(group.day, items: group.items)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("History")
            .searchable(text: $filter, prompt: "Filter foods")
            .toolbar {
                if selectedDay != nil {
                    Button("All Days") { withAnimation { selectedDay = nil } }
                }
            }
            .sheet(item: $editing) { EditEntryView(entry: $0) }
            .confirmationDialog("Delete this entry?", isPresented: .init(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    if let e = pendingDelete { withAnimation { logger.delete(e) } }
                    pendingDelete = nil
                }
            }
            .animation(Theme.spring, value: selectedDay)
        }
    }

    private func dayHeader(_ day: Date, items: [FoodEntry]) -> some View {
        let total = items.map(\.total).sum()
        return HStack {
            Text(dayTitle(day)).font(.headline).foregroundStyle(.primary)
            Spacer()
            Text("\(Int(total.calories)) kcal").font(.subheadline.weight(.bold).monospacedDigit())
            MacroLine(nutrients: total)
        }
        .textCase(nil)
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}

/// Horizontal strip of the last 30 days with mini calorie bars; tap to filter.
private struct DayStrip: View {
    @Binding var selected: Date?
    var entries: [FoodEntry]
    var goal: Double

    var body: some View {
        let totals = Dictionary(grouping: entries) { $0.date.startOfDay }.mapValues { $0.map(\.total.calories).reduce(0, +) }
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach((0..<30).reversed(), id: \.self) { offset in
                        let day = Date.now.adding(days: -offset).startOfDay
                        let cal = totals[day] ?? 0
                        let isSelected = selected.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
                        Button {
                            withAnimation(Theme.bouncy) { selected = isSelected ? nil : day }
                        } label: {
                            VStack(spacing: 6) {
                                Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                ZStack(alignment: .bottom) {
                                    Capsule().fill(.white.opacity(0.08)).frame(width: 10, height: 44)
                                    Capsule()
                                        .fill(cal > goal * 1.1 ? Palette.warning : Palette.calories)
                                        .frame(width: 10, height: 44 * min(cal / max(goal, 1), 1))
                                }
                                Text(day.formatted(.dateTime.day())).font(.caption.weight(.semibold).monospacedDigit())
                            }
                            .frame(width: 40)
                            .padding(.vertical, 8)
                            .background(isSelected ? Palette.calories.opacity(0.22) : .clear, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.pressable)
                        .id(offset)
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
            .sensoryFeedback(.selection, trigger: selected)
            .onAppear { proxy.scrollTo(0, anchor: .trailing) }
        }
    }
}

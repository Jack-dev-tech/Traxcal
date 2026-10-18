import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today, history, trends, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .history: "History"
        case .trends: "Trends"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: "circle.dashed.inset.filled"
        case .history: "clock.arrow.circlepath"
        case .trends: "chart.xyaxis.line"
        case .settings: "slider.horizontal.3"
        }
    }
}

/// Quick actions offered from the center "+" button.
enum LogAction: String, Identifiable {
    case search, scan, describe, barcode, chipotle, quickAdd
    var id: String { rawValue }
}

struct RootView: View {
    @Environment(GoalStore.self) private var goals
    @State private var tab: AppTab = .today
    @State private var logAction: LogAction?
    @State private var showActions = false
    @Namespace private var tabNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .today: DashboardView(onLog: { logAction = $0 })
                case .history: HistoryView()
                case .trends: TrendsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))

            if showActions {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(Theme.bouncy) { showActions = false } }
                    .transition(.opacity)
                QuickActionFan { action in
                    withAnimation(Theme.bouncy) { showActions = false }
                    logAction = action
                }
                .padding(.bottom, 110)
                .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }

            tabBar
        }
        .background(AuroraBackground().opacity(0.9))
        .onOpenURL { url in
            // Deep links from widgets: traxcal://today, traxcal://trends, traxcal://log
            switch url.host {
            case "trends": tab = .trends
            case "history": tab = .history
            case "log": logAction = .search
            case "scan": logAction = .scan
            default: tab = .today
            }
        }
        .sheet(item: $logAction) { action in
            LogFlowView(initial: action)
        }
        .fullScreenCover(isPresented: .init(get: { !goals.hasOnboarded }, set: { _ in })) {
            OnboardingView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.today)
            tabButton(.history)
            addButton
            tabButton(.trends)
            tabButton(.settings)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
    }

    private func tabButton(_ item: AppTab) -> some View {
        Button {
            guard tab != item else { return }
            withAnimation(Theme.spring) { tab = item }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolEffect(.bounce, value: tab == item)
                Text(item.title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(tab == item ? Palette.calories : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if tab == item {
                    Capsule()
                        .fill(Palette.calories.opacity(0.16))
                        .matchedGeometryEffect(id: "tab", in: tabNamespace)
                }
            }
        }
        .buttonStyle(.pressable)
        .sensoryFeedback(.selection, trigger: tab)
    }

    private var addButton: some View {
        Button {
            withAnimation(Theme.bouncy) { showActions.toggle() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.black)
                .rotationEffect(.degrees(showActions ? 45 : 0))
                .frame(width: 58, height: 58)
                .background(
                    LinearGradient(colors: [Palette.calories, Palette.carbs], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .circle
                )
                .shadow(color: Palette.calories.opacity(0.6), radius: 12, y: 4)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .sensoryFeedback(.impact(weight: .medium), trigger: showActions)
        .padding(.horizontal, 6)
        .offset(y: -10)
    }
}

/// Radial menu of logging options that springs out of the + button.
private struct QuickActionFan: View {
    var onSelect: (LogAction) -> Void
    @State private var appeared = false

    private let actions: [(LogAction, String, String, Color)] = [
        (.scan, "Scan Meal", "camera.viewfinder", Palette.fat),
        (.search, "Search", "magnifyingglass", Palette.calories),
        (.barcode, "Barcode", "barcode.viewfinder", Palette.water),
        (.chipotle, "Chipotle", "flame.fill", Color(red: 0.75, green: 0.25, blue: 0.15)),
        (.describe, "Describe", "text.bubble.fill", Palette.protein),
        (.quickAdd, "Quick Add", "bolt.fill", Palette.carbs),
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                Button { onSelect(action.0) } label: {
                    VStack(spacing: 8) {
                        Image(systemName: action.2)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(action.3)
                            .frame(width: 58, height: 58)
                            .glassEffect(.regular.tint(action.3.opacity(0.25)).interactive(), in: .circle)
                        Text(action.1).font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.pressable)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)
                .animation(Theme.bouncy.delay(Double(index) * 0.035), value: appeared)
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, 28)
        .onAppear { appeared = true }
    }
}

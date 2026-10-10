import SwiftUI
import SwiftData
import KopilkaCore

/// Куда ведут переходы с главной. Экран «Все лимиты» (задача 15) пока заглушка.
enum HomeDestination: Hashable {
    case limits, review
}

/// Главная (спека §8): сколько можно потратить до конца периода, полоса бюджета, остатки, главные лимиты.
/// Списки — из @Query, поэтому после импорта экран пересчитывается сам.
struct HomeScreen: View {
    let today: CalendarDay
    @Binding var path: [HomeDestination]

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.theme) private var theme

    @Query private var entries: [JournalEntry]
    @Query(sort: \SpendingCategory.sortOrder) private var categories: [SpendingCategory]
    @Query private var accounts: [Account]

    var body: some View {
        let settings = settingsStore.settings
        // Те же границы аванса и разовой премии, что у импорта: иначе периоды разошлись бы с правилами переводов.
        let salaryEvents = findSalaryEvents(entries: entries, advanceDayRange: 10...20, oneOffAboveMedianTimes: 1.5)
        let numbers = calculateHomeNumbers(
            today: today,
            mode: settings.periodMode,
            monthlySavingsGoal: settings.monthlySavingsGoal,
            entries: entries,
            categories: categories,
            accounts: accounts,
            salaryEvents: salaryEvents
        )

        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PeriodPicker(selection: Binding(get: { settings.periodMode }, set: updatePeriodMode))
                    HomeHero(numbers: numbers, theme: theme)
                    Card {
                        BudgetBar(summary: numbers.budget, theme: theme)
                    }
                    HomeBalances(cardBalance: numbers.cardBalance, depositBalance: numbers.depositBalance, theme: theme)
                    // Четыре самых потраченных лимита: остальные — на экране «Все лимиты».
                    HomeLimits(statuses: Array(numbers.limitStatuses.prefix(4)), theme: theme)
                    if numbers.unreviewedCount > 0 {
                        HomeReviewLink(count: numbers.unreviewedCount, theme: theme)
                    }
                }
                .padding()
            }
            .background(theme.background)
            .navigationTitle("Главная")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .review:
                    ReviewScreen()
                case .limits:
                    LimitsPlaceholderScreen(theme: theme)
                }
            }
        }
    }

    private func updatePeriodMode(_ mode: PeriodMode) {
        do {
            try settingsStore.updatePeriodMode(mode)
        } catch {
            errorStore.show(error)
        }
    }
}

// MARK: - Части экрана

private struct HomeHero: View {
    let numbers: HomeNumbers
    let theme: Theme

    var body: some View {
        let isOverspent = numbers.budget.freeToSpend < 0
        VStack(alignment: .leading, spacing: 6) {
            Text(makeHeroTitle(numbers: numbers))
                .font(.subheadline)
                .foregroundStyle(isOverspent ? theme.over : theme.secondaryText)
            Text(formatTenge(makeHeroAmount(freeToSpend: numbers.budget.freeToSpend)))
                .font(theme.heroFont)
                .monospacedDigit()
                .foregroundStyle(isOverspent ? theme.over : theme.text)
            Text(makeHeroCaption(numbers: numbers))
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 4)
    }
}

private struct HomeBalances: View {
    let cardBalance: Decimal
    let depositBalance: Decimal
    let theme: Theme

    var body: some View {
        HStack(spacing: 12) {
            BalanceCard(title: "Карта", amount: cardBalance, theme: theme)
            BalanceCard(title: "Депозит", amount: depositBalance, theme: theme)
        }
    }
}

private struct BalanceCard: View {
    let title: String
    let amount: Decimal
    let theme: Theme

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
                MoneyText(amount: amount, style: .title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HomeLimits: View {
    let statuses: [LimitStatus]
    let theme: Theme

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Лимиты")
                    .font(.headline)
                    .foregroundStyle(theme.text)
                if statuses.isEmpty {
                    Text("Лимиты не заданы")
                        .foregroundStyle(theme.secondaryText)
                    HomeLink(title: "Задать лимиты", destination: .limits, theme: theme)
                } else {
                    ForEach(statuses, id: \.category.id) { status in
                        LimitMeter(status: status, theme: theme)
                    }
                    HomeLink(title: "Все лимиты", destination: .limits, theme: theme)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HomeLink: View {
    let title: String
    let destination: HomeDestination
    let theme: Theme

    var body: some View {
        NavigationLink(value: destination) {
            Text("\(title) ›")
                .font(.subheadline)
                .foregroundStyle(theme.accent)
        }
    }
}

private struct HomeReviewLink: View {
    let count: Int
    let theme: Theme

    var body: some View {
        NavigationLink(value: HomeDestination.review) {
            Card {
                HStack {
                    Text("Проверьте новое")
                        .foregroundStyle(theme.text)
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(theme.accent)
                    Spacer()
                    Text("›")
                        .foregroundStyle(theme.secondaryText)
                }
                .font(.headline)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Заглушка «Все лимиты»: её заменит задача 15.
private struct LimitsPlaceholderScreen: View {
    let theme: Theme

    var body: some View {
        ScrollView {
            Card {
                Text("Здесь будут все лимиты и их настройка.")
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(theme.background)
        .navigationTitle("Лимиты")
    }
}

import SwiftUI
import SwiftData
import KopilkaCore

/// Куда ведут переходы с главной. Экраны «Все лимиты» (задача 15) и «Проверьте новое» (задача 14) пока заглушки.
enum HomeDestination: Hashable {
    case limits, review
}

/// Главная (спека §8): сколько можно потратить до конца периода, полоса бюджета, остатки, главные лимиты.
/// Списки — из @Query, поэтому после импорта экран пересчитывается сам.
struct HomeScreen: View {
    let today: CalendarDay

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ErrorStore.self) private var errorStore
    @Environment(\.theme) private var theme

    @Query private var entries: [JournalEntry]
    @Query(sort: \SpendingCategory.sortOrder) private var categories: [SpendingCategory]
    @Query private var accounts: [Account]

    var body: some View {
        let settings = settingsStore.settings
        let numbers = calculateHomeNumbers(
            today: today,
            mode: settings.periodMode,
            monthlySavingsGoal: settings.monthlySavingsGoal,
            entries: entries,
            categories: categories,
            accounts: accounts
        )

        NavigationStack {
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
                HomeDestinationScreen(destination: destination, theme: theme)
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

// MARK: - Расчёт

/// Всё, что показывает главная, посчитанное за один проход по записям.
struct HomeNumbers {
    let period: Period
    let budget: BudgetSummary
    /// Какое поступление закрывает период; nil — период кончается с месяцем.
    let periodEndKind: SalaryEventKind?
    let limitStatuses: [LimitStatus]
    let cardBalance: Decimal
    let depositBalance: Decimal
    let unreviewedCount: Int
}

func calculateHomeNumbers(
    today: CalendarDay,
    mode: PeriodMode,
    monthlySavingsGoal: Decimal,
    entries: [JournalEntry],
    categories: [SpendingCategory],
    accounts: [Account]
) -> HomeNumbers {
    // Те же границы аванса и разовой премии, что у импорта: иначе периоды разошлись бы с правилами переводов.
    let salaryEvents = findSalaryEvents(entries: entries, advanceDayRange: 10...20, oneOffAboveMedianTimes: 1.5)
    let period = makePeriod(containing: today, mode: mode, salaryEvents: salaryEvents)
    let budget = calculateBudget(
        period: period,
        today: today,
        mode: mode,
        entries: entries,
        categories: categories,
        salaryEvents: salaryEvents,
        monthlySavingsGoal: monthlySavingsGoal
    )
    let cardAccounts = accounts.filter { account in account.kind == .card }
    let depositAccounts = accounts.filter { account in account.kind == .deposit }

    return HomeNumbers(
        period: period,
        budget: budget,
        periodEndKind: findPeriodEndKind(period: period, mode: mode, salaryEvents: salaryEvents),
        limitStatuses: calculateLimitStatuses(period: period, today: today, mode: mode, entries: entries, categories: categories),
        cardBalance: calculateTotalBalance(of: cardAccounts, entries: entries),
        depositBalance: calculateTotalBalance(of: depositAccounts, entries: entries),
        unreviewedCount: entries.filter { entry in !entry.isReviewed && entry.mergedInto == nil }.count
    )
}

private func calculateTotalBalance(of accounts: [Account], entries: [JournalEntry]) -> Decimal {
    accounts.reduce(Decimal(0)) { total, account in total + calculateBalance(account: account, entries: entries) }
}

// MARK: - Подписи

/// «до зарплаты» / «до аванса» / «до конца месяца».
func makePeriodEndLabel(periodEndKind: SalaryEventKind?) -> String {
    guard let periodEndKind else { return "до конца месяца" }
    switch periodEndKind {
    case .salary:
        return "до зарплаты"
    case .advance:
        return "до аванса"
    }
}

/// «зарплата ~15 окт · 6 дней · ≈31 000 ₸ в день»; при перерасходе без «в день».
func makeHeroCaption(numbers: HomeNumbers) -> String {
    let lastDay = numbers.period.endExclusive.adding(days: -1)
    let endText: String
    switch numbers.periodEndKind {
    case .salary:
        endText = "зарплата ~\(formatShortDay(numbers.period.endExclusive))"
    case .advance:
        endText = "аванс ~\(formatShortDay(numbers.period.endExclusive))"
    case nil:
        endText = "по \(formatShortDay(lastDay))"
    }
    let daysText = formatDayCount(numbers.budget.daysLeft)
    guard numbers.budget.freeToSpend >= 0 else { return [endText, daysText].joined(separator: " · ") }
    return [endText, daysText, "≈\(formatTenge(numbers.budget.perDay)) в день"].joined(separator: " · ")
}

// MARK: - Части экрана

private struct HomeHero: View {
    let numbers: HomeNumbers
    let theme: Theme

    var body: some View {
        let freeToSpend = numbers.budget.freeToSpend
        VStack(alignment: .leading, spacing: 6) {
            Text("Можно потратить \(makePeriodEndLabel(periodEndKind: numbers.periodEndKind))")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
            if freeToSpend < 0 {
                Text("Перерасход \(formatTenge(-freeToSpend))")
                    .font(theme.heroFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.over)
            } else {
                // Копейки в главной цифре только мешают читать; вниз — чтобы не обещать лишнего.
                MoneyText(amount: roundDownToWholeTenge(freeToSpend), style: .hero)
            }
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

/// Заглушки экранов-переходов: их заменят задачи 14 и 15.
private struct HomeDestinationScreen: View {
    let destination: HomeDestination
    let theme: Theme

    var body: some View {
        let title = destination == .limits ? "Лимиты" : "Проверьте новое"
        let text = destination == .limits ? "Здесь будут все лимиты и их настройка." : "Здесь будут новые операции на проверку."
        ScrollView {
            Card {
                Text(text)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .background(theme.background)
        .navigationTitle(title)
    }
}

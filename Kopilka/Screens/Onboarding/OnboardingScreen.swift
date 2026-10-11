import SwiftUI
import UniformTypeIdentifiers
import KopilkaCore

/// Начальная настройка (спека §5.9): история из PDF → остатки карты и депозита → готово.
/// `sharedPdfData` — файл, пришедший через «Поделиться», пока настройка не пройдена: он идёт в шаг 1.
struct OnboardingScreen: View {
    @Binding var sharedPdfData: Data?

    @Environment(ErrorStore.self) private var errorStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(JournalStore.self) private var journalStore
    @Environment(AccountStore.self) private var accountStore
    @Environment(RulesStore.self) private var rulesStore
    @Environment(\.theme) private var theme

    @State private var step = OnboardingStep.history
    @State private var isPickingFile = false
    // Шапку разобранной выписки держим здесь, чтобы на шаге 3 не разбирать PDF заново.
    @State private var history: LoadedHistory?
    @State private var cardBalance: Decimal?
    @State private var depositBalance: Decimal?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Шаг \(step.rawValue) из 3")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                OnboardingStepContent(
                    step: step,
                    history: history,
                    cardBalance: $cardBalance,
                    depositBalance: $depositBalance,
                    onPickFile: { isPickingFile = true },
                    onShowStep: { nextStep in step = nextStep },
                    onFinish: finishSetup
                )
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.background)
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.pdf]) { result in
            openPickedFile(result)
        }
        .onChange(of: sharedPdfData, initial: true) {
            openSharedFile()
        }
    }

    private func openPickedFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let pdfData = try readSharedFile(url: url)
            try loadHistory(pdfData: pdfData)
        } catch {
            errorStore.show(error)
        }
    }

    private func openSharedFile() {
        guard let pdfData = sharedPdfData else { return }
        sharedPdfData = nil
        do {
            try loadHistory(pdfData: pdfData)
            step = .history
        } catch {
            errorStore.show(error)
        }
    }

    // Встроенные правила засеваются только на «Готово»: импорт при пустых таблицах правил сам берёт стартовые.
    private func loadHistory(pdfData: Data) throws {
        let statement = try journalStore.readStatement(pdfData: pdfData)
        // Шаг 2 подставляет остаток выписки в поле карты, поэтому выписку депозита отсекаем до записи в базу.
        guard !isDepositStatement(statement.header) else {
            throw SetupError.historyIsNotCardStatement
        }
        let result = try journalStore.importStatement(statement, mode: .initialHistory)
        history = LoadedHistory(header: statement.header, addedCount: result.addedCount, alreadyKnownCount: result.alreadyKnownCount)
        cardBalance = statement.header.availableAmount
    }

    private func finishSetup() {
        guard let history, let cardBalance, let depositBalance else { return }
        let anchorDay = history.header.generatedOn

        do {
            guard let cardAccount = try accountStore.findAccount(number: history.header.accountNumber) else {
                throw SetupError.statementAccountNotFound(number: history.header.accountNumber)
            }
            try accountStore.updateAnchor(cardAccount, balance: cardBalance, day: anchorDay)
            let depositAccount = try accountStore.findOrAddDepositAccount()
            try accountStore.updateAnchor(depositAccount, balance: depositBalance, day: anchorDay)
            try rulesStore.seedBuiltInsIfMissing()
            try settingsStore.saveSetupFinished()
        } catch {
            errorStore.show(error)
        }
    }
}

private enum OnboardingStep: Int {
    case history = 1
    case balances = 2
    case finish = 3
}

private struct LoadedHistory {
    let header: StatementHeader
    let addedCount: Int
    let alreadyKnownCount: Int
}

// MARK: - Шаги

private struct OnboardingStepContent: View {
    let step: OnboardingStep
    let history: LoadedHistory?
    @Binding var cardBalance: Decimal?
    @Binding var depositBalance: Decimal?
    let onPickFile: () -> Void
    let onShowStep: (OnboardingStep) -> Void
    let onFinish: () -> Void

    var body: some View {
        switch step {
        case .history:
            HistoryStep(
                history: history,
                onPickFile: onPickFile,
                onNext: { onShowStep(.balances) }
            )
        case .balances:
            BalancesStep(
                anchorDay: history?.header.generatedOn,
                cardBalance: $cardBalance,
                depositBalance: $depositBalance,
                onBack: { onShowStep(.history) },
                onNext: { onShowStep(.finish) }
            )
        case .finish:
            FinishStep(
                history: history,
                cardBalance: cardBalance,
                depositBalance: depositBalance,
                onBack: { onShowStep(.balances) },
                onFinish: onFinish
            )
        }
    }
}

private struct HistoryStep: View {
    let history: LoadedHistory?
    let onPickFile: () -> Void
    let onNext: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        StepTitle(
            title: "Загрузите историю",
            text: "Выписка Halyk в PDF за прошлые месяцы. Эти операции попадут в журнал и аналитику, но остаток не изменят."
        )
        if let history {
            Card {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.accent)
                    Text(makeLoadedText(history))
                        .foregroundStyle(theme.text)
                }
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            StepButton(title: "Выбрать другой PDF", isMain: false, action: onPickFile)
            StepButton(title: "Дальше", isMain: true, action: onNext)
        } else {
            StepButton(title: "Выбрать PDF", isMain: true, action: onPickFile)
        }
    }
}

private struct BalancesStep: View {
    let anchorDay: CalendarDay?
    @Binding var cardBalance: Decimal?
    @Binding var depositBalance: Decimal?
    let onBack: () -> Void
    let onNext: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        StepTitle(title: "Остатки счетов", text: makeAnchorText(anchorDay))
        Card {
            MoneyField(title: "Карта", amount: $cardBalance)
        }
        Card {
            VStack(alignment: .leading, spacing: 6) {
                MoneyField(title: "Депозит", amount: $depositBalance)
                Text("Если депозита нет, введите 0.")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        StepButton(title: "Дальше", isMain: true, action: onNext)
            .disabled(cardBalance == nil || depositBalance == nil)
        StepButton(title: "Назад", isMain: false, action: onBack)
    }
}

private struct FinishStep: View {
    let history: LoadedHistory?
    let cardBalance: Decimal?
    let depositBalance: Decimal?
    let onBack: () -> Void
    let onFinish: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        StepTitle(title: "Всё готово", text: "Проверьте и нажмите «Готово». Дальше остатки считаются от этих сумм.")
        Card {
            VStack(spacing: 12) {
                SummaryRow(title: "Карта") { MoneyText(amount: cardBalance ?? 0) }
                SummaryRow(title: "Депозит") { MoneyText(amount: depositBalance ?? 0) }
                if let history {
                    SummaryRow(title: "Точка отсчёта") { SummaryValue(text: formatDay(history.header.generatedOn)) }
                }
            }
        }
        StepButton(title: "Готово", isMain: true, action: onFinish)
        StepButton(title: "Назад", isMain: false, action: onBack)
    }
}

// MARK: - Мелкие части шагов

private struct StepTitle: View {
    let title: String
    let text: String

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(theme.heroFont)
                .foregroundStyle(theme.text)
            Text(text)
                .foregroundStyle(theme.secondaryText)
        }
    }
}

private struct StepButton: View {
    let title: String
    let isMain: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        if isMain {
            Button(action: action) { StepButtonLabel(title: title) }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        } else {
            Button(action: action) { StepButtonLabel(title: title) }
                .buttonStyle(.bordered)
                .tint(theme.accent)
        }
    }
}

private struct StepButtonLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }
}

private struct SummaryRow<Value: View>: View {
    let title: String
    @ViewBuilder let value: Value

    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(theme.secondaryText)
            Spacer()
            value
        }
    }
}

private struct SummaryValue: View {
    let text: String

    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(theme.text)
    }
}

private func makeAnchorText(_ anchorDay: CalendarDay?) -> String {
    guard let anchorDay else { return "Сколько денег на счетах сейчас." }
    return "Сколько было на \(formatDay(anchorDay)) — в день формирования выписки. Для карты подставлена «Доступная сумма» из выписки."
}

/// «Добавлено 1160 операций»; при повторном выборе того же файла — «Добавлено 0 операций, уже было 1160».
private func makeLoadedText(_ history: LoadedHistory) -> String {
    let addedText = "Добавлено \(formatOperationCount(history.addedCount))"
    guard history.alreadyKnownCount > 0 else { return addedText }
    return "\(addedText), уже было \(history.alreadyKnownCount)"
}

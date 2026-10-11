import SwiftUI
import PaceCore

/// Окно ввода одной суммы: «Готово» отдаёт введённую сумму, необязательная кнопка сброса — своё действие.
/// Сохраняет вызывающий экран; окно закрывается само после любого из действий.
struct AmountEditorSheet: View {
    let title: String
    let fieldTitle: String
    let initialAmount: Decimal?
    /// Подпись под полем, например «В среднем 42 000 ₸».
    let hint: String?
    let resetTitle: String?
    let onReset: (() -> Void)?
    let onSave: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var amount: Decimal?

    init(
        title: String,
        fieldTitle: String,
        initialAmount: Decimal?,
        hint: String? = nil,
        resetTitle: String? = nil,
        onReset: (() -> Void)? = nil,
        onSave: @escaping (Decimal) -> Void
    ) {
        self.title = title
        self.fieldTitle = fieldTitle
        self.initialAmount = initialAmount
        self.hint = hint
        self.resetTitle = resetTitle
        self.onReset = onReset
        self.onSave = onSave
        // Поле ввода читает сумму при появлении, поэтому начальное значение кладём сразу, а не в onAppear.
        _amount = State(initialValue: initialAmount)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        MoneyField(title: fieldTitle, amount: $amount)
                        if let hint {
                            Text(hint)
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }
                if let resetTitle, let onReset {
                    Button(resetTitle) {
                        onReset()
                        dismiss()
                    }
                    .padding(.horizontal, 4)
                }
                Spacer()
            }
            .padding()
            .background(theme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово", action: save)
                        .disabled(amount == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let amount else { return }
        onSave(amount)
        dismiss()
    }
}

import SwiftUI
import KopilkaCore

/// Как считается месяц (спека §5.7): с 1 числа или от фактического дня зарплаты.
/// «Полмесяца» отдельно не выбирается: его включает настройка «Получаю аванс».
struct PeriodPicker: View {
    @Binding var selection: PeriodMode

    var body: some View {
        Picker("Месяц считается", selection: $selection) {
            Text("С зарплаты").tag(PeriodMode.salaryMonth)
            Text("С 1 числа").tag(PeriodMode.calendarMonth)
        }
        .pickerStyle(.segmented)
    }
}

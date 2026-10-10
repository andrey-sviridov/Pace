import SwiftUI
import KopilkaCore

/// Переключатель режима периода (спека §5.7): «Цикл ЗП / Месяц / Полмесяца».
struct PeriodPicker: View {
    @Binding var selection: PeriodMode

    var body: some View {
        Picker("Период", selection: $selection) {
            Text("Цикл ЗП").tag(PeriodMode.salaryMonth)
            Text("Месяц").tag(PeriodMode.calendarMonth)
            Text("Полмесяца").tag(PeriodMode.halfMonth)
        }
        .pickerStyle(.segmented)
    }
}

import Foundation
import Testing
@testable import KopilkaCore

@Suite struct HomeMonthLineTests {
    private func makeBudget(freeToSpend: Decimal) -> BudgetSummary {
        BudgetSummary(incomeTotal: 0, obligatoryTotal: 0, savingsGoal: 0, flexibleSpent: 0, freeToSpend: freeToSpend, daysLeft: 20, perDay: 0)
    }

    @Test func monthLineShowsWholeTengeFree() {
        #expect(makeMonthFreeText(budget: makeBudget(freeToSpend: Decimal(string: "288610.7")!)) == "за месяц: 288\u{00A0}610 ₸")
    }

    @Test func monthLineShowsOverspend() {
        #expect(makeMonthFreeText(budget: makeBudget(freeToSpend: Decimal(string: "-11999.2")!)) == "за месяц: перерасход 12\u{00A0}000 ₸")
    }

    @Test func operationTimeIsHoursAndMinutes() {
        var almatyCalendar = Calendar(identifier: .gregorian)
        almatyCalendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
        // 2026-10-09 20:05 UTC — в Алматы 01:05 следующего дня.
        let time = Date(timeIntervalSince1970: 1_791_576_300)

        #expect(formatOperationTime(time, calendar: almatyCalendar) == "01:05")
    }
}

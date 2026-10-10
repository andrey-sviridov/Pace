import Foundation
import Observation
import KopilkaCore

/// Единственное место, куда приходят ошибки (спека §7): экраны ловят `throw` и отдают его сюда,
/// а корень показывает `currentMessage` окном.
@Observable
final class ErrorStore {
    var currentMessage: String?

    func show(_ error: Error) {
        currentMessage = makeErrorMessage(error)
    }

    func close() {
        currentMessage = nil
    }
}

/// Понятный пользователю текст по ошибке. Неизвестную ошибку не прячем — показываем её описание,
/// иначе потом не понять, что случилось.
func makeErrorMessage(_ error: Error) -> String {
    switch error {
    case StatementError.notHalykStatement:
        return "Это не похоже на выписку Halyk. Ничего не записано."
    case StatementError.totalsMismatch(let expected, let actual):
        return makeTotalsMismatchMessage(expected: expected, actual: actual)
    case ImportError.unknownAccount(let number):
        return "Выписка по счёту \(number), которого нет в приложении. Ничего не записано."
    case SetupError.statementAccountNotFound(let number):
        return "Не нашёлся счёт \(number) из загруженной выписки. Загрузите выписку ещё раз."
    case ParsingError.badAmount(let text):
        return "В выписке не удалось прочитать сумму «\(text)». Ничего не записано."
    case ParsingError.badDate(let text):
        return "В выписке не удалось прочитать дату «\(text)». Ничего не записано."
    default:
        return "Что-то пошло не так: \(error.localizedDescription)"
    }
}

/// Показываем только те итоги, что разошлись: «в выписке» — строка «Всего», «по строкам» — наша сумма.
private func makeTotalsMismatchMessage(expected: StatementTotals, actual: StatementTotals) -> String {
    let differences = [
        ("Приход", expected.income, actual.income),
        ("Расход", expected.expense, actual.expense),
        ("Комиссия", expected.fee, actual.fee),
    ]
    let differenceLines = differences
        .filter { name, expectedAmount, actualAmount in expectedAmount != actualAmount }
        .map { name, expectedAmount, actualAmount in
            "\(name): в выписке \(formatTenge(expectedAmount)), по строкам \(formatTenge(actualAmount))"
        }
    let header = "Суммы операций не сошлись с итогом «Всего» в выписке. Ничего не записано."
    return ([header] + differenceLines).joined(separator: "\n")
}

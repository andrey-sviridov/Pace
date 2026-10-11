import Foundation

/// Строка, которую «Команда» покажет сразу после оплаты (спека §5.10).
/// Только когда категория дошла до порога или вышла за лимит; в остальных случаях nil — команда промолчит.
public func makeRemainingAfterPaymentText(categoryId: String?, statuses: [LimitStatus]) -> String? {
    guard let categoryId else { return nil }
    guard let status = statuses.first(where: { status in status.category.id == categoryId }) else { return nil }

    let name = status.category.name
    let limitText = formatTenge(status.limit)
    switch status.level {
    case .normal:
        return nil
    case .warning:
        return "\(name): осталось \(formatTenge(status.limit - status.spent)) из \(limitText)"
    case .over:
        return "\(name): перерасход \(formatTenge(status.spent - status.limit)) сверх \(limitText)"
    }
}

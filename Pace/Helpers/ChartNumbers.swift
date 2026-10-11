import Foundation
import PaceCore

// Swift Charts и ползунки работают с Double; это только положение на экране, сами суммы остаются в Decimal.

func makeDouble(_ amount: Decimal) -> Double {
    NSDecimalNumber(decimal: amount).doubleValue
}

/// Суммы на графиках — в тысячах: подписи осей короче («120k», а не «120 000»).
func makeThousands(_ amount: Decimal) -> Double {
    makeDouble(amount / 1000)
}

/// Подпись деления оси в тысячах обратно в «120k».
func formatAxisThousands(_ thousands: Double) -> String {
    formatThousands(Decimal(thousands) * 1000)
}

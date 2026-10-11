import SwiftUI

/// sheet и alert ждут Bool, а у нас правило «есть значение — показываем».
/// Закрытие окна обнуляет значение.
func makeIsShownBinding<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
    Binding(
        get: { value.wrappedValue != nil },
        set: { isShown in
            guard !isShown else { return }
            value.wrappedValue = nil
        }
    )
}

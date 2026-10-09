import Foundation

/// Стартовые категории (спека §10). Новые несохранённые объекты, без лимитов.
public func makeBuiltInCategories() -> [SpendingCategory] {
    let definitions: [(id: String, name: String, iconName: String, kind: CategoryKind)] = [
        ("mortgage", "Ипотека", "house.fill", .obligatory),
        ("loans", "Кредиты", "creditcard.fill", .obligatory),
        ("installments", "Рассрочка Kaspi", "calendar.badge.clock", .obligatory),
        ("family", "Семья", "figure.2.and.child.holdinghands", .obligatory),
        ("utilities", "Коммуналка и связь", "bolt.fill", .obligatory),
        ("groceries", "Продукты", "cart.fill", .flexible),
        ("foodDelivery", "Доставка еды", "bag.fill", .flexible),
        ("cafes", "Кафе и кофе", "cup.and.saucer.fill", .flexible),
        ("transport", "Такси и транспорт", "car.fill", .flexible),
        ("marketplaces", "Маркетплейсы", "shippingbox.fill", .flexible),
        ("health", "Здоровье", "cross.case.fill", .flexible),
        ("subscriptions", "Подписки", "repeat", .flexible),
        ("clothing", "Одежда и красота", "tshirt.fill", .flexible),
        ("electronics", "Электроника", "desktopcomputer", .flexible),
        ("kids", "Дети", "teddybear.fill", .flexible),
        ("sport", "Спорт", "figure.run", .flexible),
        ("travel", "Путешествия и билеты", "airplane", .flexible),
        ("home", "Дом", "sofa.fill", .flexible),
        ("taxes", "Налоги", "doc.text.fill", .flexible),
        ("bankFees", "Комиссии банка", "percent", .flexible),
        ("transfersToPeople", "Переводы людям", "arrow.up.right.circle.fill", .flexible),
        ("uncategorized", "Не определено", "questionmark.circle.fill", .flexible),
        ("salary", "Зарплата", "banknote.fill", .income),
        ("incomingTransfers", "Переводы от людей", "arrow.down.left.circle.fill", .income),
        ("depositInterest", "Проценты по депозиту", "chart.line.uptrend.xyaxis", .income),
        ("refunds", "Возвраты", "arrow.uturn.backward.circle.fill", .income),
        ("ownTransfer", "Свои переводы", "arrow.left.arrow.right", .transfer),
        ("adjustment", "Корректировка", "slider.horizontal.3", .transfer),
    ]

    return definitions.enumerated().map { index, definition in
        SpendingCategory(
            id: definition.id,
            name: definition.name,
            iconName: definition.iconName,
            kind: definition.kind,
            sortOrder: index
        )
    }
}

/// Встроенные правила продавцов (спека §10). Фрагменты записаны в виде ключа продавца.
public func makeBuiltInMerchantRules() -> [MerchantRule] {
    let fragmentsByCategory: [(categoryId: String, fragments: [String])] = [
        ("mortgage", ["ЖИЛСТРОЙСБЕРБАНК"]),
        ("loans", ["ПОГАШЕНИЕБАНКОВСКОЙ", "ПЕРЕВОДНАКРЕДИТRS"]),
        ("utilities", ["ERC", "ҚАЗАҚТЕЛЕКОМ", "IZI", "МОБИЛЬНОЙСВЯЗИ"]),
        ("groceries", ["MAGNUM", "SMALL", "VKUSMART", "SPAR", "ANVAR", "BEKMARKET", "BEEMARKET", "FERMAG", "MINIMARKET", "DOSMART", "LIKEMART", "YANDEXLAVKA", "VSEDLYADOMA", "RAKHMET", "ARZAN", "IPORAZBAY", "IPTURAPBAYEV", "IPABYLAYHAN", "SALEKZ", "SYURPRIZ"]),
        ("foodDelivery", ["YANDEXEDA", "WOLT", "GLOVO", "DODO", "JETPAY"]),
        ("cafes", ["COFFEE", "KOFEYNYA", "ZEBRA", "PAMPUSHKA", "TATTI", "HAPPYCAKE", "SWEETSIN", "KFC", "RESTAURANT", "CAFE", "KAFE", "KKFOOD", "CHEBUREK", "BLIN", "WARM", "SOLOD", "BONJOUR", "OHANA", "KOSTA", "CASPIANINTERNAT"]),
        ("transport", ["UBER", "YANDEXGO", "AVTOBYS", "ASTANALRT"]),
        ("marketplaces", ["KASPIKZ", "WILDBERRIES", "PINDUODUO", "ОПЛАТАВМАРКЕТЕ", "JANAPOST"]),
        ("health", ["BOLNITSA", "STOMAS", "SALAMAT", "PHARM", "APTEKA", "CLINIC", "ZDOROVYE", "GIPPOKRAT"]),
        ("subscriptions", ["CLAUDE", "ANTHROPIC", "OPENAI", "GOOGLE", "YANDEXPLUS", "APPLECOM", "TIKTOK"]),
        ("clothing", ["LCW", "KIMEX", "SPORTMASTER", "LETUAL", "ORCHESTRA", "MORA", "DIONASHOP", "BESTPRAYS", "BEAUTIFUL", "DMASTANA"]),
        ("electronics", ["SULPAK", "MECHTA", "TECHNODOM", "TEKHNODOM"]),
        ("kids", ["DETSKIY", "BEGEMOTIK"]),
        ("sport", ["FITNESS"]),
        ("travel", ["АВИАПЕРЕЛЕТ", "TICKETON"]),
        // A4SHOP превращается в ASHOP: цифры из ключа убираются.
        ("home", ["LILYSHOME", "FIXPRICE", "ASHOP", "ARTGROUP"]),
        ("taxes", ["НАЛОГ"]),
        ("bankFees", ["REGULARCHARGE"]),
    ]

    return fragmentsByCategory.flatMap { entry in
        entry.fragments.map { fragment in
            MerchantRule(merchantKey: fragment, categoryId: entry.categoryId, isBuiltIn: true)
        }
    }
}

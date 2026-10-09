import Foundation
import SwiftData

@Model
public final class MerchantRule {
    @Attribute(.unique) public var merchantKey: String
    public var categoryId: String
    public var title: String?
    public var isBuiltIn: Bool

    public init(merchantKey: String, categoryId: String, title: String? = nil, isBuiltIn: Bool = false) {
        self.merchantKey = merchantKey
        self.categoryId = categoryId
        self.title = title
        self.isBuiltIn = isBuiltIn
    }
}

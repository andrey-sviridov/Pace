import Testing
@testable import KopilkaCore

struct ImportPlannerTests {
    private let threeRows = [makeTestRow(), makeTestRow(), makeTestRow()]

    @Test func returnsOnlyRowsMissingFromStore() {
        let keyedRows = makeKeyedRows(rows: threeRows, accountNumber: "KZ1")
        let existingKeys = Set(keyedRows.prefix(2).map { keyed in keyed.key })
        let newRows = findNewRows(keyedRows: keyedRows, existingKeys: existingKeys)
        #expect(newRows.map { keyed in keyed.key } == [keyedRows[2].key])
    }

    @Test func sameFileTwiceGivesNothing() {
        let keyedRows = makeKeyedRows(rows: threeRows, accountNumber: "KZ1")
        let existingKeys = Set(keyedRows.map { keyed in keyed.key })
        #expect(findNewRows(keyedRows: keyedRows, existingKeys: existingKeys).isEmpty)
    }
}

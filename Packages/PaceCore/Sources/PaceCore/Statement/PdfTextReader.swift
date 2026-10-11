import Foundation
import PDFKit

/// Достаёт текст PDF построчно, сверху вниз, с x-координатой каждого куска.
public func readTextLines(pdfData: Data) throws -> [TextLine] {
    guard let document = PDFDocument(data: pdfData) else {
        throw StatementError.notHalykStatement
    }

    var lines: [TextLine] = []
    for pageIndex in 0..<document.pageCount {
        guard let page = document.page(at: pageIndex) else { continue }
        let pagePieces = readPagePieces(page: page)
        let pageLines = groupPiecesIntoLines(pagePieces, pageIndex: pageIndex, sameLineToleranceY: 2)
        lines.append(contentsOf: pageLines)
    }
    return lines
}

private struct PositionedPiece {
    let y: Double
    let piece: TextPiece
}

// characterBounds даёт рамки глифов, которые прыгают по высоте и теряют пробелы,
// а PDFSelection по строкам отдаёт каждую ячейку таблицы цельным куском с точными границами.
private func readPagePieces(page: PDFPage) -> [PositionedPiece] {
    let pageBounds = page.bounds(for: .mediaBox)
    guard let pageSelection = page.selection(for: pageBounds) else { return [] }

    var pieces: [PositionedPiece] = []
    for lineSelection in pageSelection.selectionsByLine() {
        let text = (lineSelection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { continue }
        let bounds = lineSelection.bounds(for: page)
        // Нижний край у ячеек одной строки таблицы совпадает, верхний зависит от высоты букв.
        let yFromTop = Double(pageBounds.maxY - bounds.minY)
        pieces.append(PositionedPiece(y: yFromTop, piece: TextPiece(x: Double(bounds.minX), text: text)))
    }
    return pieces
}

private func groupPiecesIntoLines(_ pieces: [PositionedPiece], pageIndex: Int, sameLineToleranceY: Double) -> [TextLine] {
    let sortedPieces = pieces.sorted { left, right in left.y < right.y }

    var groups: [[PositionedPiece]] = []
    for positionedPiece in sortedPieces {
        guard let lineY = groups.last?.first?.y, positionedPiece.y - lineY <= sameLineToleranceY else {
            groups.append([positionedPiece])
            continue
        }
        groups[groups.count - 1].append(positionedPiece)
    }

    return groups.map { group in
        let piecesLeftToRight = group.map { positionedPiece in positionedPiece.piece }.sorted { left, right in left.x < right.x }
        return TextLine(pageIndex: pageIndex, y: group[0].y, pieces: piecesLeftToRight)
    }
}

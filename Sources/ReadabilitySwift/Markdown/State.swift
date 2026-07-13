struct MarkdownConversionState {
    var listDepth = 0
    var orderedListCounters: [Int] = []
    var inCodeBlock = false
    var inTable = false
    var blockquoteDepth = 0
    var linkReferences: [(String, String)] = []
    var footnotes: [(String, String)] = []
    var inLink = false
    var inHeading = false
    var inListItem = false
}

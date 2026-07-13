enum MarkdownMathRules {
    static func math(latex: String, display: String) -> String {
        guard !latex.isEmpty else { return "" }
        return display == "block" ? "\n\n$$\(latex)$$\n\n" : "$\(latex)$"
    }
}

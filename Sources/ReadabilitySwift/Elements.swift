/// HTML standardization facade matching `elements::standardize_all`.
public enum Elements {
    public static func standardizeAll(_ html: String, title: String? = nil) throws -> String {
        var result = html
        result = try ElementCodeBlocks.standardize(result)
        result = ElementHeadings.standardize(result, title: title)
        result = ElementImages.standardize(result)
        result = try ElementFootnotes.standardize(result)
        result = try ElementMath.standardize(result)
        return result
    }

    public static func standardizeCodeBlocks(_ html: String) throws -> String { try ElementCodeBlocks.standardize(html) }
    public static func standardizeHeadings(_ html: String, title: String? = nil) -> String { ElementHeadings.standardize(html, title: title) }
    public static func standardizeImages(_ html: String) -> String { ElementImages.standardize(html) }
    public static func pickBestSrcset(_ srcset: String) -> String? { ElementImages.pickBestSrcset(srcset) }
    public static func standardizeFootnotes(_ html: String) throws -> String { try ElementFootnotes.standardize(html) }
    public static func standardizeMath(_ html: String) throws -> String { try ElementMath.standardize(html) }
}

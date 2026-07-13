/// HTML standardization facade matching `elements::standardize_all`.
public enum Elements {
    public static func standardizeAll(_ html: String, title: String? = nil) -> String {
        var result = html
        result = ElementCodeBlocks.standardize(result)
        result = ElementHeadings.standardize(result, title: title)
        result = ElementImages.standardize(result)
        result = ElementFootnotes.standardize(result)
        result = ElementMath.standardize(result)
        return result
    }

    public static func standardizeCodeBlocks(_ html: String) -> String { ElementCodeBlocks.standardize(html) }
    public static func standardizeHeadings(_ html: String, title: String? = nil) -> String { ElementHeadings.standardize(html, title: title) }
    public static func standardizeImages(_ html: String) -> String { ElementImages.standardize(html) }
    public static func pickBestSrcset(_ srcset: String) -> String? { ElementImages.pickBestSrcset(srcset) }
    public static func standardizeFootnotes(_ html: String) -> String { ElementFootnotes.standardize(html) }
    public static func standardizeMath(_ html: String) -> String { ElementMath.standardize(html) }
}

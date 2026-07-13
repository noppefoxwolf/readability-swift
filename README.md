# ReadabilitySwift

ReadabilitySwift is a Swift implementation of [`readabilityrs`](https://github.com/theiskaa/readabilityrs), the Rust port of [Mozilla's Readability.js](https://github.com/mozilla/readability). It extracts the readable article from an HTML document while removing navigation, advertisements, sidebars, and other page furniture.

The library is intended for reader-mode experiences, article previews, offline reading, and content indexing on Apple platforms.

> This project is not affiliated with or endorsed by Mozilla.

## Features

- Extracts the article title, byline, excerpt, body, and metadata.
- Returns cleaned HTML and plain-text content.
- Resolves relative links and media URLs when a base URL is provided.
- Supports JSON-LD, Open Graph, Twitter Card, Dublin Core, and standard metadata.
- Provides `Readerable.isProbablyReaderable(_:)` for lightweight content detection.
- Optionally converts extracted HTML to Markdown.
- Supports Markdown conversion as a standalone utility.
- Includes compatibility tests based on Mozilla Readability fixtures when fixtures are provided.

## Requirements

- Swift 6.3 or later
- iOS 18.0 or later
- macOS 15.0 or later

## Installation

Add the package URL to your Swift Package Manager dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/noppe/readability-swift.git", branch: "main")
]
```

Then add `ReadabilitySwift` to the target that uses it:

```swift
.target(
    name: "MyApp",
    dependencies: ["ReadabilitySwift"]
)
```

The package uses [SwiftSoup](https://github.com/scinfu/SwiftSoup) for HTML parsing. Swift Package Manager resolves it automatically.

## Basic usage

```swift
import Foundation
import ReadabilitySwift

let html = """
<html>
    <head>
        <title>Example Article</title>
    </head>
    <body>
        <nav>Site navigation</nav>
        <article>
            <h1>Example Article</h1>
            <p>This is the main article content.</p>
        </article>
    </body>
</html>
"""

do {
    let parser = try Readability(
        html,
        baseURL: URL(string: "https://example.com/articles/example")
    )
    let article = try parser.parse()

    print(article.title ?? "Untitled")
    print(article.textContent ?? "")
    print(article.content ?? "") // Cleaned HTML
} catch {
    print("Failed to parse the document: \(error)")
}
```

`parse()` throws `ReadabilityError.noContentFound` when no readable content can be extracted. The initializer accepts a typed `URL` base URL.

## Article fields

The returned `Article` contains the following commonly used values:

| Property | Description |
| --- | --- |
| `title` | Extracted article title |
| `content` | Cleaned article HTML |
| `textContent` | Article text with HTML removed |
| `length` | UTF-8 length of `textContent` |
| `excerpt` | Short article excerpt |
| `byline` | Author or byline |
| `image` | Representative image URL |
| `siteName` | Site name |
| `lang` | Document language |
| `publishedTime` | Publication time, when available |
| `rawContent` | Extracted content before final cleanup |
| `markdownContent` | Markdown output when enabled |

## Configuration

Use `ReadabilityOptions` directly:

```swift
let options = ReadabilityOptions(
    charThreshold: 500,
    nbTopCandidates: 5,
    keepClasses: false,
    disableJSONLD: false,
    removeTitleFromContent: true,
    outputMarkdown: true
)

let parser = try Readability(html, options: options)
let article = try parser.parse()
let markdown = article.markdownContent
```

Available options include candidate limits, character thresholds, class preservation, JSON-LD handling, link-density scoring, title removal, whitespace and style cleanup, and Markdown output.

## Readerability detection

For a quick check before running full extraction:

```swift
if Readerable.isProbablyReaderable(html) {
    let article = try Readability(html).parse()
    // Show reader mode for the extracted article.
}
```

The detector can be tuned with `ReaderableOptions`:

```swift
let options = ReaderableOptions(
    minContentLength: 140,
    minScore: 20,
    maxElemsToParse: 1_000
)

let likelyReadable = Readerable.isProbablyReaderable(html, options: options)
```

## Markdown conversion

Convert HTML directly without running article extraction:

```swift
let markdown = Markdown.convert(
    html: "<h1>Hello</h1><p>This is <strong>important</strong>.</p>"
)
```

Formatting can be customized with `MarkdownOptions`:

```swift
let markdownOptions = MarkdownOptions(
    headingStyle: .atx,
    bulletCharacter: "*",
    linkStyle: .reference
)

let markdown = Markdown.convert(html: html, options: markdownOptions)
```

`Elements.standardizeAll(_:)` is also available when vendor-specific HTML patterns need to be normalized before conversion.

## HTML safety

ReadabilitySwift extracts and cleans article content, but it is not a complete security sanitizer. Treat `content` and `rawContent` as untrusted HTML and apply the sanitization and rendering policies required by your application before displaying user-controlled content.

## Testing

Run the test suite with:

```sh
swift test
```

## Example CLI

The `Example` directory contains a small command-line tool for trying the library locally:

```sh
cd Example
swift run Example article.html
swift run Example https://example.com/article --format markdown
cat article.html | swift run Example --format markdown
```

The input can be a local HTML file, an `http`/`https` URL, `-`, or omitted to read from standard input. Output formats are `text` (default) and `markdown`. Use `--url` when a local HTML file needs a base URL for resolving relative links and media.

To run the optional Mozilla fixture compatibility test, set `READABILITYRS_FIXTURES` to a directory containing fixture subdirectories with `source.html` and `expected-metadata.json` files. Set `READABILITYRS_CASES` to a comma-separated list to run selected fixtures.

## Acknowledgements

This project is a Swift implementation of `readabilityrs`, which in turn ports Mozilla's standalone Readability library used by Firefox Reader View. The extraction approach, compatibility surface, and Markdown behavior are documented in the upstream projects:

- [`readabilityrs`](https://github.com/theiskaa/readabilityrs)
- [`mozilla/readability`](https://github.com/mozilla/readability)

## License

ReadabilitySwift is licensed under the [Apache License, Version 2.0](LICENSE). It includes or derives behavior from projects released under the same license. See [LICENSE](LICENSE) for the complete terms.

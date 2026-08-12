# Compatibility with readabilityrs

This report records ReadabilitySwift's compatibility against the test contract
used by `readabilityrs` at commit
`f2d6f7cd432a1d21d383bff465eb9738a265f980` (2026-08-10).

The complete 130-page Mozilla Readability corpus and 105 default-option
Markdown golden pairs are committed as SwiftPM test resources. The tests run
without environment variables or network access.

## Results

| Evaluation | Result |
| --- | ---: |
| Core metadata used by readabilityrs (`title`, `byline`, `excerpt`, `siteName`) | 120/130 (92.3%) |
| Extended metadata (core plus `dir`, `lang`, `publishedTime`) | 116/130 (89.2%) |
| Article extraction for expected-readerable pages | 122/122 (100.0%) |
| Extracted text length within readabilityrs's 0.5–2.0× band | 118/122 (96.7%) |
| Direct readabilityrs `Article` golden | 176 field differences across 90/130 cases |
| Default Markdown output byte-for-byte equal to readabilityrs | 105/105 (100.0%) |
| Markdown quality audit across all Mozilla pages | 130/130 (100.0%) |
| Preformatted/code whitespace regressions | 7/7 (100.0%) |

`readabilityrs` intentionally checks only the four core metadata fields. The
extended result is an additional Swift-side measurement so direction and
language regressions are visible.

## Known metadata differences

Core metadata differs on these 10 pages:

- `ietf-1` — excerpt
- `liberation-1` — byline
- `mathjax` — excerpt
- `mercurial` — excerpt
- `replace-brs` — excerpt
- `salon-1` — byline
- `seattletimes-1` — byline
- `wikipedia-2` — excerpt
- `wikipedia-4` — excerpt
- `wordpress` — byline

The extended comparison additionally differs on:

- `rtl-2` — direction
- `rtl-3` — direction
- `tmz-1` — language
- `wordpress` — direction as well as its core byline difference
- `yahoo-3` — direction

## Known content differences

Four expected-readerable pages fall outside the coarse length band:

| Case | Swift text length | Mozilla expected | Observation |
| --- | ---: | ---: | --- |
| `archive-of-our-own` | 74,218 | 22,245 | Over-extraction |
| `bug-1255978` | 19,904 | 4,152 | No longer empty; close to readabilityrs's 20,301-character output |
| `hukumusume` | 438 | 920 | Slightly below the lower bound |
| `yahoo-3` | 8,850 | 2,844 | Over-extraction |

These differences are committed as explicit regression baselines. The test
still executes and reports every case; a new difference fails the suite.
Baselines describe current behavior and must not be interpreted as correctness
exceptions.

`ArticleGolden.jsonl` is a separate direct oracle generated from the pinned
readabilityrs revision. It compares extraction success, all public metadata,
the public byte length, and whitespace-normalized text. The corresponding
field-level baseline prevents Rust implementation differences from being
confused with differences against Mozilla's expected output.

## Reproducing

Run everything:

```sh
swift test
```

Run only the slower Mozilla extraction evaluation:

```sh
swift test --filter mozillaReadabilityCompatibility
```

Run the direct readabilityrs Markdown comparison and corpus audit:

```sh
swift test --filter readabilityrsMarkdownGoldenCompatibility
swift test --filter allMozillaPagesMarkdownQualityAudit
```

The fixture origin and refresh policy are documented in
`Tests/ReadabilitySwiftTests/Fixtures/README.md`.

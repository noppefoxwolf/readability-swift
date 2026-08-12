# Mozilla Readability fixtures

The `MozillaReadability` directory is copied from `tests/test-pages` in
[`theiskaa/readabilityrs`](https://github.com/theiskaa/readabilityrs) at commit
`f2d6f7cd432a1d21d383bff465eb9738a265f980` (2026-08-10).

The corpus contains all 130 test-page directories used by readabilityrs. Each
directory contains `source.html`, `expected.html`, and
`expected-metadata.json`. The files originate from Mozilla Readability's test
suite and are distributed under the repository's Apache-2.0 license.

Do not update individual fixtures. Refresh the complete directory from a
specific upstream commit so compatibility results remain reproducible.

`MarkdownGolden.jsonl` contains the 105 default-option input/output pairs
captured while running readabilityrs's `markdown_tests` integration target at
the same commit. The upstream target contains 123 tests; cases that exercise
non-default options, the full extraction pipeline, or corpus-wide invariants
are represented as native Swift tests instead of golden pairs.

`ArticleGolden.jsonl` contains readabilityrs's default `Article` result for all
130 pages at the same commit. It records metadata, the public byte length, and
whitespace-normalized text content. `ArticleGoldenKnownDifferences.txt` is the
field-level Swift divergence baseline; removing an entry after a compatibility
fix is safe, while adding one requires reviewing the reported Rust and Swift
values.

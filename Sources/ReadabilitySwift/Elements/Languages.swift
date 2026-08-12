public enum ElementLanguages {
    private static let aliases: [String: String] = [
        "py": "python", "python3": "python", "py3": "python", "js": "javascript", "jsx": "javascript", "ts": "typescript", "tsx": "typescript",
        "rb": "ruby", "rs": "rust", "sh": "shell", "bash": "shell", "zsh": "shell", "fish": "shell", "ksh": "shell", "csh": "shell",
        "ps1": "powershell", "psm1": "powershell", "ps": "powershell", "pwsh": "powershell", "cs": "csharp", "c#": "csharp", "fs": "fsharp", "f#": "fsharp",
        "vb": "vbnet", "vbnet": "vbnet", "vb.net": "vbnet", "objc": "objectivec", "objective-c": "objectivec", "mm": "objectivecpp",
        "kt": "kotlin", "kts": "kotlin", "sc": "scala", "ex": "elixir", "exs": "elixir", "erl": "erlang", "hrl": "erlang", "hs": "haskell", "lhs": "haskell",
        "ml": "ocaml", "mli": "ocaml", "clj": "clojure", "cljs": "clojurescript", "cljc": "clojure", "coffee": "coffeescript", "litcoffee": "coffeescript",
        "pl": "perl", "pm": "perl", "php3": "php", "php4": "php", "php5": "php", "php7": "php", "php8": "php", "phtml": "php",
        "rscript": "r", "jl": "julia", "nim": "nim", "cr": "crystal", "dart": "dart", "elm": "elm", "gvy": "groovy", "gradle": "groovy",
        "m": "matlab", "mat": "matlab", "pas": "pascal", "pp": "pascal", "delphi": "pascal", "f90": "fortran", "f95": "fortran", "f03": "fortran", "f08": "fortran", "for": "fortran", "f": "fortran",
        "cob": "cobol", "cbl": "cobol", "asm": "assembly", "nasm": "assembly", "masm": "assembly", "s": "assembly", "v": "verilog", "sv": "systemverilog", "vhd": "vhdl",
        "htm": "html", "xhtml": "html", "xsl": "xml", "xslt": "xml", "svg": "xml", "rss": "xml", "atom": "xml", "md": "markdown", "mdx": "markdown", "mkd": "markdown", "rst": "restructuredtext", "rest": "restructuredtext", "tex": "latex", "ltx": "latex", "sty": "latex",
        "json5": "json", "jsonc": "json", "geojson": "json", "yml": "yaml", "gql": "graphql", "proto": "protobuf", "thrift": "thrift", "avro": "avro", "scss": "scss", "sass": "sass", "less": "less", "styl": "stylus", "stylus": "stylus",
        "docker": "dockerfile", "tf": "terraform", "hcl": "terraform", "nix": "nix", "bat": "batch", "cmd": "batch", "awk": "awk", "sed": "sed", "mysql": "sql", "pgsql": "sql", "plsql": "sql", "tsql": "sql", "sqlite": "sql", "psql": "sql",
        "el": "lisp", "rkt": "racket", "scm": "scheme", "ss": "scheme", "sml": "sml", "sig": "sml", "pro": "prolog", "p": "prolog", "h": "c", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hxx": "cpp", "c++": "cpp",
        "vue": "vue", "svelte": "svelte", "hbs": "handlebars", "mustache": "mustache", "ejs": "ejs", "pug": "pug", "jade": "pug", "erb": "erb", "haml": "haml", "slim": "slim", "twig": "twig", "jinja": "jinja2", "j2": "jinja2", "liquid": "liquid",
        "golang": "go", "wasm": "wasm", "wat": "wasm", "sol": "solidity", "vy": "vyper", "ahk": "autohotkey", "osascript": "applescript", "patch": "diff"
    ]
    private static let known: Set<String> = ["python", "javascript", "typescript", "ruby", "rust", "go", "java", "kotlin", "scala", "swift", "dart", "elixir", "erlang", "haskell", "ocaml", "clojure", "clojurescript", "perl", "php", "lua", "r", "julia", "nim", "crystal", "shell", "powershell", "csharp", "fsharp", "vbnet", "objectivec", "objectivecpp", "cpp", "c", "zig", "ada", "fortran", "cobol", "pascal", "assembly", "verilog", "vhdl", "systemverilog", "sql", "html", "css", "scss", "sass", "less", "stylus", "xml", "json", "yaml", "toml", "markdown", "latex", "graphql", "protobuf", "dockerfile", "terraform", "nix", "makefile", "cmake", "batch", "vue", "svelte", "handlebars", "mustache", "ejs", "pug", "erb", "haml", "slim", "twig", "jinja2", "liquid", "diff", "wasm", "solidity", "matlab", "groovy", "coffeescript", "lisp", "scheme", "racket", "prolog", "sml", "ini", "csv", "restructuredtext", "applescript", "autohotkey"]

    public static func normalizeLanguage(_ language: String) -> String {
        let value = language.trimmed().lowercased()
        return aliases[value] ?? value
    }

    public static func isKnownLanguage(_ language: String) -> Bool { known.contains(normalizeLanguage(language)) }
}

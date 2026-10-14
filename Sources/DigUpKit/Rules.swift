import Foundation
import UniformTypeIdentifiers

public enum Classification: Equatable, Sendable {
    case index(FileKind)
    case skip(String)   // a reason worth reporting ("code or data file")
    case ignore         // a type we don't handle at all
}

/// What gets indexed. The defaults come from a real developer's Mac: Spotlight types 57k TypeScript files as movies,
/// one repo holds a 55k-clip dataset, and screenshot tools move screenshots into code projects.
public enum Rules {
    /// Folders never worth walking into. Hidden folders and bundles are skipped by the enumerator itself.
    static let skippedFolderNames: Set<String> = [
        "node_modules", "bower_components", "venv", "site-packages", "__pycache__", "DerivedData", "Pods", "Carthage",
    ]
    /// Where apps keep what they make for themselves, any case: CapCut's effects in ~/Movies are thousands of images.
    /// Code search still walks them: in a project, a "cache" folder is usually its own code (ESP-IDF's log cache).
    static let cacheFolderNames: Set<String> = ["cache", "caches"]

    /// Any of these in a folder makes it a code project, where only screenshots are indexed.
    static let projectMarkers = [
        ".git", "package.json", "Package.swift", "pyproject.toml", "setup.py", "requirements.txt", "Cargo.toml",
        "go.mod", "pom.xml", "build.gradle", "build.gradle.kts", "Gemfile", "composer.json", "CMakeLists.txt",
    ]
    static let projectBundleExtensions: Set<String> = ["xcodeproj", "xcworkspace"]

    static let docExtensions: Set<String> = ["txt", "text", "md", "markdown", "rtf", "docx", "doc", "odt", "pptx", "html", "htm"]

    /// Source code and data files: off by default (your editor and ripgrep search them better, and they flood an index).
    static let codeExtensions: Set<String> = [
        "py", "ipynb", "c", "h", "cc", "cpp", "cxx", "hpp", "hh", "m", "mm", "swift", "tsx", "cts", "js", "jsx", "mjs",
        "cjs", "go", "rs", "java", "kt", "kts", "scala", "rb", "php", "cs", "fs", "sh", "bash", "zsh", "fish", "ps1",
        "lua", "pl", "r", "jl", "dart", "sql", "vue", "svelte", "css", "scss", "sass", "less", "json", "jsonl", "yaml",
        "yml", "toml", "xml", "plist", "gradle", "cmake", "mk", "lock", "log", "csv", "tsv", "ini", "cfg", "conf",
        "proto", "graphql", "tf", "nix", "zig", "hs", "ex", "exs", "erl", "clj", "elm", "ml", "vim", "el", "asm",
        "metal", "glsl", "hlsl", "wgsl", "cu", "pyi", "pyc", "bicep",
    ]

    static let screenshotPrefixes = ["Screenshot", "Screen Shot", "CleanShot", "SCR-"]

    // MARK: Code (the code index, `IndexOptions.code`)

    /// Source files code search reads.
    static let sourceExtensions: Set<String> = [
        "py", "pyi", "pyx", "c", "h", "cc", "cpp", "cxx", "hpp", "hh", "hxx", "m", "mm", "swift", "ts", "tsx", "mts",
        "cts", "js", "jsx", "mjs", "cjs", "go", "rs", "java", "kt", "kts", "scala", "groovy", "rb", "php", "cs", "fs",
        "sh", "bash", "zsh", "fish", "ps1", "lua", "pl", "pm", "r", "jl", "dart", "sql", "vue", "svelte", "astro",
        "html", "htm", "css", "scss", "sass", "less", "gradle", "cmake", "mk", "proto", "graphql", "gql", "tf", "hcl",
        "nix", "zig", "hs", "ex", "exs", "erl", "clj", "cljs", "elm", "ml", "mli", "vim", "el", "lisp", "asm", "s",
        "metal", "glsl", "hlsl", "wgsl", "cu", "cuh", "ino", "v", "sv", "tex", "bicep",
    ]
    /// What goes with code: a repo's docs and its settings.
    static let codeTextExtensions: Set<String> = ["md", "markdown", "rst", "adoc", "org", "txt", "yaml", "yml", "toml"]
    /// Code known by its name alone.
    static let codeFileNames: Set<String> = [
        "Makefile", "makefile", "GNUmakefile", "Dockerfile", "Containerfile", "Justfile", "justfile", "Rakefile",
        "Gemfile", "Podfile", "Brewfile", "Procfile", "Vagrantfile", "Jenkinsfile",
    ]
    /// Folders code search doesn't go into, besides what git ignores: other people's code kept in a repo (vendor/,
    /// third_party/), what builds and runs leave (build/, dist/, a wandb run's copy of the code), for repos whose
    /// .gitignore doesn't list them and folders that aren't in git at all.
    static let codeSkippedFolderNames: Set<String> = [
        "vendor", "Vendor", "vendored", "third_party", "third-party", "thirdparty", "3rdparty", "external", "extern",
        "deps", "build", "Build", "dist", "out", "target", "obj", "coverage", "htmlcov", "generated", "__generated__",
        "wandb", "mlruns", "lightning_logs",
    ]

    /// What code search reads in the code folders: source files, a repo's docs and settings, and notebooks. Never data
    /// (json, csv, lockfiles, logs), minified bundles, licenses, or anything that looks like a key or a password file.
    public static func classifyCode(_ url: URL, options: IndexOptions) -> Classification {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if options.excludedExtensions.contains(ext) { return .skip("excluded type") }
        if isSecret(name) { return .skip("key or password file") }
        let lower = name.lowercased()
        if lower.hasSuffix(".min.js") || lower.hasSuffix(".min.mjs") || lower.hasSuffix(".min.css") {
            return .skip("minified")
        }
        if ["license", "licence", "copying", "notice"].contains(where: lower.hasPrefix) { return .skip("license") }
        if (ext == "ts" || ext == "mts"), isMPEGTransportStream(url) { return .ignore }   // a video
        if mayBeCode(name) { return .index(.code) }
        if codeExtensions.contains(ext) { return .skip("data file") }   // json, csv, lockfiles, logs, plists
        return .ignore
    }

    /// Whether a file of this name is of a type code search reads (`classifyCode`, from the name alone).
    static func mayBeCode(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return sourceExtensions.contains(ext) || codeTextExtensions.contains(ext) || ext == "ipynb"
            || codeFileNames.contains(name) || name.hasPrefix("Dockerfile")
    }

    /// Whether a file of this name may be indexed (`classify`, from the name alone: a ".ts" may still be a video).
    /// False only when it surely isn't.
    static func mayBeIndexed(_ name: String, options: IndexOptions) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        if options.excludedExtensions.contains(ext) { return false }
        if ext == "ts" || ext == "mts" || ext == "m2ts" || docExtensions.contains(ext) { return true }
        if codeExtensions.contains(ext) { return options.includeCode }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return options.includeCode }
        return type.conforms(to: .pdf) || type.conforms(to: .image) || type.conforms(to: .movie)
            || type.conforms(to: .audio)
    }

    /// Whether a file of this name may be an image `classify` indexes (from the name alone): inside a code project, the
    /// only kind a walk keeps, if it's a screenshot.
    static func mayBeImage(_ name: String, options: IndexOptions) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        if options.excludedExtensions.contains(ext) || ext == "ts" || ext == "mts" || ext == "m2ts"
            || docExtensions.contains(ext) || codeExtensions.contains(ext) {
            return false
        }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .sourceCode) && !type.conforms(to: .script)
            && !type.conforms(to: .pdf)
    }

    /// A file or bundle that makes its folder a code project (`isProjectRoot`).
    static func isProjectMarker(_ name: String) -> Bool {
        projectMarkers.contains(name) || projectBundleExtensions.contains((name as NSString).pathExtension)
    }

    /// Whether a walk never goes into a folder of this name (`skipReason`, and `codeSkipReason` for code; by name
    /// alone).
    static func skipsFolder(named name: String, code: Bool) -> Bool {
        skippedFolderNames.contains(name) || name.hasSuffix(".noindex")
            || (code ? codeSkippedFolderNames.contains(name) : cacheFolderNames.contains(name.lowercased()))
    }

    /// Keys, certificates, password and credential files: never read, wherever they are.
    static func isSecret(_ name: String) -> Bool {
        let lower = name.lowercased()
        let secretTypes: Set<String> = ["pem", "key", "p12", "pfx", "keystore", "jks", "ppk", "kdbx", "gpg", "asc",
                                        "crt", "cer", "der", "p8", "mobileprovision"]
        if secretTypes.contains((lower as NSString).pathExtension) { return true }
        return ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", ".env", "secret", "credential", ".netrc", ".npmrc",
                ".pypirc", "htpasswd", ".htpasswd"].contains(where: lower.hasPrefix)
    }

    /// Why code search doesn't go into a folder (`codeSkippedFolderNames`), or nil.
    static func codeSkipReason(forFolder url: URL) -> String? {
        if codeSkippedFolderNames.contains(url.lastPathComponent) { return "vendored or built code" }
        // A submodule or a worktree (".git" is a file there): someone else's code, or a copy of a repo's own.
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path + "/.git", isDirectory: &isFolder), !isFolder.boolValue {
            return "submodule or worktree"
        }
        return nil
    }

    public static func classify(_ url: URL, type: UTType?, options: IndexOptions) -> Classification {
        let ext = url.pathExtension.lowercased()
        if options.excludedExtensions.contains(ext) { return .skip("excluded type") }
        // .ts / .mts are usually TypeScript, which Spotlight calls MPEG-2 video. Only a real transport stream is video.
        if ext == "ts" || ext == "mts" || ext == "m2ts" {
            if isMPEGTransportStream(url) { return .index(.video) }
            return options.includeCode ? .index(.doc) : .skip("code or data file")
        }
        if docExtensions.contains(ext) { return .index(.doc) }
        if codeExtensions.contains(ext) { return options.includeCode ? .index(.doc) : .skip("code or data file") }
        guard let type else { return .ignore }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) {
            return options.includeCode ? .index(.doc) : .skip("code or data file")
        }
        if type.conforms(to: .pdf) { return .index(.pdf) }
        if type.conforms(to: .image) { return .index(isScreenshot(url) ? .screenshot : .image) }
        if type.conforms(to: .movie) { return .index(.video) }
        if type.conforms(to: .audio) { return .index(.audio) }
        return .ignore
    }

    /// Only in the cloud: a dataless placeholder (iCloud Drive, OneDrive: any File Provider), which a walk leaves out
    /// (`Crawler`). Asking doesn't download it.
    static func isInTheCloud(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_flags & 0x4000_0000 != 0   // SF_DATALESS
    }

    /// MPEG-TS packets start with 0x47 every 188 bytes (or every 192 with a 4-byte timecode, as in .m2ts / AVCHD .mts).
    /// A file that's only in the cloud isn't sniffed: reading a dataless placeholder (iCloud, OneDrive) downloads it,
    /// and the crawler leaves it out anyway.
    static func isMPEGTransportStream(_ url: URL) -> Bool {
        var info = stat()
        guard stat(url.path, &info) == 0, info.st_flags & 0x4000_0000 == 0 else { return false }  // SF_DATALESS
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 600), data.count >= 400 else { return false }
        let bytes = [UInt8](data)
        return (bytes[0] == 0x47 && bytes[188] == 0x47 && bytes[376] == 0x47)
            || (bytes[4] == 0x47 && bytes[196] == 0x47 && bytes[388] == 0x47)
    }

    /// macOS marks screenshots with an extended attribute that survives moves and copies; names are the fallback.
    public static func isScreenshot(_ url: URL) -> Bool {
        if getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0 { return true }
        let name = url.lastPathComponent
        return screenshotPrefixes.contains { name.hasPrefix($0) }
    }

    static func skipReason(forFolder url: URL, home: String, excluded: [String], code: Bool) -> String? {
        let name = url.lastPathComponent
        if skippedFolderNames.contains(name) { return "developer folder" }
        if !code, cacheFolderNames.contains(name.lowercased()) { return "app cache" }
        if name.hasSuffix(".noindex") { return ".noindex folder" }
        if url.path == home + "/Library" { return "~/Library" }
        if excluded.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) { return "excluded folder" }
        return nil
    }

    static func isProjectRoot(_ folder: String) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return false }
        let set = Set(names)
        return projectMarkers.contains(where: set.contains)
            || names.contains { projectBundleExtensions.contains(($0 as NSString).pathExtension) }
    }

    static let cameraPrefixes = ["img", "dsc", "pxl", "mvimg", "vid", "gopr", "dji", "photo", "whatsapp", "screenshot"]

    /// Machine-made names like "clip_000123", "frame-0042" or "3f9a1c0e-…", but not camera names like "IMG_1234".
    public static func looksMachineNamed(_ stem: String) -> Bool {
        let name = stem.lowercased()
        if cameraPrefixes.contains(where: { name.hasPrefix($0) }) { return false }
        if name.range(of: #"^[0-9a-f]{8,}([-_][0-9a-f]{4,})*$"#, options: .regularExpression) != nil { return true }
        return name.range(of: #"^[a-z]{0,16}[-_. ]?\d{3,}([-_.]\d+)*$"#, options: .regularExpression) != nil
    }

    /// Folders with hundreds of same-kind, machine-named media files: training data, not your stuff.
    /// They're skipped (and reported) instead of being indexed silently. Roots you pick yourself are never datasets.
    static func datasetFolders(_ files: [(folder: String, stem: String, kind: FileKind)], roots: Set<String>,
                               minimum: Int = 300) -> [String: Int] {
        var groups: [String: [String]] = [:]
        for file in files where [.image, .audio, .video].contains(file.kind) && !roots.contains(file.folder) {
            groups["\(file.folder)\u{0}\(file.kind.rawValue)", default: []].append(file.stem)
        }
        var datasets: [String: Int] = [:]
        for (key, stems) in groups where stems.count >= minimum {
            let machine = stems.filter(looksMachineNamed).count
            if Double(machine) / Double(stems.count) >= 0.7 {
                datasets[String(key.split(separator: "\u{0}")[0]), default: 0] += stems.count
            }
        }
        return datasets
    }
}

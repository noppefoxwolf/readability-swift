import Foundation
import Testing

func mozillaFixtureRoot() throws -> URL {
    try #require(
        Bundle.module.resourceURL?
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("MozillaReadability", isDirectory: true)
    )
}

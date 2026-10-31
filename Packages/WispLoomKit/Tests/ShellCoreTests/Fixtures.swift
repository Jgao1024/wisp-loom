import Foundation

@testable import ShellCore

enum Fixtures {
    static let manifestJSON = """
        {
          "id": "dev.wisp.sample",
          "name": { "zh-Hans": "示例", "en": "Sample" },
          "category": { "ja": "ツール", "fr": "Outils" },
          "symbol": "sparkles",
          "tint": "purple",
          "ui": "ui.js",
          "settings": true,
          "backend": { "exec": ["backend/echo"], "idle": 30 },
          "window": { "size": [1100, 720], "min": [720, 480] }
        }
        """

    static func manifest(_ json: String = manifestJSON) throws -> Manifest {
        try Manifest.decode(Data(json.utf8))
    }
}

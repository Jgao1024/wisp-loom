import Foundation
import Testing

@testable import ShellCore

struct ToolbarSpecTests {
    @Test func decodesItemsAndMenuEntries() throws {
        let json = """
            {
              "leading": [{ "id": "new", "symbol": "square.and.pencil", "help": "新建对话" }],
              "trailing": [
                { "id": "more", "symbol": "ellipsis", "menu": [
                  { "id": "rename", "title": "重命名" },
                  { "id": "delete", "title": "删除", "destructive": true, "disabled": true }
                ]},
                { "id": "search", "search": true, "placeholder": "搜索" }
              ]
            }
            """
        let spec = try JSONDecoder().decode(ToolbarSpec.self, from: Data(json.utf8))
        #expect(spec.leading.map(\.id) == ["new"])
        #expect(spec.leading.first?.kind == .button)
        #expect(spec.trailing.map(\.kind) == [.menu, .search])
        #expect(spec.trailing[0].menu.map(\.id) == ["rename", "delete"])
        #expect(spec.trailing[0].menu[1].destructive)
        #expect(!spec.trailing[0].menu[1].isEnabled)
        #expect(spec.trailing[1].placeholder == "搜索")
    }

    @Test func missingSectionsAreEmpty() throws {
        let spec = try JSONDecoder().decode(ToolbarSpec.self, from: Data("{}".utf8))
        #expect(spec == ToolbarSpec())
        #expect(spec.leading.isEmpty && spec.trailing.isEmpty)
    }

    @Test func sidebarIsItsOwnItemKind() throws {
        let json = #"{"leading":[{"id":"sidebar","sidebar":true}]}"#
        let spec = try JSONDecoder().decode(ToolbarSpec.self, from: Data(json.utf8))
        #expect(spec.leading.first?.kind == .sidebar)
        #expect(spec.leading.first?.sidebar == true)
    }

    @Test func disabledMapsToEnabled() throws {
        let json = #"{"trailing":[{"id":"a","symbol":"plus","disabled":true},{"id":"b","symbol":"minus"}]}"#
        let spec = try JSONDecoder().decode(ToolbarSpec.self, from: Data(json.utf8))
        #expect(spec.trailing.map(\.isEnabled) == [false, true])
    }
}

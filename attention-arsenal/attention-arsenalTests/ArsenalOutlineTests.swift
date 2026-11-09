import Testing
@testable import attention_arsenal

/// Drag-and-drop rules for the mixed arsenal/category list.
@Suite("ArsenalOutline")
struct ArsenalOutlineTests {
    typealias O = ArsenalOutline<Int>

    /// Top: 1, [Work: 3, 4], 2, [School: 5]   (higher key = higher in the list)
    private func make() -> O {
        O(arsenals: [(1, nil, 100), (3, "Work", 95), (4, "Work", 94), (2, nil, 80), (5, "School", 70)],
          categoryKeys: ["Work": 96, "School": 75])
    }

    private func rows(_ o: O) -> [O.Row] { o.rows(isVisible: { _ in true }, isExpanded: { _ in true }) }

    @Test func buildsMixedOrder() {
        #expect(make().top == [.arsenal(1), .category("Work"), .arsenal(2), .category("School")])
        #expect(rows(make()) == [.arsenal(1, category: nil), .header("Work"), .arsenal(3, category: "Work"),
                                 .arsenal(4, category: "Work"), .arsenal(2, category: nil),
                                 .header("School"), .arsenal(5, category: "School")])
    }

    @Test func categoryWithoutKeySitsAtItsNewestArsenal() {
        let o = O(arsenals: [(1, nil, 100), (2, "Gym", 90), (3, nil, 80)], categoryKeys: [:])
        #expect(o.top == [.arsenal(1), .category("Gym"), .arsenal(3)])
    }

    @Test func categoryMovesBetweenArsenals() {
        var o = make()
        // Drag School up so it lands between 1 and Work.
        o.move(.header("School"), prev: .arsenal(1, category: nil), next: .header("Work"))
        #expect(o.top == [.arsenal(1), .category("School"), .category("Work"), .arsenal(2)])
        // Its arsenals travel with it.
        #expect(o.flatOrder.prefix(3) == [.arsenal(1), .category("School"), .arsenal(5)])
    }

    @Test func categoryDroppedInsideAnotherBlockGoesAfterIt() {
        var o = make()
        o.move(.header("School"), prev: .arsenal(3, category: "Work"), next: .arsenal(4, category: "Work"))
        #expect(o.top == [.arsenal(1), .category("Work"), .category("School"), .arsenal(2)])
    }

    @Test func arsenalDroppedAmongCategoryArsenalsJoinsIt() {
        var o = make()
        o.move(.arsenal(2, category: nil), prev: .arsenal(3, category: "Work"), next: .arsenal(4, category: "Work"))
        #expect(o.children["Work"] == [3, 2, 4])
        #expect(o.categoryByArsenal[2] == .some("Work"))
    }

    @Test func arsenalUnderOpenHeaderJoinsAtTop() {
        var o = make()
        o.move(.arsenal(1, category: nil), prev: .header("Work"), next: .arsenal(3, category: "Work"))
        #expect(o.children["Work"] == [1, 3, 4])
    }

    @Test func topLevelArsenalAtEndOfBlockStaysTopLevel() {
        var o = make()
        o.move(.arsenal(1, category: nil), prev: .arsenal(4, category: "Work"), next: .arsenal(2, category: nil))
        #expect(o.top == [.category("Work"), .arsenal(1), .arsenal(2), .category("School")])
        #expect(o.categoryByArsenal[1] == .some(nil))
    }

    @Test func arsenalDraggedAboveHeaderLeavesCategory() {
        var o = make()
        o.move(.arsenal(4, category: "Work"), prev: .arsenal(1, category: nil), next: .header("Work"))
        #expect(o.top == [.arsenal(1), .arsenal(4), .category("Work"), .arsenal(2), .category("School")])
        #expect(o.children["Work"] == [3])
    }

    @Test func emptiedCategoryDisappears() {
        var o = make()
        o.move(.arsenal(5, category: "School"), prev: nil, next: .arsenal(1, category: nil))
        #expect(o.top == [.arsenal(5), .arsenal(1), .category("Work"), .arsenal(2)])
        #expect(o.children["School"] == nil)
    }
}

import Foundation

/// The main list's order: one top-level sequence that mixes uncategorized arsenals with
/// category blocks, and each category's own ordered arsenals. Pure value type (generic over
/// the arsenal ID) so the drag-and-drop rules are unit-testable without Core Data.
///
/// Persisted as sort keys, higher first: arsenals use `createdDate`, categories a key stored
/// in UserDefaults. A category with no stored key sits where its newest arsenal would.
struct ArsenalOutline<Key: Hashable> {
    enum Item: Hashable {
        case arsenal(Key)
        case category(String)
    }

    enum Row: Hashable, Identifiable {
        case header(String)
        case arsenal(Key, category: String?)

        /// Stable across category changes. Including the category made a row dragged into a
        /// category look like delete+insert mid-drag, which crashes UICollectionView.
        var id: AnyHashable {
            switch self {
            case .header(let c): return "header:" + c
            case .arsenal(let id, _): return id
            }
        }
    }

    private(set) var top: [Item]
    private(set) var children: [String: [Key]]

    init(arsenals: [(id: Key, category: String?, key: Double)], categoryKeys: [String: Double]) {
        var children: [String: [(Key, Double)]] = [:]
        var keyed: [(Item, Double, String)] = []
        for a in arsenals {
            if let c = a.category, !c.isEmpty {
                children[c, default: []].append((a.id, a.key))
            } else {
                keyed.append((.arsenal(a.id), a.key, ""))
            }
        }
        for (c, ids) in children {
            keyed.append((.category(c), categoryKeys[c] ?? ids.map(\.1).max() ?? 0, c))
        }
        top = keyed.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }.map(\.0)
        self.children = children.mapValues { $0.sorted { $0.1 > $1.1 }.map(\.0) }
    }

    /// Rows on screen. A category with nothing visible (filter) is hidden entirely.
    func rows(isVisible: (Key) -> Bool, isExpanded: (String) -> Bool) -> [Row] {
        top.flatMap { item -> [Row] in
            switch item {
            case .arsenal(let id):
                return isVisible(id) ? [.arsenal(id, category: nil)] : []
            case .category(let c):
                let visible = (children[c] ?? []).filter(isVisible)
                if visible.isEmpty { return [] }
                return [.header(c)] + (isExpanded(c) ? visible.map { .arsenal($0, category: c) } : [])
            }
        }
    }

    /// Everything in display order (category arsenals right after their category), for
    /// writing the sort keys back.
    var flatOrder: [Item] {
        top.flatMap { item -> [Item] in
            if case .category(let c) = item {
                return [item] + (children[c] ?? []).map(Item.arsenal)
            }
            return [item]
        }
    }

    /// Category each arsenal ends up in (nil = top level).
    var categoryByArsenal: [Key: String?] {
        var map: [Key: String?] = [:]
        for case .arsenal(let id) in top { map[id] = .some(nil) }
        for (c, ids) in children { for id in ids { map[id] = c } }
        return map
    }

    /// Drop `row` between the on-screen neighbours `prev` and `next` (both excluding `row`).
    /// Categories always move as a whole block at the top level. An arsenal joins a category
    /// when dropped among its arsenals or right under its open header. At the very end of a
    /// category's block it stays in that category only if it already belonged there, so
    /// dragging below a block puts a top-level arsenal after it.
    mutating func move(_ row: Row, prev: Row?, next: Row?) {
        switch row {
        case .header(let c):
            let anchor = prev.map { owner(of: $0) }
            if anchor == .category(c) { return }
            top.removeAll { $0 == .category(c) }
            insertTop(.category(c), after: anchor)

        case .arsenal(let id, let current):
            if let current {
                children[current]?.removeAll { $0 == id }
            } else {
                top.removeAll { $0 == .arsenal(id) }
            }
            let nextCategory: String? = {
                if case .arsenal(_, let nc)? = next { return nc }
                return nil
            }()

            switch prev {
            case .header(let d)?:
                if nextCategory == d || current == d {
                    children[d, default: []].insert(id, at: 0)
                } else {
                    insertTop(.arsenal(id), after: .category(d))
                }
            case .arsenal(let pid, let d?)?:
                if nextCategory == d || current == d {
                    let list = children[d] ?? []
                    let at = (list.firstIndex(of: pid) ?? list.count - 1) + 1
                    children[d, default: []].insert(id, at: at)
                } else {
                    insertTop(.arsenal(id), after: .category(d))
                }
            case .arsenal(let pid, nil)?:
                insertTop(.arsenal(id), after: .arsenal(pid))
            case nil:
                insertTop(.arsenal(id), after: nil)
            }
            // A category emptied by the drag disappears; drop it from the top level too.
            if let current, children[current]?.isEmpty == true {
                children[current] = nil
                top.removeAll { $0 == .category(current) }
            }
        }
    }

    private func owner(of row: Row) -> Item {
        switch row {
        case .header(let c), .arsenal(_, let c?): return .category(c)
        case .arsenal(let id, nil): return .arsenal(id)
        }
    }

    private mutating func insertTop(_ item: Item, after anchor: Item?) {
        let at = anchor.flatMap { top.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        top.insert(item, at: at)
    }
}

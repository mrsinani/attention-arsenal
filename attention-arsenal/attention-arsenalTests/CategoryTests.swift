import Testing
import CoreData
@testable import attention_arsenal

@Suite("Arsenal categories")
struct CategoryTests {
    @Test func categoryNamesAreDistinctSortedAndSkipEmpty() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let arsenals = ["work", "School", nil, "", "work"].map { name -> Arsenal in
            let arsenal = Arsenal(context: context)
            arsenal.category = name
            return arsenal
        }
        #expect(Arsenal.categoryNames(in: arsenals) == ["School", "work"])
        #expect(Arsenal.categoryNames(in: arsenals, plus: "Gym") == ["Gym", "School", "work"])
    }

    @Test func cleanCategoryNameTrimsAndCaps() {
        #expect(Arsenal.cleanCategoryName("  Work \n") == "Work")
        #expect(Arsenal.cleanCategoryName("   ").isEmpty)
        #expect(Arsenal.cleanCategoryName(String(repeating: "a", count: 40)).count == 30)
    }
}

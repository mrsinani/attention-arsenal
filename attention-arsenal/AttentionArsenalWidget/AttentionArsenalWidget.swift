import WidgetKit
import SwiftUI
import CoreData

// MARK: - Timeline Entry
struct ArsenalWidgetEntry: TimelineEntry {
    let date: Date
    let arsenals: [ArsenalData]
}

// MARK: - Arsenal Data Model
struct ArsenalData: Identifiable {
    let id: UUID
    let title: String
    let arsenalDescription: String?
    let startDate: Date?
    let endDate: Date?
    let isCompleted: Bool
}

// MARK: - Timeline Provider
struct ArsenalWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ArsenalWidgetEntry {
        ArsenalWidgetEntry(date: Date(), arsenals: getSampleArsenals())
    }
    
    func getSnapshot(in context: Context, completion: @escaping (ArsenalWidgetEntry) -> Void) {
        let entry: ArsenalWidgetEntry
        if context.isPreview {
            entry = ArsenalWidgetEntry(date: Date(), arsenals: getSampleArsenals())
        } else {
            entry = ArsenalWidgetEntry(date: Date(), arsenals: fetchArsenals(limit: 2))
        }
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<ArsenalWidgetEntry>) -> Void) {
        let currentDate = Date()
        let limit: Int
        
        switch context.family {
        case .systemSmall:
            limit = 1
        case .systemMedium:
            limit = 2
        default:
            limit = 1
        }
        
        let arsenals = fetchArsenals(limit: limit)
        let entry = ArsenalWidgetEntry(date: currentDate, arsenals: arsenals)
        
        // Refresh timeline every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        
        completion(timeline)
    }
    
    // MARK: - Core Data Fetch
    private func fetchArsenals(limit: Int) -> [ArsenalData] {
        let persistenceController = PersistenceController.shared
        let context = persistenceController.container.viewContext
        
        let fetchRequest: NSFetchRequest<Arsenal> = Arsenal.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isCompleted == false")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \Arsenal.createdDate, ascending: false)
        ]
        fetchRequest.fetchLimit = limit
        
        do {
            let results = try context.fetch(fetchRequest)
            return results.map { arsenal in
                ArsenalData(
                    id: UUID(), // Simple unique ID for each fetch
                    title: arsenal.title ?? "Untitled",
                    arsenalDescription: arsenal.arsenalDescription,
                    startDate: arsenal.startDate,
                    endDate: arsenal.endDate,
                    isCompleted: arsenal.isCompleted
                )
            }
        } catch {
            print("Error fetching arsenals: \(error)")
            return []
        }
    }
    
    private func getSampleArsenals() -> [ArsenalData] {
        return [
            ArsenalData(
                id: UUID(),
                title: "Sample Arsenal",
                arsenalDescription: "This is a sample arsenal",
                startDate: Date(),
                endDate: Date().addingTimeInterval(3600),
                isCompleted: false
            )
        ]
    }
}

// MARK: - Widget Views
struct ArsenalWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: ArsenalWidgetProvider.Entry
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(arsenals: entry.arsenals)
        case .systemMedium:
            MediumWidgetView(arsenals: entry.arsenals)
        default:
            SmallWidgetView(arsenals: entry.arsenals)
        }
    }
}

// MARK: - Small Widget (1 Arsenal)
struct SmallWidgetView: View {
    let arsenals: [ArsenalData]
    
    var body: some View {
        if let arsenal = arsenals.first {
            Text(arsenal.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(3)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("No Arsenals")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Medium Widget (2 Arsenals)
struct MediumWidgetView: View {
    let arsenals: [ArsenalData]
    
    var body: some View {
        if arsenals.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("No Arsenals")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Upcoming Arsenals")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                
                ForEach(Array(arsenals.prefix(2))) { arsenal in
                    WidgetArsenalRowView(arsenal: arsenal, isCompact: true)
                    if arsenal.id != arsenals.prefix(2).last?.id {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Widget Arsenal Row View
struct WidgetArsenalRowView: View {
    let arsenal: ArsenalData
    var isCompact: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 2 : 4) {
            Text(arsenal.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundColor(.primary)
            
            if let description = arsenal.arsenalDescription, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            
            if let startDate = arsenal.startDate, let endDate = arsenal.endDate {
                HStack(spacing: 4) {
                    Text(startDate, style: .date)
                    Text("—")
                    Text(endDate, style: .date)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            } else if let startDate = arsenal.startDate {
                Text(startDate, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if let endDate = arsenal.endDate {
                Text("Until: \(endDate, style: .date)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isCompact ? 6 : 10)
    }
}

// MARK: - Widget Configuration
@main
struct AttentionArsenalWidget: Widget {
    let kind: String = "AttentionArsenalWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ArsenalWidgetProvider()) { entry in
            ArsenalWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(uiColor: UIColor { traitCollection in
                        traitCollection.userInterfaceStyle == .dark ? .black : .systemBackground
                    })
                }
        }
        .configurationDisplayName("Arsenal Reminders")
        .description("View your upcoming arsenals")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview
struct AttentionArsenalWidget_Previews: PreviewProvider {
    static var previews: some View {
        let sampleArsenals = [
            ArsenalData(
                id: UUID(),
                title: "Sample Arsenal 1",
                arsenalDescription: "This is a sample description",
                startDate: Date(),
                endDate: Date().addingTimeInterval(86400),
                isCompleted: false
            ),
            ArsenalData(
                id: UUID(),
                title: "Sample Arsenal 2",
                arsenalDescription: "Another sample",
                startDate: Date().addingTimeInterval(86400),
                endDate: Date().addingTimeInterval(172800),
                isCompleted: false
            )
        ]
        
        Group {
            ArsenalWidgetEntryView(entry: ArsenalWidgetEntry(date: Date(), arsenals: sampleArsenals))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            ArsenalWidgetEntryView(entry: ArsenalWidgetEntry(date: Date(), arsenals: sampleArsenals))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}

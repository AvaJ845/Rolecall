import WidgetKit
import SwiftUI

/// One widget, small + medium. Reads the board snapshot the app wrote to the App Group
/// container (falling back to the copy bundled in the extension). The timeline reload is
/// the only refresh — no BGTask, no network here. Calm, matches the app.
@main
struct RolecallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RolecallBoard", provider: BoardProvider()) { entry in
            RolecallWidgetView(entry: entry)
                .containerBackground(Color("Paper"), for: .widget)
        }
        .configurationDisplayName("Fresh design roles")
        .description("Product-design roles live today, and the newest ones.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BoardEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
    let totalCount: Int
    let newest: [Role]
    let generatedUTC: Date?
}

struct BoardProvider: TimelineProvider {

    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: Date(), todayCount: 6, totalCount: 600,
                   newest: [], generatedUTC: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 3, to: Date())
            ?? Date().addingTimeInterval(3 * 3600)
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
    }

    private func loadBoard() -> Board {
        if let shared = SharedContainer.currentBoard() { return shared }
        if let url = Bundle.main.url(forResource: "board", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let board = try? Board.decode(from: data) {
            return board
        }
        return .empty
    }

    private func makeEntry() -> BoardEntry {
        let board = loadBoard()
        let startOfToday = Calendar.current.startOfDay(for: Date())
        // The widget speaks for the design vertical the app leads with, not the PM roles.
        let sorted = board.roles
            .filter { RoleFilter.designFamilies.contains($0.family) }
            .sorted { $0.freshnessDate > $1.freshnessDate }
        let today = sorted.filter { $0.freshnessDate >= startOfToday }
        return BoardEntry(
            date: Date(),
            todayCount: today.count,
            totalCount: board.roles.count,
            newest: Array(sorted.prefix(2)),
            generatedUTC: board.generatedUTC == .distantPast ? nil : board.generatedUTC
        )
    }
}

struct RolecallWidgetView: View {
    let entry: BoardEntry
    @Environment(\.widgetFamily) private var family

    private var headlineCount: Int { entry.todayCount > 0 ? entry.todayCount : entry.totalCount }
    private var headlineWord: String { entry.todayCount > 0 ? "today" : "live now" }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
            Text("\(headlineCount)")
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
                .foregroundStyle(Color("Ink"))
            Text("fresh \(headlineCount == 1 ? "role" : "roles") \(headlineWord)")
                .font(.caption)
                .foregroundStyle(Color("InkSecondary"))

            if family == .systemMedium {
                Spacer(minLength: 2)
                ForEach(entry.newest) { role in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(role.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color("Ink"))
                            .lineLimit(1)
                        Text(role.company)
                            .font(.caption2)
                            .foregroundStyle(Color("InkSecondary"))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headlineCount) fresh roles \(headlineWord) on Rolecall")
    }
}

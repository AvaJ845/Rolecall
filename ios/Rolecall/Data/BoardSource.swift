import Foundation

/// Where a fresher board comes from. One configurable constant, by design: the app
/// talks to exactly one host and nothing else.
enum BoardSource {

    /// Published by the `web/` build to Cloudflare Pages, served at the rolecalljobs.com
    /// apex. Until the custom domain is attached it fails to resolve; `BoardStore` treats
    /// any non-success as "no update" and keeps the bundled snapshot.
    static let remoteURL = URL(string: "https://rolecalljobs.com/board.json")!

    /// The snapshot shipped inside the app bundle, copied from `data/board.json` at build.
    static func bundledBoard() -> Board {
        guard let url = Bundle.main.url(forResource: "board", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let board = try? Board.decode(from: data)
        else { return .empty }
        return board
    }
}

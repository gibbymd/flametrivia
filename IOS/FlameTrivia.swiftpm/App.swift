import SwiftUI

@main
struct FlameTestTriviaApp: App {
    @StateObject private var store: ScoreStore
    @StateObject private var game: Game

    init() {
        let store = ScoreStore()
        _store = StateObject(wrappedValue: store)
        _game = StateObject(wrappedValue: Game(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(game)
        }
    }
}

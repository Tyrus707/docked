import Foundation

// A collection that fills itself. Every rule that is set must hold.
struct SmartCollection: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var console: String? = nil
    var status: Entry.Status? = nil
    var favorite = false
    var neverPlayed = false
    var playedWithin: Int? = nil   // days
    var notPlayedFor: Int? = nil
    var moreThanHours: Int? = nil
    var addedWithin: Int? = nil
    var empty: Bool { console == nil && status == nil && !favorite && !neverPlayed && playedWithin == nil && notPlayedFor == nil && moreThanHours == nil && addedWithin == nil }
    func holds(_ g: Game, _ e: Entry, now: Date = Date()) -> Bool {
        func days(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86400) }
        if let c = console, consoleOf(g.titleID) != c { return false }
        if let s = status, e.status != s { return false }
        if favorite && !e.favorite { return false }
        if neverPlayed && e.lastPlayed != nil { return false }
        if let n = playedWithin { guard let l = e.lastPlayed, l >= days(n) else { return false } }
        if let n = notPlayedFor { guard let l = e.lastPlayed, l < days(n) else { return false } }
        if let h = moreThanHours, e.seconds < Double(h) * 3600 { return false }
        if let n = addedWithin, e.added < days(n) { return false }
        return true
    }
    static let ready: [SmartCollection] = [SmartCollection(name: "Unfinished", status: .playing), SmartCollection(name: "Played This Month", playedWithin: 30), SmartCollection(name: "Not Tried Yet", neverPlayed: true), SmartCollection(name: "Come Back To", status: .playing, notPlayedFor: 30)]
}

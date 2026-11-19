// ReviewPrompt.swift
// Shop Math
//
// Decides when to show Apple's "rate this app" prompt. Ratings drive App Store search ranking,
// but asking too early or too often annoys people, so the app asks only someone who has come back
// on at least three different days and finished at least three tasks, at most once per app
// version, and never within four months of the last ask. iOS also limits the prompt to three
// times a year and may skip it on its own.
//
// Apple's guidelines say to ask after the person finishes something, at a natural pause. So
// ContentView in ShopMathApp.swift records each day the app comes to the foreground, and
// askForReviewIfDue in Views/Components.swift is called right after a finished task: adding a
// board to the lumber list, getting an answer with = on the Fractions tab, or going back from a
// planner to the Planners list.

import Foundation

enum ReviewPrompt {
    static let daysUsedKey = "review_daysUsed"
    static let lastDayKey = "review_lastDay"
    static let askedVersionKey = "review_askedVersion"
    static let lastAskKey = "review_lastAsk"
    static let finishedTasksKey = "review_finishedTasks"

    /// Distinct days of use before the first ask.
    static let minimumDays = 3
    /// Finished tasks before the first ask.
    static let minimumFinishedTasks = 3

    /// Counts one finished task.
    static func recordFinishedTask(_ d: UserDefaults = .standard) {
        d.set(d.integer(forKey: finishedTasksKey) + 1, forKey: finishedTasksKey)
    }
    /// Days between asks, across versions.
    static let minimumDaysBetweenAsks = 120.0

    /// Counts today as a day of use, once per calendar day.
    static func recordUse(now: Date = Date(), calendar: Calendar = .current, _ d: UserDefaults = .standard) {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        guard d.string(forKey: lastDayKey) != day else { return }
        d.set(day, forKey: lastDayKey)
        d.set(d.integer(forKey: daysUsedKey) + 1, forKey: daysUsedKey)
    }

    /// True when it's a good time to ask.
    static func shouldAsk(version: String, now: Date = Date(), _ d: UserDefaults = .standard) -> Bool {
        guard d.integer(forKey: daysUsedKey) >= minimumDays,
              d.integer(forKey: finishedTasksKey) >= minimumFinishedTasks else { return false }
        guard d.string(forKey: askedVersionKey) != version else { return false }
        if let last = d.object(forKey: lastAskKey) as? Date,
           now.timeIntervalSince(last) < minimumDaysBetweenAsks * 86_400 { return false }
        return true
    }

    /// Records that the prompt was requested for this version.
    static func markAsked(version: String, now: Date = Date(), _ d: UserDefaults = .standard) {
        d.set(version, forKey: askedVersionKey)
        d.set(now, forKey: lastAskKey)
    }
}

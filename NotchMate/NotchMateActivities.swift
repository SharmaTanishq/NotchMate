//
//  NotchMateActivities.swift
//  NotchMate
//

import NookComponents

@MainActor
final class NotchMateActivities {
    static let shared = NotchMateActivities()
    let queue = NookActivityQueue()
    private init() {}
}

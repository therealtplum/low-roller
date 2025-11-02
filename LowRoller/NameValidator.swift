//
//  NameValidator.swift
//  Name validation and reservation system
//

import Foundation

enum NameValidator {
    
    // All reserved names (case-insensitive)
    private static let reservedNames: Set<String> = {
        var names = Set<String>()
        
        // House/System names
        names.insert("🎰 Casino (House)".lowercased())
        names.insert("Casino".lowercased())
        names.insert("House".lowercased())
        names.insert("The House".lowercased())
        
        // All bot names from BotRoster
        let allBots = BotRoster.amateurs + BotRoster.pros
        for bot in allBots {
            names.insert(bot.name.lowercased())
        }
        
        return names
    }()
    
    /// Check if a name is valid (not reserved)
    static func isValidName(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty && !reservedNames.contains(normalized)
    }
    
    /// Clean a name and return a valid version
    static func sanitizeName(_ name: String, fallback: String = "Player") -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return fallback
        }
        
        if isValidName(trimmed) {
            return trimmed
        }
        
        // If name is reserved, append a number until we find a valid one
        var counter = 1
        var candidate = "\(trimmed) \(counter)"
        while !isValidName(candidate) && counter < 100 {
            counter += 1
            candidate = "\(trimmed) \(counter)"
        }
        
        return isValidName(candidate) ? candidate : fallback
    }
}

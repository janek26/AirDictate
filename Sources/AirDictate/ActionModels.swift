import Foundation
import CoreGraphics

enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case command, option, control, shift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .command: return "\u{2318} Command"
        case .option:  return "\u{2325} Option"
        case .control: return "\u{2303} Control"
        case .shift:   return "\u{21E7} Shift"
        }
    }

    var cgEventFlag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option:  return .maskAlternate
        case .control: return .maskControl
        case .shift:   return .maskShift
        }
    }
}

struct KeyStrokeAction: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: [ModifierKey]

    var displayName: String {
        let name = keyDisplayName(for: keyCode)
        guard !modifiers.isEmpty else { return name }
        let modNames = modifiers.map(\.displayName).joined(separator: " ")
        return "\(modNames) \(name)"
    }
}

// MARK: - Key code helpers

private let keyDisplayNames: [UInt16: String] = [
    36: "Return",
    49: "Space",
    53: "Escape",
    48: "Tab",
    51: "Delete",
    117: "Delete Forward",
    122: "F1", 120: "F2", 99: "F3", 118: "F4",
    96: "F5", 97: "F6", 98: "F7", 100: "F8",
    101: "F9", 109: "F10", 103: "F11", 111: "F12",
    126: "\u{2191}", 125: "\u{2193}", 123: "\u{2190}", 124: "\u{2192}",
    115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    24: "+", 27: "-", 67: "*", 75: "/",
    18: "1", 19: "2", 20: "3", 21: "4",
    23: "5", 22: "6", 26: "7", 28: "8",
    25: "9", 29: "0",
    12: "Q", 13: "W", 14: "E", 15: "R",
    17: "T", 16: "Y", 32: "U", 34: "I",
    31: "O", 35: "P",
    0: "A", 1: "S", 2: "D", 3: "F",
    5: "G", 4: "H", 38: "J", 40: "K",
    37: "L",
    6: "Z", 7: "X", 8: "C", 9: "V",
    11: "B", 45: "N", 46: "M",
    33: "[", 30: "]", 42: "\\", 41: ";",
    39: "'", 43: ",", 47: ".", 44: "/",
    50: "`",
]

func keyDisplayName(for keyCode: UInt16) -> String {
    keyDisplayNames[keyCode] ?? "Key \(keyCode)"
}

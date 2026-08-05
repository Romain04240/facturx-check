import SwiftUI

/// Le thème choisi dans les réglages.
///
/// La teinte de l'application vient du bleu de son icône (#00BCF5, teinte
/// 194°), assombrie jusqu'à ce qu'un libellé blanc posé dessus reste lisible :
/// #007DA3 en clair, #009DCC en sombre. Elle est déclarée une fois dans
/// `AccentColor` du catalogue, et macOS s'en sert partout.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Système"
        case .light:  return "Clair"
        case .dark:   return "Sombre"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// `nil` laisse la fenêtre suivre le réglage du Mac.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

extension Color {
    /// Le marine du fond de l'icône. Sert d'arrière-plan discret, jamais de
    /// couleur de texte : sur blanc il passe le contraste, mais l'application
    /// n'a aucune raison d'écrire en bleu.
    static let iconNavy = Color(red: 0x00 / 255, green: 0x2B / 255, blue: 0x58 / 255)
}

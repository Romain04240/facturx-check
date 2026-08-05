import SwiftUI
import FacturXKit

/// Comment un rapport se donne à voir : les couleurs, les symboles, et la
/// version texte qu'on colle dans un courriel au prestataire qui a produit la
/// facture — c'est presque toujours la suite logique quand un contrôle échoue.

extension FacturXReport.Outcome {
    var title: String {
        switch self {
        case .sound:      return "Facture électronique valide"
        case .flawed:     return "Facture structurée, mais des contrôles échouent"
        case .notFacturX: return "Ce n'est pas une facture électronique"
        case .unreadable: return "Fichier illisible"
        }
    }

    var detail: String? {
        switch self {
        case .sound:
            return "Le PDF porte une facture structurée exploitable par votre destinataire."
        case .flawed:
            return "Le XML est présent, mais un destinataire automatisé peut rejeter le document."
        case .notFacturX(let reason), .unreadable(let reason):
            return reason
        }
    }

    var symbol: String {
        switch self {
        case .sound:      return "checkmark.seal.fill"
        case .flawed:     return "exclamationmark.triangle.fill"
        case .notFacturX: return "doc.questionmark.fill"
        case .unreadable: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sound:      return .green
        case .flawed:     return .orange
        case .notFacturX: return .secondary
        case .unreadable: return .red
        }
    }
}

extension FacturXReport.Check.Level {
    var symbol: String {
        switch self {
        case .passed:  return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .failed:  return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .passed:  return .green
        case .warning: return .orange
        case .failed:  return .red
        }
    }
}

extension FacturXReport {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// La même mise en forme que celle des messages de contrôle, qui vit dans
    /// la bibliothèque : sinon l'app écrit « 1 200,00 € » dans son tableau et
    /// « 1200 » dans la phrase juste au-dessus, sur le même montant.
    func money(_ value: Decimal?) -> String? {
        value.map { AmountFormat.money($0, currency: invoice?.currencyCode) }
    }

    /// Le rapport en texte brut, prêt à coller. Un contrôle qui échoue se
    /// règle en écrivant à celui qui a émis la facture, pas dans cette fenêtre.
    var plainText: String {
        var lines = ["\(fileName) — \(outcome.title)"]
        if let detail = outcome.detail { lines.append(detail) }

        if let invoice {
            lines.append("")
            if let number = invoice.number { lines.append("Numéro : \(number)") }
            if let date = invoice.issueDate {
                lines.append("Date d'émission : \(Self.dayFormatter.string(from: date))")
            }
            if let seller = invoice.sellerName { lines.append("Émetteur : \(seller)") }
            if let buyer = invoice.buyerName { lines.append("Destinataire : \(buyer)") }
            if let ht = money(invoice.totalHT) { lines.append("Total HT : \(ht)") }
            if let vat = money(invoice.totalVAT) { lines.append("Total TVA : \(vat)") }
            if let ttc = money(invoice.totalTTC) { lines.append("Total TTC : \(ttc)") }
        }

        if !checks.isEmpty {
            lines.append("")
            lines.append("Contrôles")
            for check in checks {
                let mark = check.level == .passed ? "OK" : (check.level == .warning ? "!" : "ÉCHEC")
                lines.append("[\(mark)] \(check.message)")
                if check.level != .passed, let consequence = check.consequence {
                    lines.append("       \(consequence)")
                }
            }
        }

        lines.append("")
        lines.append("Vérifié avec Factur-X Check — analyse locale, aucun envoi réseau.")
        return lines.joined(separator: "\n")
    }
}

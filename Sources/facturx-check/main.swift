import Foundation
import FacturXKit

/// L'outil en ligne de commande. Toute l'analyse vit dans `FacturXReport` :
/// ici il ne reste que la mise en forme, pour que la commande et
/// l'application ne puissent jamais répondre différemment sur le même
/// fichier.

let useColor = isatty(fileno(stdout)) == 1

func paint(_ text: String, _ code: String) -> String {
    useColor ? "\u{001B}[\(code)m\(text)\u{001B}[0m" : text
}

func field(_ label: String, _ value: String?) {
    guard let value, !value.isEmpty else { return }
    print("  \(paint(label.padding(toLength: 22, withPad: " ", startingAt: 0), "2"))\(value)")
}

func money(_ value: Decimal?, _ currency: String?) -> String? {
    value.map { AmountFormat.money($0, currency: currency) }
}

let dateOnly: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return formatter
}()

let arguments = CommandLine.arguments.dropFirst()
let wantsXML = arguments.contains("--xml")
let paths = arguments.filter { !$0.hasPrefix("--") }

guard !paths.isEmpty else {
    print("""
    facturx-check — vérifie qu'un PDF est une facture Factur-X valide.

    USAGE
      facturx-check <fichier.pdf> [autres.pdf…] [--xml]

    OPTIONS
      --xml   affiche le XML embarqué en plus du rapport

    Rien n'est envoyé sur le réseau : tout est analysé localement.
    Code de sortie 0 si tous les fichiers sont conformes, 1 sinon.
    """)
    exit(2)
}

var allSound = true

for path in paths {
    let report = FacturXReport.analyse(fileURL: URL(fileURLWithPath: path))
    print("\n\(paint("▸ \(report.fileName)", "1"))")

    switch report.outcome {
    case .unreadable(let reason), .notFacturX(let reason):
        print("  \(paint("✗", "31")) \(reason)")
        allSound = false
        continue
    case .sound, .flawed:
        print("  \(paint("✓", "32")) XML Factur-X trouvé (\(report.xml?.count ?? 0) octets)")
    }

    if let invoice = report.invoice {
        print("\n\(paint("  Contenu", "1"))")
        field("Type", invoice.isCreditNote ? "Avoir (381)" : "Facture (\(invoice.documentTypeCode ?? "?"))")
        field("Numéro", invoice.number)
        field("Date d'émission", invoice.issueDate.map { dateOnly.string(from: $0) })
        field("Échéance", invoice.dueDate.map { dateOnly.string(from: $0) })
        field("Émetteur", invoice.sellerName)
        field("SIRET émetteur", invoice.sellerLegalID)
        field("TVA émetteur", invoice.sellerVATNumber)
        field("Destinataire", invoice.buyerName)
        field("Total HT", money(invoice.totalHT, invoice.currencyCode))
        field("Total TVA", money(invoice.totalVAT, invoice.currencyCode))
        field("Total TTC", money(invoice.totalTTC, invoice.currencyCode))
        field("Reste à payer", money(invoice.duePayable, invoice.currencyCode))

        if !invoice.vatBreakdown.isEmpty {
            print("\n\(paint("  Ventilation de TVA", "1"))")
            for row in invoice.vatBreakdown {
                let rate = AmountFormat.rate(row.rate).padding(toLength: 22, withPad: " ", startingAt: 0)
                let base = AmountFormat.money(row.baseHT, currency: invoice.currencyCode)
                let tax = AmountFormat.money(row.amount, currency: invoice.currencyCode)
                print("  \(paint(rate, "2"))base \(base) — taxe \(tax)")
            }
        }
    }

    print("\n\(paint("  Contrôles", "1"))")
    for check in report.checks {
        switch check.level {
        case .passed:  print("  \(paint("✓", "32")) \(check.message)")
        case .warning: print("  \(paint("!", "33")) \(check.message)")
        case .failed:  print("  \(paint("✗", "31")) \(check.message)")
        }
        if let consequence = check.consequence, check.level != .passed {
            print("      \(paint(consequence, "2"))")
        }
    }

    if wantsXML, let xml = report.xmlString {
        print("\n\(paint("  XML embarqué", "1"))")
        print(xml)
    }

    if !report.outcome.isSound { allSound = false }
}

print("")
print(allSound
      ? paint("Tous les fichiers sont exploitables comme factures électroniques.", "32")
      : paint("Au moins un fichier pose problème — voir ci-dessus.", "31"))
exit(allSound ? 0 : 1)

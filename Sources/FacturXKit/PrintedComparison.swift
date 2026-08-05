import Foundation

/// Le rapprochement entre ce qui est *imprimé* sur la page et ce que le XML
/// *déclare*.
///
/// C'est la seule divergence que ni l'humain ni la machine ne peuvent voir
/// seuls : le client lit la page, le logiciel du destinataire lit le XML, et
/// si les deux ne disent pas la même chose, personne ne s'en aperçoit avant
/// le rapprochement bancaire. Un générateur qui recalcule mal, un modèle
/// d'impression resté sur l'ancien taux, une facture rééditée sans
/// régénérer le XML : ça arrive, et ça ne se voit nulle part ailleurs.
///
/// Ces contrôles vivent à part de `FacturXReport.evaluate` parce qu'ils
/// demandent une entrée que l'analyse n'a pas : le texte lu par un OCR, qui
/// coûte quelques secondes par page et n'est demandé qu'à la main. La règle
/// tient quand même — ils sont dans la bibliothèque, pas dans une vue, pour
/// que la commande puisse les rendre un jour sans les réécrire.
extension FacturXReport {

    /// Aucun de ces contrôles n'échoue, ils avertissent.
    ///
    /// L'OCR se trompe : il lit « 1 693,2O » avec un O, coupe une ligne au
    /// mauvais endroit, ignore un filigrane. Condamner une facture sur cette
    /// base ferait exactement ce que l'outil reproche aux autres — annoncer
    /// une erreur qui n'existe pas. Ce qui est dit ici est donc toujours
    /// « je ne l'ai pas retrouvé », jamais « c'est faux ».
    public static func comparePrinted(_ text: String,
                                      with invoice: FacturXParsedInvoice) -> [Check] {
        var checks: [Check] = []
        let page = folded(text)
        let printedAmounts = amounts(in: text)

        func money(_ value: Decimal) -> String {
            AmountFormat.money(value, currency: invoice.currencyCode)
        }

        if let number = invoice.number, !number.isEmpty {
            checks.append(page.contains(folded(number))
                ? Check(.passed, "Le numéro \(number) figure bien sur la page")
                : Check(.warning, "Le numéro \(number) ne se retrouve pas dans le texte de la page",
                        consequence: "Le XML et la page ne désignent peut-être pas la même facture — à moins que l'OCR ne l'ait mal lu."))
        }

        if let seller = invoice.sellerName, !seller.isEmpty {
            checks.append(page.contains(folded(seller))
                ? Check(.passed, "L'émetteur \(seller) figure bien sur la page")
                : Check(.warning, "L'émetteur \(seller) ne se retrouve pas dans le texte de la page",
                        consequence: "Le nom déclaré dans le XML n'est pas celui qu'on lit sur la facture."))
        }

        if let date = invoice.issueDate {
            checks.append(printedDateForms(date).contains { page.contains($0) }
                ? Check(.passed, "La date d'émission figure bien sur la page")
                : Check(.warning, "La date d'émission déclarée ne se retrouve pas sur la page",
                        consequence: "La date fait courir les délais de paiement : deux dates différentes, ce sont deux échéances différentes."))
        }

        // Le montant est le rapprochement qui compte : c'est celui que le
        // client paie et celui que le logiciel du destinataire comptabilise.
        for (label, value) in [("total TTC", invoice.totalTTC), ("total HT", invoice.totalHT)] {
            guard let value else { continue }
            let found = printedAmounts.contains { abs($0 - value) <= cent }
            checks.append(found
                ? Check(.passed, "Le \(label) \(money(value)) figure bien sur la page")
                : Check(.warning, "Le \(label) déclaré, \(money(value)), ne se lit nulle part sur la page",
                        consequence: "Votre client lit la page, son logiciel lit le XML. S'ils ne portent pas la même somme, l'écart n'apparaîtra qu'au paiement."))
        }

        return checks
    }

    // MARK: - Lire des nombres dans du texte

    /// Tous les nombres qu'on peut lire sur la page, quelle que soit leur
    /// écriture.
    ///
    /// Un même montant s'imprime « 1 693,20 », « 1 693.20 », « 1,693.20 » ou
    /// « 1693,20 » selon le générateur, et l'OCR ajoute ses propres espaces.
    /// Quand l'écriture est ambiguë — « 1.693 » est-il mille six cent
    /// quatre-vingt-treize ou un virgule six ? — les deux lectures sont
    /// retenues : il s'agit de savoir si la somme *figure* sur la page, et une
    /// interprétation de trop ne fait que rendre le contrôle plus prudent.
    static func amounts(in text: String) -> Set<Decimal> {
        var found: Set<Decimal> = []
        var run = ""

        func flush() {
            defer { run = "" }
            let trimmed = run.trimmingCharacters(in: CharacterSet(charactersIn: " \u{00A0}\u{202F}',."))
            guard trimmed.contains(where: \.isNumber) else { return }
            found.formUnion(readings(of: trimmed))
        }

        for character in text {
            if character.isNumber || " \u{00A0}\u{202F}',.".contains(character) {
                run.append(character)
            } else {
                flush()
            }
        }
        flush()
        return found
    }

    /// Les lectures possibles d'une suite de chiffres et de séparateurs.
    private static func readings(of raw: String) -> [Decimal] {
        // Les espaces et l'apostrophe ne séparent jamais que des milliers.
        let text = raw.filter { !" \u{00A0}\u{202F}'".contains($0) }
        let posix = Locale(identifier: "en_US_POSIX")

        func decimal(_ string: String) -> Decimal? {
            Decimal(string: string, locale: posix)
        }

        let hasComma = text.contains(","), hasDot = text.contains(".")

        if hasComma && hasDot {
            // Le dernier séparateur est le décimal ; l'autre groupe les
            // milliers. Aucune ambiguïté, quel que soit le pays.
            let decimalSeparator: Character = text.lastIndex(of: ",")! > text.lastIndex(of: ".")! ? "," : "."
            let cleaned = text.filter { $0.isNumber || $0 == decimalSeparator }
                              .replacingOccurrences(of: String(decimalSeparator), with: ".")
            return [decimal(cleaned)].compactMap { $0 }
        }

        guard let separator: Character = hasComma ? "," : (hasDot ? "." : nil) else {
            return [decimal(text)].compactMap { $0 }
        }

        // Un seul type de séparateur, une seule occurrence : décimal ou
        // milliers, on ne peut pas trancher, donc on garde les deux.
        let asDecimal = decimal(text.replacingOccurrences(of: String(separator), with: "."))
        let asThousands = decimal(text.replacingOccurrences(of: String(separator), with: ""))
        return [asDecimal, asThousands].compactMap { $0 }
    }

    // MARK: - Comparer du texte que l'OCR a maltraité

    /// Minuscules, sans accents, espaces unifiées : l'OCR rend « BLANC-CONSEIL »
    /// aussi bien que « Blanc-Conseil », et « Bréal » sans son accent une fois
    /// sur deux.
    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// Les écritures sous lesquelles une date peut figurer sur une facture
    /// française. Le XML, lui, n'en connaît qu'une.
    private static func printedDateForms(_ date: Date) -> [String] {
        ["dd/MM/yyyy", "d MMMM yyyy", "dd-MM-yyyy", "yyyy-MM-dd", "dd.MM.yyyy", "d MMM yyyy"]
            .map { format in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "fr_FR")
                formatter.timeZone = TimeZone(identifier: "UTC")
                formatter.dateFormat = format
                return folded(formatter.string(from: date))
            }
    }
}

import Foundation

/// The values read back out of a supplier's Cross Industry Invoice.
///
/// Deliberately a different type from `FacturXInvoiceData` (which we *write*):
/// everything here is optional because it comes from someone else's software
/// and we control none of it. Forcing it into the writer's shape would mean
/// inventing defaults for missing fields and then presenting invented data as
/// if it had been read from the invoice.
public struct FacturXParsedInvoice: Sendable, Equatable {
    public var guidelineURN: String?
    public var documentTypeCode: String?
    public var number: String?
    public var issueDate: Date?
    public var dueDate: Date?

    /// La devise de la facture (BT-5), telle que le document la déclare.
    /// Mention obligatoire : c'est elle qu'un destinataire contrôle.
    public var declaredCurrencyCode: String?

    /// La devise portée par l'attribut `currencyID` des montants. Un secours
    /// pour la lecture quand BT-5 manque — pas un remplacement : afficher
    /// « 1 200,00 € » ne rend pas conforme une facture qui n'a jamais dit
    /// qu'elle comptait en euros, et le contrôle doit continuer de le voir.
    public var amountCurrencyCode: String?

    /// La devise de déclaration fiscale (BT-6), quand elle diffère. Elle sert
    /// à écarter le montant de TVA qui l'accompagne, pas à afficher.
    public var taxCurrencyCode: String?

    /// Celle avec laquelle écrire les montants.
    public var currencyCode: String? { declaredCurrencyCode ?? amountCurrencyCode }

    public var sellerName: String?
    public var sellerLegalID: String?
    public var sellerVATNumber: String?
    public var buyerName: String?

    public var totalHT: Decimal?
    public var totalVAT: Decimal?
    public var totalTTC: Decimal?
    public var duePayable: Decimal?
    public var vatBreakdown: [VATBreakdownRow] = []

    /// The profile the sender declared, matched against the ones we know.
    /// Nil when the URN is absent or from a profile we don't recognise —
    /// which does not make the file unreadable, only unlabelled.
    public var profile: FacturXProfile? {
        guard let guidelineURN else { return nil }
        return FacturXProfile.allCases.first { guidelineURN.hasSuffix($0.guidelineURN) || $0.guidelineURN == guidelineURN }
    }

    /// A credit note reverses a charge, so an app that treats 381 like 380
    /// would book a refund as an expense.
    public var isCreditNote: Bool { documentTypeCode == "381" }

    public init() {}
}

/// Reads a Cross Industry Invoice into `FacturXParsedInvoice`.
///
/// Element *paths* rather than bare names do the disambiguating: `ram:ID`
/// appears in a dozen unrelated places in CII (document number, seller legal
/// ID, VAT registration, guideline URN…), so matching on the name alone
/// silently mixes them up. Namespace processing is on, so a sender using
/// different prefixes than ours parses identically.
public enum FacturXParser {
    public static func parse(_ xml: Data) -> FacturXParsedInvoice? {
        let delegate = Delegate()
        let parser = XMLParser(data: xml)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        let invoice = delegate.resolved()
        // A document with neither a number nor a total isn't a parse we should
        // hand to the caller as if it had worked.
        guard invoice.number != nil || invoice.totalTTC != nil else { return nil }
        return invoice
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var result = FacturXParsedInvoice()
        private var path: [String] = []
        private var text = ""
        /// The tax row being read; CII repeats `ApplicableTradeTax` once per rate.
        private var taxAmount: Decimal?
        private var taxBase: Decimal?
        private var taxRate: Decimal?

        /// Les attributs de chaque élément ouvert, empilés en parallèle du
        /// chemin : c'est `currencyID` qui distingue deux montants écrits avec
        /// le même nom d'élément, au même endroit.
        private var attributeStack: [[String: String]] = []

        /// Tous les `TaxTotalAmount` rencontrés, avec leur devise. Le choix
        /// entre eux ne peut se faire qu'à la fin — voir `resolved()`.
        private var taxTotals: [(amount: Decimal, currency: String?)] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            path.append(elementName)
            attributeStack.append(attributes)
            text = ""
            if elementName == "ApplicableTradeTax" {
                taxAmount = nil; taxBase = nil; taxRate = nil
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let currencyID = attributeStack.last?["currencyID"]
            defer { path.removeLast(); attributeStack.removeLast(); text = "" }
            guard !value.isEmpty || elementName == "ApplicableTradeTax" else { return }

            switch true {
            case ends(with: ["GuidelineSpecifiedDocumentContextParameter", "ID"]):
                result.guidelineURN = value
            case ends(with: ["ExchangedDocument", "ID"]):
                result.number = value
            case ends(with: ["ExchangedDocument", "TypeCode"]):
                result.documentTypeCode = value
            case ends(with: ["IssueDateTime", "DateTimeString"]):
                result.issueDate = date(from: value)
            case ends(with: ["DueDateDateTime", "DateTimeString"]):
                result.dueDate = date(from: value)
            case ends(with: ["SellerTradeParty", "Name"]):
                result.sellerName = value
            case ends(with: ["SellerTradeParty", "SpecifiedLegalOrganization", "ID"]):
                result.sellerLegalID = value
            case ends(with: ["SellerTradeParty", "SpecifiedTaxRegistration", "ID"]):
                result.sellerVATNumber = value
            case ends(with: ["BuyerTradeParty", "Name"]):
                result.buyerName = value
            case ends(with: ["InvoiceCurrencyCode"]):
                result.declaredCurrencyCode = value
            case ends(with: ["TaxCurrencyCode"]):
                result.taxCurrencyCode = value
            case ends(with: ["ApplicableTradeTax", "CalculatedAmount"]):
                taxAmount = decimal(from: value)
            case ends(with: ["ApplicableTradeTax", "BasisAmount"]):
                taxBase = decimal(from: value)
            case ends(with: ["ApplicableTradeTax", "RateApplicablePercent"]):
                taxRate = decimal(from: value)
            case elementName == "ApplicableTradeTax":
                if let taxRate, let taxBase, let taxAmount {
                    result.vatBreakdown.append(VATBreakdownRow(rate: taxRate, baseHT: taxBase, amount: taxAmount))
                }
            case ends(with: ["LineTotalAmount"]):
                result.totalHT = decimal(from: value)
            case ends(with: ["TaxTotalAmount"]):
                if let amount = decimal(from: value) {
                    taxTotals.append((amount, currencyID))
                }
            case ends(with: ["GrandTotalAmount"]):
                result.totalTTC = decimal(from: value)
                // Le total TTC est le montant le plus sûrement présent : sa
                // devise sert de secours quand la facture n'a pas déclaré la
                // sienne.
                if result.amountCurrencyCode == nil { result.amountCurrencyCode = currencyID }
            case ends(with: ["DuePayableAmount"]):
                result.duePayable = decimal(from: value)
            default:
                break
            }
        }

        /// Le document lu en entier, une fois tranché ce qui ne pouvait pas
        /// l'être en cours de lecture.
        func resolved() -> FacturXParsedInvoice {
            var invoice = result
            if invoice.amountCurrencyCode == nil {
                // Sans exclure la devise fiscale, ce secours adopterait
                // précisément celle qu'il faut écarter, et désignerait ensuite
                // le mauvais total de TVA comme étant « le bon ».
                invoice.amountCurrencyCode = taxTotals
                    .compactMap(\.currency)
                    .first { $0 != invoice.taxCurrencyCode }
            }
            invoice.totalVAT = taxTotal(of: invoice)
            return invoice
        }

        /// BT-110 (le total de TVA) et BT-111 (la même somme dans la devise de
        /// déclaration fiscale) portent le même nom d'élément, au même
        /// endroit, et ne se distinguent que par `currencyID`. Garder le
        /// dernier lu — ce que fait un parseur écrit sans le savoir — revient à
        /// comparer un total HT en euros à une TVA en francs suisses : « HT +
        /// TVA = TTC » échoue alors sur une facture parfaitement valide, et
        /// c'est le contrôle sur lequel cet outil est jugé.
        private func taxTotal(of invoice: FacturXParsedInvoice) -> Decimal? {
            guard taxTotals.count > 1 else { return taxTotals.first?.amount }

            if let currency = invoice.currencyCode,
               let match = taxTotals.first(where: { $0.currency == currency }) {
                return match.amount
            }
            // À défaut de savoir laquelle est la bonne, on sait au moins
            // laquelle ne l'est pas.
            if let taxCurrency = invoice.taxCurrencyCode,
               let other = taxTotals.first(where: { $0.currency != taxCurrency }) {
                return other.amount
            }
            // CII écrit le montant de la facture avant celui de la déclaration
            // fiscale. Au-delà, deviner serait deviner.
            return taxTotals.first?.amount
        }

        private func ends(with suffix: [String]) -> Bool {
            guard path.count >= suffix.count else { return false }
            return Array(path.suffix(suffix.count)) == suffix
        }

        /// CII amounts are always `.`-separated regardless of the sender's
        /// locale, so parsing must not follow the device's own settings.
        private func decimal(from value: String) -> Decimal? {
            Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        }

        /// Format 102 (CCYYMMDD) is what Factur-X uses; 610 and 616 appear in
        /// wider CII usage but not for these fields.
        private func date(from value: String) -> Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd"
            return formatter.date(from: value)
        }
    }
}

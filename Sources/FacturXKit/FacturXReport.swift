import Foundation

/// L'analyse d'un PDF, indépendante de la façon dont on l'affiche.
///
/// Elle vivait dans le `main.swift` de l'outil en ligne de commande. L'y
/// laisser aurait fait diverger l'application de la commande dès le premier
/// contrôle ajouté d'un seul côté — et deux outils qui répondent
/// différemment sur le même fichier ne valent ni l'un ni l'autre.
public struct FacturXReport: Sendable, Identifiable {
    public let id = UUID()
    public let fileName: String
    public let outcome: Outcome
    public let invoice: FacturXParsedInvoice?
    public let xml: Data?
    public let checks: [Check]

    public enum Outcome: Sendable, Equatable {
        /// Exploitable comme facture électronique.
        case sound
        /// Le XML est là, mais quelque chose cloche.
        case flawed
        /// Pas de facture structurée du tout.
        case notFacturX(String)
        /// Le fichier n'est pas lisible.
        case unreadable(String)

        public var isSound: Bool { self == .sound }
    }

    public struct Check: Sendable, Identifiable {
        public enum Level: Sendable { case passed, warning, failed }
        public let id = UUID()
        public let level: Level
        public let message: String
        /// Ce que ça implique concrètement — vide quand le contrôle passe.
        public let consequence: String?

        init(_ level: Level, _ message: String, consequence: String? = nil) {
            self.level = level
            self.message = message
            self.consequence = consequence
        }
    }

    public var xmlString: String? {
        xml.map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: - Analyse

    /// Tolérance d'arrondi sur les contrôles d'addition : un centime. En
    /// dessous, c'est la conversion décimale du générateur ; au-dessus, c'est
    /// une erreur de calcul.
    /// Partagée avec le rapprochement OCR/XML, qui compare les mêmes sommes
    /// avec la même indulgence.
    static let cent = Decimal(string: "0.01")!

    public static func analyse(pdf: Data, fileName: String) -> FacturXReport {
        guard pdf.prefix(4) == Data("%PDF".utf8) else {
            return FacturXReport(fileName: fileName,
                                 outcome: .unreadable("Ce fichier n'est pas un PDF."),
                                 invoice: nil, xml: nil, checks: [])
        }

        guard let result = FacturXExtractor.read(from: pdf) else {
            return FacturXReport(
                fileName: fileName,
                outcome: .notFacturX("""
                    Le PDF est lisible, mais il ne porte aucune facture \
                    structurée. Pour un destinataire, c'est une image : il \
                    devra ressaisir les montants ou les faire reconnaître.
                    """),
                invoice: nil, xml: nil, checks: [])
        }

        let checks = evaluate(result.invoice)
        return FacturXReport(fileName: fileName,
                             outcome: checks.contains { $0.level == .failed } ? .flawed : .sound,
                             invoice: result.invoice, xml: result.xml, checks: checks)
    }

    /// Les contrôles, séparés de la lecture du PDF pour qu'ils soient
    /// testables sans avoir à fabriquer un PDF conforme à chaque cas d'erreur.
    static func evaluate(_ invoice: FacturXParsedInvoice) -> [Check] {
        var checks: [Check] = []

        // Les sommes citées dans un message d'échec se lisent comme partout
        // ailleurs dans l'outil, devise comprise : un écart annoncé « 0,02 € »
        // se reconnaît du premier coup d'œil, « 0.02 » se relit deux fois.
        func money(_ value: Decimal) -> String {
            AmountFormat.money(value, currency: invoice.currencyCode)
        }

        if let profile = invoice.profile {
            checks.append(Check(.passed, "Profil déclaré : \(profile.rawValue)"))
        } else if let urn = invoice.guidelineURN {
            checks.append(Check(.warning, "Profil non reconnu : \(urn)",
                                consequence: "Un destinataire strict peut refuser un profil qu'il ne connaît pas."))
        } else {
            checks.append(Check(.failed, "Aucun profil déclaré",
                                consequence: "Le destinataire ne sait pas quelles règles appliquer au document."))
        }

        checks.append(invoice.number?.isEmpty == false
            ? Check(.passed, "Numéro de facture présent")
            : Check(.failed, "Numéro de facture absent",
                    consequence: "C'est une mention obligatoire : la facture est irrégulière."))

        checks.append(invoice.issueDate != nil
            ? Check(.passed, "Date d'émission présente")
            : Check(.failed, "Date d'émission absente",
                    consequence: "Mention obligatoire, et point de départ des délais de paiement."))

        checks.append(invoice.sellerName?.isEmpty == false
            ? Check(.passed, "Émetteur identifié")
            : Check(.failed, "Émetteur absent",
                    consequence: "Sans émetteur, le destinataire ne peut pas rapprocher la facture."))

        checks.append(invoice.buyerName?.isEmpty == false
            ? Check(.passed, "Destinataire identifié")
            : Check(.warning, "Destinataire absent",
                    consequence: "Toléré par certains profils, refusé par d'autres."))

        // Une somme sans sa monnaie ne veut rien dire, et la deviner d'après
        // l'émetteur serait exactement ce que cet outil refuse de faire.
        if let declared = invoice.declaredCurrencyCode, !declared.isEmpty {
            checks.append(Check(.passed, "Devise déclarée : \(declared)"))
        } else if let fallback = invoice.amountCurrencyCode, !fallback.isEmpty {
            checks.append(Check(.warning, "Devise absente du document, lue sur les montants : \(fallback)",
                                consequence: "La devise de la facture est une mention obligatoire. Un destinataire qui la contrôle refuse, même quand elle se devine."))
        } else {
            checks.append(Check(.failed, "Aucune devise",
                                consequence: "Les montants ne disent pas dans quelle monnaie ils sont comptés."))
        }

        // Le contrôle qui attrape le plus d'erreurs de génération. Un
        // destinataire automatisé rejette, et son message est rarement
        // explicite : « erreur de cohérence » n'aide personne.
        if let ht = invoice.totalHT, let vat = invoice.totalVAT, let ttc = invoice.totalTTC {
            let expected = ht + vat
            let gap = abs(ttc - expected)
            checks.append(gap <= cent
                ? Check(.passed, "HT + TVA = TTC")
                : Check(.failed, "HT + TVA donne \(money(expected)), le TTC déclaré est \(money(ttc))",
                        consequence: "Écart de \(money(gap)). La plupart des destinataires rejettent sur ce seul point."))
        } else {
            checks.append(Check(.warning, "Totaux incomplets",
                                consequence: "Le contrôle d'addition n'a pas pu être fait."))
        }

        // MARK: - Les règles du socle européen
        //
        // Elles étaient hors périmètre : l'outil vérifiait la structure et les
        // additions, pas la norme. C'était défendable tant qu'il ne savait rien
        // en dire ; ça ne l'est plus, puisqu'un rejet chez le destinataire cite
        // précisément ces codes-là. Chaque contrôle porte donc le sien, pour
        // qu'on retrouve la règle officielle sans avoir à nous croire.
        //
        // Le périmètre est **explicite plutôt qu'exhaustif** : ce qui n'est pas
        // vérifié n'est pas prétendu. Les règles qui portent sur les lignes de
        // détail (BR-21 à BR-31) ne peuvent pas l'être ici — le lecteur ne les
        // extrait pas.

        // BR-04. Sans code de type, le destinataire ne sait pas s'il reçoit
        // une facture ou un avoir : il crédite ce qu'il devrait débiter.
        switch invoice.documentTypeCode {
        case "380":
            checks.append(Check(.passed, "Type de document : facture (380)"))
        case "381":
            checks.append(Check(.passed, "Type de document : avoir (381)"))
        case let code?:
            checks.append(Check(.warning, "Type de document inhabituel : \(code)",
                                consequence: "BR-04. Le socle attend 380 pour une facture, 381 pour un avoir. Un autre code se comporte différemment chez le destinataire."))
        case nil:
            checks.append(Check(.failed, "Aucun type de document",
                                consequence: "BR-04. Rien ne dit s'il s'agit d'une facture ou d'un avoir : le destinataire peut créditer ce qu'il devrait débiter."))
        }

        // BR-CO-26. L'émetteur doit être identifiable autrement que par son
        // nom — deux entreprises peuvent s'appeler pareil, et le rapprochement
        // comptable se fait sur l'identifiant, jamais sur la raison sociale.
        let emetteurIdentifie = invoice.sellerLegalID?.isEmpty == false
            || invoice.sellerVATNumber?.isEmpty == false
        checks.append(emetteurIdentifie
            ? Check(.passed, "Émetteur identifié par son immatriculation")
            : Check(.failed, "L'émetteur n'a ni immatriculation ni numéro de TVA",
                    consequence: "BR-CO-26. Deux entreprises peuvent porter le même nom : sans identifiant, le destinataire ne sait pas rapprocher la facture d'un fournisseur."))

        // BR-CO-14. Le total de TVA doit être la somme de sa ventilation. Un
        // écart ici veut dire qu'un taux a été oublié dans le détail, ou
        // compté deux fois — et le pied de facture, lui, paraît juste.
        if let vat = invoice.totalVAT, !invoice.vatBreakdown.isEmpty {
            let somme = invoice.vatBreakdown.reduce(Decimal(0)) { $0 + $1.amount }
            let ecart = abs(somme - vat)
            checks.append(ecart <= cent
                ? Check(.passed, "Le total de TVA correspond à sa ventilation")
                : Check(.failed, "La ventilation totalise \(money(somme)) de TVA, le pied de facture en déclare \(money(vat))",
                        consequence: "BR-CO-14. Écart de \(money(ecart)). Un taux manque au détail, ou y figure deux fois."))
        }

        // BR-S-08. Sur chaque taux, la taxe doit être la base multipliée par
        // le taux. C'est le contrôle qui distingue une facture fausse d'une
        // facture mal additionnée : les totaux peuvent tomber juste alors
        // qu'aucune ligne du détail n'est cohérente.
        for row in invoice.vatBreakdown where row.rate > 0 {
            // Arrondi au centime, comme la norme le veut : la comparaison
            // porte sur ce qu'un destinataire recalculera, pas sur une
            // décimale infinie qui ne tombe jamais juste.
            var brut = row.baseHT * row.rate / 100
            var attendu = Decimal()
            NSDecimalRound(&attendu, &brut, 2, .plain)
            let ecart = abs(attendu - row.amount)
            guard ecart > cent else { continue }
            checks.append(Check(.failed,
                                "Au taux de \(AmountFormat.rate(row.rate)) %, \(money(row.baseHT)) donnent \(money(attendu)) de TVA, le document en déclare \(money(row.amount))",
                                consequence: "BR-S-08. Écart de \(money(ecart)) sur ce taux."))
        }
        if invoice.vatBreakdown.contains(where: { $0.rate > 0 })
            && !checks.contains(where: { $0.consequence?.hasPrefix("BR-S-08") == true }) {
            checks.append(Check(.passed, "Chaque taux de TVA retombe sur sa base"))
        }

        // BR-15. Le montant à payer : ce que le destinataire doit virer. Son
        // absence oblige à le recalculer, et deux logiciels ne s'accordent pas
        // toujours sur les acomptes déjà versés.
        if invoice.duePayable == nil {
            checks.append(Check(.warning, "Le montant à payer n'est pas déclaré",
                                consequence: "BR-15. Le destinataire doit le recalculer lui-même, acomptes compris."))
        }

        // La ventilation doit retomber sur le pied de facture, sinon les deux
        // parties de la facture se contredisent.
        if !invoice.vatBreakdown.isEmpty, let ht = invoice.totalHT {
            let sum = invoice.vatBreakdown.reduce(Decimal(0)) { $0 + $1.baseHT }
            let gap = abs(sum - ht)
            checks.append(gap <= cent
                ? Check(.passed, "La ventilation de TVA retombe sur le total HT")
                : Check(.failed, "Les bases ventilées totalisent \(money(sum)), le total HT déclaré est \(money(ht))",
                        consequence: "La ventilation contredit le pied de facture."))
        }

        return checks
    }

    public static func analyse(fileURL: URL) -> FacturXReport {
        guard let data = try? Data(contentsOf: fileURL) else {
            return FacturXReport(fileName: fileURL.lastPathComponent,
                                 outcome: .unreadable("Fichier illisible ou introuvable."),
                                 invoice: nil, xml: nil, checks: [])
        }
        return analyse(pdf: data, fileName: fileURL.lastPathComponent)
    }
}

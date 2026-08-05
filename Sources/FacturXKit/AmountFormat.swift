import Foundation

/// La mise en forme des montants et des taux, au même endroit que les
/// contrôles qui les citent.
///
/// Un contrôle qui échoue nomme des sommes — « HT + TVA donne 1 200,00 € ».
/// Laisser cette mise en forme aux vues n'était pas possible : le nombre est
/// déjà noyé dans une phrase quand l'application le reçoit, et il en sortait
/// des « 1200 » bruts au milieu d'une interface qui écrit « 1 200,00 € »
/// partout ailleurs.
///
/// Le format est celui du français quelle que soit la langue du Mac. C'est un
/// outil français, et le rapport doit se lire pareil partout : dans la
/// commande, qui n'a pas de paquet où déclarer sa langue ; et dans les tests,
/// qui échoueraient sur une machine réglée autrement.
public enum AmountFormat {
    private static let locale = Locale(identifier: "fr_FR")

    /// Un montant avec sa devise : « 1 200,00 € ».
    ///
    /// Sans devise déclarée, le nombre est affiché seul plutôt que supposé en
    /// euros : le reste de la lecture ne suppose jamais ce que le XML tait.
    public static func money(_ value: Decimal, currency: String?) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        if let currency, !currency.isEmpty {
            formatter.numberStyle = .currency
            formatter.currencyCode = currency
        } else {
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    /// Un taux se lit « 20 % » et « 5,5 % », pas « 20.00 % » : virgule
    /// décimale, zéros inutiles retirés, et une espace insécable avant le
    /// signe pour qu'il ne parte pas seul à la ligne suivante.
    public static func rate(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
        return number + "\u{00A0}%"
    }
}

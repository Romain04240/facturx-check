import XCTest
@testable import FacturXKit

/// Ces tests fixent des caractères qu'on ne voit pas à l'écran : l'espace fine
/// insécable des milliers (U+202F) et l'espace insécable qui précède le symbole
/// (U+00A0). Les écrire en clair est ce qui distingue « 1 200,00 € » d'un
/// « 1 200,00 € » composé d'espaces ordinaires, qui se couperait en fin de
/// ligne.
final class AmountFormatTests: XCTestCase {

    func testAmountsAreWrittenInFrench() {
        XCTAssertEqual(AmountFormat.money(Decimal(string: "1200")!, currency: "EUR"),
                       "1\u{202F}200,00\u{A0}€")
        XCTAssertEqual(AmountFormat.money(Decimal(string: "0.02")!, currency: "EUR"),
                       "0,02\u{A0}€")
    }

    /// La devise vient du XML. Quand elle manque, supposer l'euro afficherait
    /// une information que le fichier ne donne pas.
    func testAnAmountWithoutACurrencyKeepsTheNumberAlone() {
        XCTAssertEqual(AmountFormat.money(Decimal(string: "1200")!, currency: nil),
                       "1\u{202F}200,00")
        XCTAssertEqual(AmountFormat.money(Decimal(string: "1200")!, currency: ""),
                       "1\u{202F}200,00")
    }

    func testAForeignCurrencyIsKeptAsDeclared() {
        XCTAssertTrue(AmountFormat.money(Decimal(string: "1200")!, currency: "CHF").contains("CHF"))
    }

    func testRatesDropTheirUselessZeros() {
        XCTAssertEqual(AmountFormat.rate(Decimal(string: "20.00")!), "20\u{A0}%")
        XCTAssertEqual(AmountFormat.rate(Decimal(string: "5.5")!), "5,5\u{A0}%")
    }
}

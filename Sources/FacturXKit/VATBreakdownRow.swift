import Foundation

/// La ventilation de TVA par taux, telle qu'elle figure dans le XML.
///
/// Copiée depuis InvoicioCore plutôt que partagée : cet outil doit rester
/// installable et lisible seul, sans traîner derrière lui une application de
/// facturation entière. La structure est stable et tient en dix lignes — la
/// dupliquer coûte moins que le couplage.
public struct VATBreakdownRow: Sendable, Equatable, Identifiable {
    public let rate: Decimal
    public let baseHT: Decimal
    public let amount: Decimal

    public var id: Decimal { rate }

    public init(rate: Decimal, baseHT: Decimal, amount: Decimal) {
        self.rate = rate
        self.baseHT = baseHT
        self.amount = amount
    }
}

import Foundation

/// The Factur-X conformance level written into the XML and into the PDF's
/// embedded-file metadata.
///
/// Factur-X (identical to Germany's ZUGFeRD 2.x) layers profiles on top of
/// the same UN/CEFACT Cross Industry Invoice syntax: each one is a superset
/// of the previous. `basicWL` — "basic without lines" — is the smallest
/// profile that still carries the full VAT breakdown, which is what makes an
/// invoice legally complete in France, and it avoids committing to the
/// line-level semantics (unit codes, item identifiers) that `basic` and
/// above require. That trade is why it's the default here.
public enum FacturXProfile: String, Sendable, CaseIterable {
    case minimum
    case basicWL
    case basic
    case en16931

    /// The URN the XML must carry in `GuidelineSpecifiedDocumentContextParameter`
    /// — a validator matches on this exact string, so it isn't cosmetic.
    public var guidelineURN: String {
        switch self {
        case .minimum: return "urn:factur-x.eu:1p0:minimum"
        case .basicWL: return "urn:factur-x.eu:1p0:basicwl"
        case .basic: return "urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic"
        case .en16931: return "urn:cen.eu:en16931:2017"
        }
    }

    /// Name as the standard writes it, for badges and reports.
    public var displayName: String {
        switch self {
        case .minimum: return "MINIMUM"
        case .basicWL: return "BASIC WL"
        case .basic: return "BASIC"
        case .en16931: return "EN 16931"
        }
    }

    /// Whether the profile carries individual invoice lines. `minimum` and
    /// `basicWL` deliberately don't.
    public var includesLines: Bool {
        switch self {
        case .minimum, .basicWL: return false
        case .basic, .en16931: return true
        }
    }
}

/// Type codes from UNTDID 1001, the code list Factur-X uses for
/// `TypeCode`. Only the two the app can currently produce are modelled.
public enum FacturXDocumentType: String, Sendable {
    /// Commercial invoice.
    case invoice = "380"
    /// Credit note.
    case creditNote = "381"
}

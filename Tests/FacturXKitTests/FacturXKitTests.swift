import XCTest
@testable import FacturXKit

final class FacturXExtractionTests: XCTestCase {

    /// Ce qui arrive le plus souvent en vrai : un PDF ordinaire, produit par
    /// un traitement de texte. L'outil doit le dire sans ambiguïté plutôt que
    /// de renvoyer un résultat vide qu'on prendrait pour un succès.
    func testAPlainPDFYieldsNothing() {
        let pdf = Data("%PDF-1.4\n%%EOF\n".utf8)
        XCTAssertNil(FacturXExtractor.embeddedXML(in: pdf))
        XCTAssertNil(FacturXExtractor.read(from: pdf))
    }

    func testGarbageIsRejectedRatherThanCrashing() {
        for data in [Data(), Data([0x00, 0xFF]), Data("pas un pdf".utf8)] {
            XCTAssertNil(FacturXExtractor.read(from: data))
        }
    }

    /// Le parseur doit tenir sur du XML tronqué : un PDF corrompu en cours de
    /// transfert produit exactement cela, et l'outil ne doit pas s'arrêter sur
    /// le premier fichier douteux d'un lot.
    func testTruncatedXMLParsesWithoutCrashing() {
        let xml = Data("""
        <?xml version="1.0"?><rsm:CrossIndustryInvoice><rsm:ExchangedDocument>
        """.utf8)
        _ = FacturXParser.parse(xml)
    }

    func testVATBreakdownRowKeepsItsRateAsIdentity() {
        let row = VATBreakdownRow(rate: 20, baseHT: 100, amount: 20)
        XCTAssertEqual(row.id, 20)
    }
}

final class FacturXParsingTests: XCTestCase {

    private let sample = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
                              xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
                              xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">
      <rsm:ExchangedDocumentContext>
        <ram:GuidelineSpecifiedDocumentContextParameter>
          <ram:ID>urn:factur-x.eu:1p0:basicwl</ram:ID>
        </ram:GuidelineSpecifiedDocumentContextParameter>
      </rsm:ExchangedDocumentContext>
      <rsm:ExchangedDocument>
        <ram:ID>F26-001</ram:ID>
        <ram:TypeCode>380</ram:TypeCode>
        <ram:IssueDateTime><udt:DateTimeString format="102">20260312</udt:DateTimeString></ram:IssueDateTime>
      </rsm:ExchangedDocument>
      <rsm:SupplyChainTradeTransaction>
        <ram:ApplicableHeaderTradeAgreement>
          <ram:SellerTradeParty><ram:Name>Blanc-Conseil</ram:Name></ram:SellerTradeParty>
          <ram:BuyerTradeParty><ram:Name>Atelier Bréal</ram:Name></ram:BuyerTradeParty>
        </ram:ApplicableHeaderTradeAgreement>
        <ram:ApplicableHeaderTradeSettlement>
          <ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>
          <ram:ApplicableTradeTax>
            <ram:CalculatedAmount>200.00</ram:CalculatedAmount>
            <ram:BasisAmount>1000.00</ram:BasisAmount>
            <ram:RateApplicablePercent>20.00</ram:RateApplicablePercent>
          </ram:ApplicableTradeTax>
          <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
            <ram:LineTotalAmount>1000.00</ram:LineTotalAmount>
            <ram:TaxBasisTotalAmount>1000.00</ram:TaxBasisTotalAmount>
            <ram:TaxTotalAmount currencyID="EUR">200.00</ram:TaxTotalAmount>
            <ram:GrandTotalAmount>1200.00</ram:GrandTotalAmount>
            <ram:DuePayableAmount>1200.00</ram:DuePayableAmount>
          </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
        </ram:ApplicableHeaderTradeSettlement>
      </rsm:SupplyChainTradeTransaction>
    </rsm:CrossIndustryInvoice>
    """.utf8)

    func testReadsTheFieldsThatMatter() throws {
        let invoice = try XCTUnwrap(FacturXParser.parse(sample))
        XCTAssertEqual(invoice.number, "F26-001")
        XCTAssertEqual(invoice.sellerName, "Blanc-Conseil")
        XCTAssertEqual(invoice.buyerName, "Atelier Bréal")
        XCTAssertEqual(invoice.currencyCode, "EUR")
        XCTAssertEqual(invoice.totalHT, 1000)
        XCTAssertEqual(invoice.totalVAT, 200)
        XCTAssertEqual(invoice.totalTTC, 1200)
        XCTAssertFalse(invoice.isCreditNote)
    }

    /// Le contrôle qui attrape le plus d'erreurs de génération en pratique :
    /// des totaux qui ne s'additionnent pas. Le destinataire automatisé
    /// rejette, et son message est rarement explicite.
    func testTheAdditionCanBeChecked() throws {
        let invoice = try XCTUnwrap(FacturXParser.parse(sample))
        guard let ht = invoice.totalHT, let vat = invoice.totalVAT,
              let ttc = invoice.totalTTC else { return XCTFail("totaux absents") }
        XCTAssertEqual(ht + vat, ttc)
    }

    func testTheVATBreakdownFallsBackOnTheHeaderTotal() throws {
        let invoice = try XCTUnwrap(FacturXParser.parse(sample))
        XCTAssertEqual(invoice.vatBreakdown.count, 1)
        let sum = invoice.vatBreakdown.reduce(Decimal(0)) { $0 + $1.baseHT }
        XCTAssertEqual(sum, invoice.totalHT)
    }

    func testTheDeclaredProfileIsRecognised() throws {
        XCTAssertEqual(try XCTUnwrap(FacturXParser.parse(sample)).profile, .basicWL)
    }
}

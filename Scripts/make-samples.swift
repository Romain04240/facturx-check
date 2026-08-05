#!/usr/bin/env swift
//
// Fabrique les deux factures de démonstration :
//
//     swift Scripts/make-samples.swift
//
//   Samples/facture-demo-facturx.pdf   la même page, avec le XML embarqué
//   Samples/facture-demo-simple.pdf    la même page, sans rien dedans
//
// Les deux sont identiques à l'œil. C'est tout l'intérêt : la différence qui
// compte ne se voit pas, et c'est précisément ce que l'outil sert à montrer.
// Sans un fichier de ce genre, qui découvre l'outil ne voit que le verdict
// négatif d'un PDF ordinaire, et peut en conclure qu'il ne fait rien.
//
// Le PDF est écrit octet par octet plutôt que rendu par CoreGraphics : Core
// Graphics dessine une page, mais ne sait pas y attacher de fichier. Injecter
// l'attachement après coup demanderait de refaire la table des références
// croisées d'un fichier qu'on n'a pas produit ; l'écrire soi-même du début
// coûte moins et se relit.
//
// ATTENTION — ce sont des fichiers de démonstration, pas des documents
// certifiés. Le XML est du CII Factur-X cohérent, mais le PDF n'est pas
// PDF/A-3 (ni profil ICC, ni polices embarquées). Pour un contrôle normatif,
// passer par un validateur officiel : c'est exactement ce que le README dit
// déjà de l'outil lui-même.

import Foundation

// MARK: - La facture, une seule fois

/// Les valeurs vivent ici et servent aux deux formes — la page imprimée et le
/// XML. Les saisir deux fois aurait fini par produire une facture dont le
/// texte et les données se contredisent, ce qui est le défaut que l'outil
/// cherche chez les autres.
struct Invoice {
    let number = "FX-2026-0042"
    let issueDate = "20260803"
    let dueDate = "20260902"
    let issueDatePrinted = "3 août 2026"
    let dueDatePrinted = "2 septembre 2026"

    let sellerName = "Blanc-Conseil"
    let sellerAddress = "12 rue des Lices, 49100 Angers"
    let sellerSIRET = "81234567800019"
    let sellerVAT = "FR32812345678"

    let buyerName = "Atelier Bréal"
    let buyerAddress = "8 quai de la Fosse, 44000 Nantes"

    let currency = "EUR"

    struct Line {
        let label: String
        let quantity: String
        let unitPrice: String
        let total: String
        let rate: String
    }

    let lines = [
        Line(label: "Accompagnement facturation électronique",
             quantity: "2,5 j", unitPrice: "480,00 €", total: "1 200,00 €", rate: "20 %"),
        Line(label: "Livret de prise en main, 40 pages",
             quantity: "12", unitPrice: "20,00 €", total: "240,00 €", rate: "5,5 %"),
    ]

    // Deux taux : la ventilation de TVA a alors quelque chose à montrer, et le
    // contrôle « somme des bases = total HT » quelque chose à vérifier.
    let totalHT = "1440.00"
    let totalVAT = "253.20"
    let totalTTC = "1693.20"
    let baseStandard = "1200.00", vatStandard = "240.00"
    let baseReduced = "240.00", vatReduced = "13.20"

    var totalHTPrinted: String { "1 440,00 €" }
    var totalVATPrinted: String { "253,20 €" }
    var totalTTCPrinted: String { "1 693,20 €" }
}

let invoice = Invoice()

// MARK: - Le XML

func facturXML(_ f: Invoice) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rsm:CrossIndustryInvoice
        xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
        xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
        xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">
      <rsm:ExchangedDocumentContext>
        <ram:GuidelineSpecifiedDocumentContextParameter>
          <ram:ID>urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basicwl</ram:ID>
        </ram:GuidelineSpecifiedDocumentContextParameter>
      </rsm:ExchangedDocumentContext>
      <rsm:ExchangedDocument>
        <ram:ID>\(f.number)</ram:ID>
        <ram:TypeCode>380</ram:TypeCode>
        <ram:IssueDateTime>
          <udt:DateTimeString format="102">\(f.issueDate)</udt:DateTimeString>
        </ram:IssueDateTime>
      </rsm:ExchangedDocument>
      <rsm:SupplyChainTradeTransaction>
        <ram:ApplicableHeaderTradeAgreement>
          <ram:SellerTradeParty>
            <ram:Name>\(f.sellerName)</ram:Name>
            <ram:SpecifiedLegalOrganization>
              <ram:ID schemeID="0002">\(f.sellerSIRET)</ram:ID>
            </ram:SpecifiedLegalOrganization>
            <ram:SpecifiedTaxRegistration>
              <ram:ID schemeID="VA">\(f.sellerVAT)</ram:ID>
            </ram:SpecifiedTaxRegistration>
          </ram:SellerTradeParty>
          <ram:BuyerTradeParty>
            <ram:Name>\(f.buyerName)</ram:Name>
          </ram:BuyerTradeParty>
        </ram:ApplicableHeaderTradeAgreement>
        <ram:ApplicableHeaderTradeDelivery/>
        <ram:ApplicableHeaderTradeSettlement>
          <ram:InvoiceCurrencyCode>\(f.currency)</ram:InvoiceCurrencyCode>
          <ram:ApplicableTradeTax>
            <ram:CalculatedAmount>\(f.vatStandard)</ram:CalculatedAmount>
            <ram:TypeCode>VAT</ram:TypeCode>
            <ram:BasisAmount>\(f.baseStandard)</ram:BasisAmount>
            <ram:CategoryCode>S</ram:CategoryCode>
            <ram:RateApplicablePercent>20.00</ram:RateApplicablePercent>
          </ram:ApplicableTradeTax>
          <ram:ApplicableTradeTax>
            <ram:CalculatedAmount>\(f.vatReduced)</ram:CalculatedAmount>
            <ram:TypeCode>VAT</ram:TypeCode>
            <ram:BasisAmount>\(f.baseReduced)</ram:BasisAmount>
            <ram:CategoryCode>S</ram:CategoryCode>
            <ram:RateApplicablePercent>5.50</ram:RateApplicablePercent>
          </ram:ApplicableTradeTax>
          <ram:SpecifiedTradePaymentTerms>
            <ram:DueDateDateTime>
              <udt:DateTimeString format="102">\(f.dueDate)</udt:DateTimeString>
            </ram:DueDateDateTime>
          </ram:SpecifiedTradePaymentTerms>
          <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
            <ram:LineTotalAmount>\(f.totalHT)</ram:LineTotalAmount>
            <ram:TaxBasisTotalAmount>\(f.totalHT)</ram:TaxBasisTotalAmount>
            <ram:TaxTotalAmount currencyID="\(f.currency)">\(f.totalVAT)</ram:TaxTotalAmount>
            <ram:GrandTotalAmount>\(f.totalTTC)</ram:GrandTotalAmount>
            <ram:DuePayableAmount>\(f.totalTTC)</ram:DuePayableAmount>
          </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
        </ram:ApplicableHeaderTradeSettlement>
      </rsm:SupplyChainTradeTransaction>
    </rsm:CrossIndustryInvoice>
    """
}

// MARK: - La page imprimée

/// Une instruction de dessin, dans l'ordre où elle sera écrite.
struct TextRun {
    let x: Double, y: Double
    let size: Double
    let bold: Bool
    let text: String
    let rightAligned: Bool

    init(_ x: Double, _ y: Double, _ text: String,
         size: Double = 10, bold: Bool = false, rightAligned: Bool = false) {
        self.x = x; self.y = y; self.text = text
        self.size = size; self.bold = bold; self.rightAligned = rightAligned
    }
}

func page(for f: Invoice) -> [TextRun] {
    var runs: [TextRun] = []
    let left = 56.0, right = 539.0
    var y = 780.0

    runs.append(TextRun(left, y, f.sellerName, size: 20, bold: true))
    y -= 18
    runs.append(TextRun(left, y, f.sellerAddress, size: 9))
    y -= 12
    runs.append(TextRun(left, y, "SIRET \(f.sellerSIRET) — TVA \(f.sellerVAT)", size: 9))

    y = 780
    runs.append(TextRun(right, y, "FACTURE", size: 20, bold: true, rightAligned: true))
    y -= 20
    runs.append(TextRun(right, y, "N° \(f.number)", size: 11, rightAligned: true))
    y -= 14
    runs.append(TextRun(right, y, "Émise le \(f.issueDatePrinted)", size: 9, rightAligned: true))
    y -= 12
    runs.append(TextRun(right, y, "Échéance le \(f.dueDatePrinted)", size: 9, rightAligned: true))

    y = 680
    runs.append(TextRun(left, y, "Facturé à", size: 9, bold: true))
    y -= 14
    runs.append(TextRun(left, y, f.buyerName, size: 11))
    y -= 12
    runs.append(TextRun(left, y, f.buyerAddress, size: 9))

    y = 600
    runs.append(TextRun(left, y, "Désignation", size: 9, bold: true))
    runs.append(TextRun(330, y, "Quantité", size: 9, bold: true, rightAligned: true))
    runs.append(TextRun(420, y, "P.U. HT", size: 9, bold: true, rightAligned: true))
    runs.append(TextRun(470, y, "TVA", size: 9, bold: true, rightAligned: true))
    runs.append(TextRun(right, y, "Total HT", size: 9, bold: true, rightAligned: true))

    for line in f.lines {
        y -= 22
        runs.append(TextRun(left, y, line.label))
        runs.append(TextRun(330, y, line.quantity, rightAligned: true))
        runs.append(TextRun(420, y, line.unitPrice, rightAligned: true))
        runs.append(TextRun(470, y, line.rate, rightAligned: true))
        runs.append(TextRun(right, y, line.total, rightAligned: true))
    }

    y -= 46
    runs.append(TextRun(430, y, "Total HT", rightAligned: true))
    runs.append(TextRun(right, y, f.totalHTPrinted, rightAligned: true))
    y -= 16
    runs.append(TextRun(430, y, "TVA", rightAligned: true))
    runs.append(TextRun(right, y, f.totalVATPrinted, rightAligned: true))
    y -= 18
    runs.append(TextRun(430, y, "Total TTC", size: 12, bold: true, rightAligned: true))
    runs.append(TextRun(right, y, f.totalTTCPrinted, size: 12, bold: true, rightAligned: true))

    y -= 48
    runs.append(TextRun(left, y, "Paiement à 30 jours. Pénalités de retard : 3 fois le taux d'intérêt légal.", size: 8))
    y -= 11
    runs.append(TextRun(left, y, "Indemnité forfaitaire pour frais de recouvrement : 40 €.", size: 8))
    y -= 11
    runs.append(TextRun(left, y, "Facture de démonstration — société et client fictifs.", size: 8))

    return runs
}

// MARK: - Écriture du PDF

/// Helvetica est l'une des quatorze polices que tout lecteur PDF possède : ne
/// pas l'embarquer garde le fichier lisible partout et le script court. C'est
/// aussi ce qui interdit de prétendre au PDF/A-3, qui exige l'inverse.
func escaped(_ text: String) -> Data {
    // WinAnsi couvre les accents et le signe €, ce qui suffit à une facture
    // française. Un caractère hors jeu deviendrait un point d'interrogation
    // silencieux : on le remplace par une approximation visible.
    let usable = text.replacingOccurrences(of: "\u{202F}", with: " ")
                     .replacingOccurrences(of: "\u{00A0}", with: " ")
    let bytes = usable.data(using: .windowsCP1252, allowLossyConversion: true) ?? Data()
    var out = Data()
    for byte in bytes {
        if byte == 0x28 || byte == 0x29 || byte == 0x5C { out.append(0x5C) }  // ( ) \
        out.append(byte)
    }
    return out
}

/// La largeur d'une chaîne, pour aligner à droite sans moteur de rendu. Les
/// largeurs d'Helvetica sont tabulées dans le standard ; une approximation
/// suffit ici, un décalage d'un point ne se voit pas sur une facture.
func width(_ text: String, size: Double, bold: Bool) -> Double {
    let narrow = Set("iljtfIr .,;:'|!")
    let wide = Set("mwMW@")
    var units = 0.0
    for character in text {
        if narrow.contains(character) { units += 0.30 }
        else if wide.contains(character) { units += 0.85 }
        else if character.isUppercase { units += 0.68 }
        else { units += 0.54 }
    }
    return units * size * (bold ? 1.06 : 1.0)
}

func contentStream(_ runs: [TextRun]) -> Data {
    var stream = Data()
    for run in runs {
        let x = run.rightAligned ? run.x - width(run.text, size: run.size, bold: run.bold) : run.x
        stream.append(Data("BT /\(run.bold ? "F2" : "F1") \(run.size) Tf 1 0 0 1 \(String(format: "%.2f", x)) \(String(format: "%.2f", run.y)) Tm (".utf8))
        stream.append(escaped(run.text))
        stream.append(Data(") Tj ET\n".utf8))
    }
    return stream
}

/// Un PDF écrit linéairement : chaque objet est ajouté, sa position retenue,
/// et la table des références croisées écrite à la fin à partir de ces
/// positions. C'est la seule partie du format qui ne pardonne pas
/// l'approximation — un décalage d'un octet et le fichier est illisible.
struct PDFWriter {
    private var data = Data()
    private var offsets: [Int] = []

    init() { data.append(Data("%PDF-1.7\n%\u{00E2}\u{00E3}\u{00CF}\u{00D3}\n".utf8)) }

    mutating func add(_ body: Data) {
        offsets.append(data.count)
        let number = offsets.count
        data.append(Data("\(number) 0 obj\n".utf8))
        data.append(body)
        data.append(Data("\nendobj\n".utf8))
    }

    mutating func add(_ body: String) { add(Data(body.utf8)) }

    mutating func addStream(dictionary: String, content: Data) {
        var body = Data("<< \(dictionary) /Length \(content.count) >>\nstream\n".utf8)
        body.append(content)
        body.append(Data("\nendstream".utf8))
        add(body)
    }

    func finished(rootObject: Int) -> Data {
        var out = data
        let start = out.count
        out.append(Data("xref\n0 \(offsets.count + 1)\n0000000000 65535 f \n".utf8))
        for offset in offsets {
            out.append(Data(String(format: "%010d 00000 n \n", offset).utf8))
        }
        out.append(Data("""
        trailer
        << /Size \(offsets.count + 1) /Root \(rootObject) 0 R >>
        startxref
        \(start)
        %%EOF

        """.utf8))
        return out
    }
}

/// Les objets sont numérotés dans l'ordre où ils sont écrits, et les
/// références sont donc en dur. L'ordre ci-dessous est le contrat : le
/// changer sans changer les renvois produit un PDF que les lecteurs ouvrent
/// à moitié, ou pas du tout.
///
///   1 catalogue   2 pages   3 page   4 Helvetica   5 Helvetica-Bold
///   6 contenu de la page
///   7 description du fichier joint   8 métadonnées   9 le XML lui-même
func makePDF(_ f: Invoice, attachingXML xml: String?) -> Data {
    var writer = PDFWriter()

    writer.add(xml == nil
        ? "<< /Type /Catalog /Pages 2 0 R >>"
        : """
          << /Type /Catalog /Pages 2 0 R \
          /Names << /EmbeddedFiles << /Names [(factur-x.xml) 7 0 R] >> >> \
          /AF [7 0 R] /Metadata 8 0 R >>
          """)
    writer.add("<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    writer.add("""
        << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] \
        /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>
        """)
    writer.add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    writer.add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
    writer.addStream(dictionary: "", content: contentStream(page(for: f)))

    if let xml {
        let payload = Data(xml.utf8)
        // AFRelationship /Alternative est ce que Factur-X impose : le XML
        // n'est pas un complément de la page, c'est la même facture sous une
        // autre forme.
        writer.add("""
            << /Type /Filespec /F (factur-x.xml) /UF (factur-x.xml) \
            /AFRelationship /Alternative /Desc (Facture électronique Factur-X) \
            /EF << /F 9 0 R >> >>
            """)
        writer.addStream(dictionary: "/Type /Metadata /Subtype /XML",
                         content: Data(xmpMetadata(f).utf8))
        writer.addStream(dictionary: """
            /Type /EmbeddedFile /Subtype /text#2Fxml \
            /Params << /Size \(payload.count) >>
            """, content: payload)
    }

    return writer.finished(rootObject: 1)
}

/// Les métadonnées que cherche un lecteur pour savoir qu'il tient une facture
/// Factur-X, et à quel profil elle prétend. Volontairement sans déclaration
/// `pdfaid` : le fichier n'est pas PDF/A-3, et l'écrire serait mentir à qui
/// le vérifierait.
func xmpMetadata(_ f: Invoice) -> String {
    """
    <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
    <x:xmpmeta xmlns:x="adobe:ns:meta/">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <dc:title><rdf:Alt><rdf:li xml:lang="x-default">Facture \(f.number)</rdf:li></rdf:Alt></dc:title>
          <dc:creator><rdf:Seq><rdf:li>\(f.sellerName)</rdf:li></rdf:Seq></dc:creator>
        </rdf:Description>
        <rdf:Description rdf:about="" xmlns:fx="urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#">
          <fx:DocumentType>INVOICE</fx:DocumentType>
          <fx:DocumentFileName>factur-x.xml</fx:DocumentFileName>
          <fx:Version>1.0</fx:Version>
          <fx:ConformanceLevel>BASIC WL</fx:ConformanceLevel>
        </rdf:Description>
      </rdf:RDF>
    </x:xmpmeta>
    <?xpacket end="w"?>
    """
}

// MARK: - Écriture

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let samples = root.appendingPathComponent("Samples")
try? FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)

let withXML = makePDF(invoice, attachingXML: facturXML(invoice))
let without = makePDF(invoice, attachingXML: nil)

try withXML.write(to: samples.appendingPathComponent("facture-demo-facturx.pdf"))
try without.write(to: samples.appendingPathComponent("facture-demo-simple.pdf"))

print("Samples/facture-demo-facturx.pdf  \(withXML.count) octets")
print("Samples/facture-demo-simple.pdf   \(without.count) octets")

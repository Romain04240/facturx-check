import SwiftUI
import FacturXKit

/// Ce que montre le volet de droite.
enum PaneTab: String {
    case xml, ocr
}

struct ReportDetailView: View {
    let inspected: Inspected
    @EnvironmentObject private var inspection: Inspection

    /// Le volet reste ouvert d'un fichier à l'autre, et d'une session à la
    /// suivante : quelqu'un qui veut voir la source veut la voir pour tous, pas
    /// la rouvrir à chaque sélection.
    @AppStorage("shows-pane") private var showsPane = false
    @AppStorage("pane-tab") private var paneTab = PaneTab.xml
    @State private var copied = false

    private var report: FacturXReport { inspected.report }

    /// Un fichier sans XML n'a qu'un onglet possible : inutile d'afficher un
    /// volet vide parce que l'onglet retenu ne s'applique pas à ce fichier-là.
    private var effectiveTab: PaneTab {
        report.xmlString == nil ? .ocr : paneTab
    }

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    verdict
                    checks
                    if let invoice = report.invoice {
                        content(invoice)
                        if !invoice.vatBreakdown.isEmpty { breakdown(invoice.vatBreakdown) }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Les deux largeurs minimales doivent tenir ensemble dans la
            // fenêtre la plus étroite que l'on autorise, barre latérale
            // comprise, sans quoi le volet déborde hors de l'écran et emporte
            // son propre en-tête avec lui.
            .frame(minWidth: 360)

            if showsPane {
                pane.frame(minWidth: 280, idealWidth: 380)
            }
        }
        .navigationTitle(report.fileName)
        .navigationSubtitle(report.invoice?.number ?? "")
        .toolbar {
            ToolbarItem {
                Button {
                    copy(report.plainText, into: $copied)
                } label: {
                    Label(copied ? "Copié" : "Copier le rapport",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .help("Copier le rapport en texte, pour l'envoyer à l'émetteur de la facture")
            }
            ToolbarItem {
                Toggle(isOn: $showsPane) {
                    Label("Volet", systemImage: "sidebar.right")
                }
                .help(showsPane ? "Masquer le volet" : "Afficher la source : XML ou texte reconnu")
            }
        }
    }

    // MARK: - Verdict

    private var verdict: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: report.outcome.symbol)
                .font(.system(size: 30))
                .foregroundStyle(report.outcome.tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(report.outcome.title)
                    .font(.title2.weight(.semibold))
                if let detail = report.outcome.detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Sur un PDF sans facture structurée, la question qui vient
                // aussitôt est « alors, qu'est-ce qu'il en reste ? ». On y
                // répond d'ici plutôt que de laisser chercher le volet.
                if report.xml == nil, inspection.ocrResults[report.id] == nil {
                    Button {
                        showsPane = true
                        inspection.runOCR(for: report.id)
                    } label: {
                        Label("Voir ce qu'un OCR y lirait", systemImage: "text.viewfinder")
                    }
                    .padding(.top, 4)
                    .disabled(inspection.ocrRunning.contains(report.id))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(report.outcome.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Contrôles

    @ViewBuilder
    private var checks: some View {
        if !report.checks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Contrôles")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(report.checks) { check in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: check.level.symbol)
                                .foregroundStyle(check.level.tint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(check.message)
                                // On dit ce que ça coûte, pas seulement que
                                // c'est faux : « HT + TVA ≠ TTC » n'aide pas
                                // quelqu'un qui n'a pas écrit le générateur.
                                if check.level != .passed, let consequence = check.consequence {
                                    Text(consequence)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Contenu

    private func content(_ invoice: FacturXParsedInvoice) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Contenu de la facture")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 8) {
                row("Type", invoice.isCreditNote ? "Avoir" : "Facture")
                row("Numéro", invoice.number)
                row("Date d'émission", invoice.issueDate.map { FacturXReport.dayFormatter.string(from: $0) })
                row("Échéance", invoice.dueDate.map { FacturXReport.dayFormatter.string(from: $0) })
                row("Émetteur", invoice.sellerName)
                row("SIRET émetteur", invoice.sellerLegalID)
                row("N° TVA émetteur", invoice.sellerVATNumber)
                row("Destinataire", invoice.buyerName)
                row("Total HT", report.money(invoice.totalHT))
                row("Total TVA", report.money(invoice.totalVAT))
                row("Total TTC", report.money(invoice.totalTTC), emphasised: true)
                row("Reste à payer", report.money(invoice.duePayable))
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?, emphasised: Bool = false) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(label)
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.leading)
                Text(value)
                    .fontWeight(emphasised ? .semibold : .regular)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Ventilation de TVA

    private func breakdown(_ rows: [VATBreakdownRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Ventilation de TVA")
            Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Taux").gridColumnAlignment(.leading)
                    Text("Base HT")
                    Text("TVA")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(rows) { row in
                    GridRow {
                        Text(Self.percent(row.rate)).gridColumnAlignment(.leading)
                        Text(report.money(row.baseHT) ?? "—")
                        Text(report.money(row.amount) ?? "—")
                    }
                    .monospacedDigit()
                }
            }
        }
    }

    private static func percent(_ rate: Decimal) -> String {
        AmountFormat.rate(rate)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
    }

    // MARK: - Volet

    private var pane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if report.xmlString != nil {
                    Picker("", selection: $paneTab) {
                        Text("XML").tag(PaneTab.xml)
                        Text("Texte lu").tag(PaneTab.ocr)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 200)
                } else {
                    Text("Texte reconnu")
                        .font(.headline)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if effectiveTab == .xml, let xml = report.xmlString {
                XMLPane(xml: xml)
            } else {
                OCRPane(id: report.id, invoice: report.invoice)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Le XML embarqué.
///
/// C'est ce qui fait la valeur légale du document, et c'est justement ce
/// qu'aucun lecteur de PDF ne montre. Le mettre en volet plutôt qu'en repli au
/// bas de la page permet de le lire *en même temps* que le contrôle qui
/// échoue, ce qui est le seul moment où on veut vraiment le voir.
private struct XMLPane: View {
    let xml: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(size).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { copy(xml, into: $copied) } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copier le XML")
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Défilement vertical seulement, et texte qui revient à la ligne :
            // un défilement horizontal donnerait au volet la largeur de la plus
            // longue ligne du XML — c'est-à-dire, en pratique, la déclaration
            // des espaces de noms, qui pousserait tout l'en-tête hors de vue.
            ScrollView(.vertical) {
                Text(indented)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Le XML embarqué arrive souvent sur deux ou trois lignes interminables :
    /// illisible tel quel. On le ré-indente, en gardant l'original si jamais il
    /// est trop abîmé pour être relu — c'est précisément le cas où on veut le
    /// voir.
    private var indented: String {
        guard let document = try? XMLDocument(data: Data(xml.utf8), options: []),
              let pretty = String(data: document.xmlData(options: .nodePrettyPrint), encoding: .utf8)
        else { return xml }
        return pretty
    }

    private var size: String {
        ByteCountFormatter.string(fromByteCount: Int64(xml.utf8.count), countStyle: .file)
    }
}

/// Ce qu'un OCR lit dans le PDF.
private struct OCRPane: View {
    let id: UUID
    /// La facture lue dans le XML, quand il y en a une. Le même volet répond
    /// à deux questions différentes selon le fichier, et les confondre serait
    /// faux : sur un PDF sans XML, l'OCR est ce qui reste au destinataire ;
    /// sur une facture valide, il sert à rapprocher la page des valeurs
    /// exactes.
    let invoice: FacturXParsedInvoice?
    @EnvironmentObject private var inspection: Inspection
    @State private var copied = false

    private var hasStructuredInvoice: Bool { invoice != nil }

    var body: some View {
        if inspection.ocrRunning.contains(id) {
            VStack(spacing: 10) {
                ProgressView()
                Text("Lecture en cours…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let failure = inspection.ocrFailures[id] {
            message(failure, symbol: "exclamationmark.triangle", tint: .orange)
        } else if let result = inspection.ocrResults[id] {
            recognised(result)
        } else {
            invitation
        }
    }

    private var invitation: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tint)
            Text(hasStructuredInvoice
                 ? "Cette facture porte ses valeurs en clair dans le XML. Voici, pour comparaison, ce qu'un OCR croit lire dans la page."
                 : "Sans facture structurée, votre destinataire n'a que l'image du PDF. Voici ce qu'il en tirerait.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Lire le texte") { inspection.runOCR(for: id) }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func recognised(_ result: OCRResult) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(summary(result)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { copy(result.text, into: $copied) } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copier le texte reconnu")
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            ScrollView(.vertical) {
                if let invoice {
                    comparison(result, invoice)
                }
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(result.lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            // Ce que l'OCR n'est pas sûr d'avoir lu, sur une
                            // facture, ce sont presque toujours les chiffres.
                            if line.confidence < 0.8 {
                                Text(percent(line.confidence))
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Le rapprochement de la page et du XML.
    ///
    /// C'est la seule divergence que personne ne voit : le client lit la page,
    /// le logiciel du destinataire lit le XML. Elle se lit donc *avant* le
    /// texte reconnu, qui n'est là que pour juger sur pièces.
    private func comparison(_ result: OCRResult, _ invoice: FacturXParsedInvoice) -> some View {
        let checks = FacturXReport.comparePrinted(result.text, with: invoice)
        let divergences = checks.filter { $0.level != .passed }

        return VStack(alignment: .leading, spacing: 10) {
            Text("La page et le XML")
                .font(.headline)

            Text(divergences.isEmpty
                 ? "Ce qui est imprimé sur la page correspond à ce que déclare le XML."
                 : "Ce que l'OCR lit sur la page ne recouvre pas tout ce que déclare le XML. L'OCR se trompe souvent — comparez vous-même ci-dessous avant d'en conclure quoi que ce soit.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: check.level.symbol)
                        .foregroundStyle(check.level.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.message)
                            .fixedSize(horizontal: false, vertical: true)
                        if check.level != .passed, let consequence = check.consequence {
                            Text(consequence)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .font(.callout)
            }

            Divider().padding(.top, 4)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(_ result: OCRResult) -> String {
        var parts = [count(result.lines.count, "ligne", "lignes")]
        // On ne dit « sur n » que lorsqu'on s'est arrêté avant la fin : sinon
        // c'est une précision qui laisse croire qu'il manque quelque chose.
        parts.append(result.pagesRead == result.pageCount
                     ? count(result.pagesRead, "page", "pages")
                     : "\(result.pagesRead) pages sur \(result.pageCount)")
        if result.uncertainCount > 0 {
            parts.append(count(result.uncertainCount, "incertaine", "incertaines"))
        }
        return parts.joined(separator: " · ")
    }

    private func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n <= 1 ? singular : plural)"
    }

    private func percent(_ confidence: Float) -> String {
        "\(Int((confidence * 100).rounded())) %"
    }

    private func message(_ text: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.title).foregroundStyle(tint)
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Copie, avec un retour visuel qui s'efface tout seul : une coche qui reste
/// ferait croire que le bouton a changé d'état.
@MainActor
private func copy(_ text: String, into flag: Binding<Bool>) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    flag.wrappedValue = true
    Task {
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        flag.wrappedValue = false
    }
}

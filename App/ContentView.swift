import SwiftUI
import UniformTypeIdentifiers
import FacturXKit

struct ContentView: View {
    @EnvironmentObject private var inspection: Inspection
    @State private var isTargeted = false
    @State private var showsImporter = false

    var body: some View {
        Group {
            if inspection.files.isEmpty {
                welcome
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    if let file = inspection.selected {
                        ReportDetailView(inspected: file)
                    } else {
                        ContentUnavailableMessage("Choisissez un fichier à gauche.")
                    }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            inspection.add(urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [9, 7]))
                    .background(Color.accentColor.opacity(0.07))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .fileImporter(isPresented: $showsImporter,
                      allowedContentTypes: [.pdf, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { inspection.add(urls) }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showsImporter = true
                } label: {
                    Label("Ouvrir…", systemImage: "plus")
                }
                .help("Choisir des PDF ou un dossier entier")
                .keyboardShortcut("o")
            }
            if !inspection.files.isEmpty {
                ToolbarItem {
                    Button { inspection.removeAll() } label: {
                        Label("Vider", systemImage: "trash")
                    }
                    .help("Retirer tous les fichiers de la liste")
                }
            }
        }
        .frame(minWidth: 900, minHeight: 480)
    }

    // MARK: - Accueil

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.tint)
                .padding(.bottom, 20)

            Text("Vérifiez vos factures Factur-X")
                .font(.largeTitle.weight(.semibold))

            Text("Déposez un PDF, plusieurs, ou un dossier entier.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            Button("Choisir des fichiers…") { showsImporter = true }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, 26)

            Spacer()

            // La raison d'être de l'outil : les validateurs existants sont des
            // services en ligne où l'on téléverse un document commercial
            // nominatif chez un tiers.
            Label("Rien ne quitte votre Mac : tout est analysé localement, sans réseau.",
                  systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Liste

    private var sidebar: some View {
        List(selection: $inspection.selection) {
            ForEach(inspection.files) { file in
                let report = file.report
                HStack(spacing: 9) {
                    Image(systemName: report.outcome.symbol)
                        .foregroundStyle(report.outcome.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(report.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(report.invoice?.number ?? report.outcome.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
                .tag(report.id)
                .contextMenu {
                    Button("Retirer de la liste") { inspection.remove(report.id) }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                if inspection.isWorking {
                    ProgressView().controlSize(.small)
                }
                Text(tally)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var tally: String {
        let total = inspection.files.count
        let problems = inspection.problemCount
        guard problems > 0 else {
            return total == 1 ? "1 fichier, conforme" : "\(total) fichiers, tous conformes"
        }
        let files = total == 1 ? "1 fichier" : "\(total) fichiers"
        let plural = problems == 1 ? "1 problème" : "\(problems) problèmes"
        return "\(files) — \(plural)"
    }
}

/// `ContentUnavailableView` n'existe qu'à partir de macOS 14 ; l'outil vise
/// macOS 13 pour rester installable sur des Mac plus anciens, qui sont
/// précisément ceux des indépendants concernés par l'échéance 2026.
private struct ContentUnavailableMessage: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

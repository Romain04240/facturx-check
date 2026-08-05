import Foundation
import FacturXKit

/// Un fichier examiné : son rapport, et ses octets.
///
/// On garde le PDF en mémoire plutôt que son chemin, parce que sous bac à
/// sable l'autorisation de lire un fichier déposé ne survit pas au dépôt. Sans
/// ça, l'OCR — demandé plus tard, à la main — échouerait sur un refus d'accès.
struct Inspected: Identifiable {
    let report: FacturXReport
    let pdf: Data
    var id: FacturXReport.ID { report.id }
}

/// Ce que la fenêtre a examiné jusqu'ici.
@MainActor
final class Inspection: ObservableObject {
    @Published private(set) var files: [Inspected] = []
    @Published private(set) var isWorking = false
    @Published var selection: FacturXReport.ID?

    @Published private(set) var ocrResults: [FacturXReport.ID: OCRResult] = [:]
    @Published private(set) var ocrFailures: [FacturXReport.ID: String] = [:]
    @Published private(set) var ocrRunning: Set<FacturXReport.ID> = []

    var selected: Inspected? { files.first { $0.id == selection } }

    var soundCount: Int { files.filter { $0.report.outcome.isSound }.count }
    var problemCount: Int { files.count - soundCount }

    func add(_ urls: [URL]) {
        let paths = urls.flatMap(Self.pdfsUnder)
        guard !paths.isEmpty else { return }
        isWorking = true
        Task {
            let fresh = await Self.analyse(paths)
            files.insert(contentsOf: fresh, at: 0)
            // On sélectionne le premier problème du lot s'il y en a un : c'est
            // celui qu'on est venu chercher.
            selection = (fresh.first { !$0.report.outcome.isSound } ?? fresh.first)?.id
            isWorking = false

            if UserDefaults.standard.bool(forKey: "auto-ocr") {
                for file in fresh where file.report.xml == nil {
                    runOCR(for: file.id)
                }
            }
        }
    }

    func removeAll() {
        files.removeAll()
        ocrResults.removeAll()
        ocrFailures.removeAll()
        selection = nil
    }

    func remove(_ id: FacturXReport.ID) {
        files.removeAll { $0.id == id }
        ocrResults[id] = nil
        ocrFailures[id] = nil
        if selection == id { selection = files.first?.id }
    }

    // MARK: - OCR

    func runOCR(for id: FacturXReport.ID) {
        guard let file = files.first(where: { $0.id == id }),
              ocrResults[id] == nil, !ocrRunning.contains(id) else { return }

        ocrRunning.insert(id)
        ocrFailures[id] = nil
        Task {
            do {
                ocrResults[id] = try await OCRReader.read(pdf: file.pdf)
            } catch {
                ocrFailures[id] = error.localizedDescription
            }
            ocrRunning.remove(id)
        }
    }

    // MARK: - Lecture des fichiers

    /// Déposer un dossier est aussi naturel que déposer un fichier — surtout
    /// pour la question « est-ce que mes factures de l'année passeront ? ».
    private static func pdfsUnder(_ url: URL) -> [URL] {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard isDirectory else {
            return url.pathExtension.lowercased() == "pdf" ? [url] : []
        }
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        let found = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension.lowercased() == "pdf" }
        return found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func analyse(_ urls: [URL]) async -> [Inspected] {
        await Task.detached(priority: .userInitiated) {
            urls.map { url in
                // Sous bac à sable, un fichier ouvert depuis le sélecteur peut
                // demander un accès explicite ; un fichier déposé, non. On
                // demande dans les deux cas, c'est sans effet quand c'est inutile.
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }

                // Un fichier illisible et un fichier qui n'est pas un PDF sont
                // deux problèmes différents ; les confondre enverrait chercher
                // la panne au mauvais endroit.
                guard let data = try? Data(contentsOf: url) else {
                    return Inspected(report: FacturXReport.analyse(fileURL: url), pdf: Data())
                }
                return Inspected(report: FacturXReport.analyse(pdf: data,
                                                               fileName: url.lastPathComponent),
                                 pdf: data)
            }
        }.value
    }
}

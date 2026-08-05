import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("auto-ocr") private var autoOCR = false

    /// L'adresse à laquelle on peut écrire — celle de l'entreprise, pas
    /// l'adresse Apple qui sert à signer l'application. Un seul endroit à
    /// changer.
    private static let contact = "daniel@blanc-conseil.fr"

    var body: some View {
        Form {
            Section {
                Picker(selection: $appearance) {
                    ForEach(Appearance.allCases) { choice in
                        Label(choice.label, systemImage: choice.symbol).tag(choice)
                    }
                } label: {
                    Text("Thème")
                }
                .pickerStyle(.inline)
                .horizontalRadioGroupLayout()
            } header: {
                Text("Apparence")
            } footer: {
                Text("« Système » suit le réglage d'apparence de votre Mac.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Lire le texte automatiquement quand aucune facture structurée n'est trouvée",
                       isOn: $autoOCR)
            } header: {
                Text("Reconnaissance de texte")
            } footer: {
                // La lecture prend quelques secondes par page : l'imposer sur
                // un dossier entier ferait attendre pour des fichiers qu'on ne
                // regardera peut-être jamais.
                Text("La reconnaissance dure quelques secondes par page. Sinon, elle reste disponible à la demande dans le volet de droite.")
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cet outil est gratuit et ne fait qu'une chose : vérifier. Si vous devez aussi **émettre** des factures Factur-X, tenir vos devis, vos clients et votre comptabilité, c'est le métier d'Invoicio.")
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Un contrôle vous manque, un profil n'est pas reconnu, une facture est refusée sans que vous compreniez pourquoi ? Écrivez-moi : c'est ce qui décide de la suite.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: mailto) {
                        Label("Écrire à \(Self.contact)", systemImage: "envelope")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Aller plus loin")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(appearance.colorScheme)
    }

    private var mailto: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.contact
        components.queryItems = [URLQueryItem(name: "subject", value: "Factur-X Check")]
        return components.url ?? URL(string: "mailto:\(Self.contact)")!
    }
}

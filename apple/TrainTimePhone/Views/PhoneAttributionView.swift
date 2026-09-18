import SwiftUI

// Credits for the data and software TrainTime builds on, plus the legal pages, reached from the
// bottom of Settings. Three sources require attribution (Open Transport Data Switzerland by a literal
// clickable link, the FOT station dataset, the Garmin SDK); the rest is credited as good practice. On
// iOS almost nothing third-party ships beyond the Garmin SDK. The app is otherwise built on Apple's
// own frameworks.
struct PhoneAttributionView: View {
    // The app language, so the terms and dataset pages open in it. The terms page exists in the
    // four app languages, the privacy page in English only.
    private var language: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return ["de", "fr", "it"].contains(code) ? code : "en"
    }

    private var termsURL: String {
        language == "en" ? "https://traintime.ch/terms/" : "https://traintime.ch/terms/\(language)/"
    }

    var body: some View {
        List {
            Section("Departure data") {
                Text(String(localized: "Live departures from Open Transport Data Switzerland, operated by Swiss Federal Railways (SBB), via the OJP API."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                linkRow("opentransportdata.swiss", String(localized: "Open Data Platform Mobility Switzerland"),
                        "https://opentransportdata.swiss")
                linkRow(String(localized: "Terms of use"), "opentransportdata.swiss/terms-of-use",
                        "https://opentransportdata.swiss/en/terms-of-use/")
            }

            Section("Station data") {
                Text(String(localized: "Station locations from the Federal Office of Transport (FOT). Open use, source named."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                linkRow(String(localized: "Public transport stops"), "opendata.swiss",
                        "https://opendata.swiss/\(language)/dataset/haltestellen-des-offentlichen-verkehrs")
            }

            Section("Map") {
                Text("Swiss border outline from Natural Earth, 1:10m resolution, public domain.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                linkRow("Natural Earth", "naturalearthdata.com", "https://www.naturalearthdata.com")
            }

            Section {
                linkRow("Garmin Connect IQ Mobile SDK", String(localized: "© Garmin. Used under its SDK licence."),
                        "https://developer.garmin.com/connect-iq/")
            } header: {
                Text("Open source & third party")
            } footer: {
                Text("Otherwise built with Apple's SwiftUI, WidgetKit and WatchConnectivity.")
            }

            Section("Legal") {
                linkRow(String(localized: "Privacy policy"), "traintime.ch/privacy", "https://traintime.ch/privacy")
                linkRow(String(localized: "Terms of use"), "traintime.ch/terms", termsURL)
            }
        }
        .navigationTitle("Attribution")
        .navigationBarTitleDisplayMode(.inline)
    }

    // A credit that opens a link: title over a muted detail line, with a trailing external-link glyph.
    private func linkRow(_ title: String, _ detail: String, _ urlString: String) -> some View {
        Link(destination: URL(string: urlString)!) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(.tint)
            }
        }
    }
}

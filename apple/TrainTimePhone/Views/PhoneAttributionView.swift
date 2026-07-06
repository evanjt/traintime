import SwiftUI

// Credits for the data and software TrainTime builds on, reached from the bottom of Settings. Two
// sources require attribution (Open Transport Data Switzerland, the Garmin SDK); the rest is credited
// as good practice. On iOS almost nothing third-party ships beyond the Garmin SDK. The app is
// otherwise built on Apple's own frameworks.
struct PhoneAttributionView: View {
    var body: some View {
        List {
            Section("Departure data") {
                Text("Live departures from Open Transport Data Switzerland, operated by Swiss "
                    + "Federal Railways (SBB), via the OJP API.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                linkRow("Terms of use", "opentransportdata.swiss",
                        "https://opentransportdata.swiss/en/terms-of-use/")
            }

            Section("Map") {
                Text("Swiss border outline from Natural Earth, 1:10m resolution, public domain.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                linkRow("Natural Earth", "naturalearthdata.com", "https://www.naturalearthdata.com")
            }

            Section {
                linkRow("Garmin Connect IQ Mobile SDK", "© Garmin. Used under its SDK licence.",
                        "https://developer.garmin.com/connect-iq/")
            } header: {
                Text("Open source & third party")
            } footer: {
                Text("Otherwise built with Apple's SwiftUI, WidgetKit and WatchConnectivity.")
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

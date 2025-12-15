import SwiftUI

struct NewsSettingsSection: View {
    @AppStorage("newsApiKey") private var newsApiKey: String = ""

    var body: some View {
        Section(header: Text("News"), footer: footer) {
            SecureField("News API Key (NewsAPI.org)", text: $newsApiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Enter your News API key to enable live headlines.")
            Link("Get a free key at NewsAPI.org", destination: URL(string: "https://newsapi.org/" )!)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationStack {
        Form { NewsSettingsSection() }
            .navigationTitle("Settings")
    }
}


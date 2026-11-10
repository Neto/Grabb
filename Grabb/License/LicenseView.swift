import SwiftUI

// Shared by Spin and Grabb. Keep both copies identical.
// The trial and license panel: status, Buy, and a field for the license key.
struct LicenseView: View {
    @Bindable var license: SpoonLicense
    var price: String
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.bold())
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !license.isLicensed {
                Button {
                    license.buy()
                } label: {
                    Text("Buy \(license.displayName) for \(price)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Already paid? Paste your license key.")
                        .font(.callout)
                    HStack {
                        TextField("SPOON1.…", text: $key)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(activate)
                        Button("Activate", action: activate)
                            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let error = license.activationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            HStack {
                Text("One payment. Every future update included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Lost your key?", action: license.contactSupport)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var title: String {
        switch license.state {
        case .trial: "\(license.displayName) free trial"
        case .expired: "Your free trial has ended"
        case .licensed: "Thank you!"
        }
    }

    private var message: String {
        switch license.state {
        case .trial(let days):
            "You have \(days == 1 ? "1 day" : "\(days) days") left to try every feature. Buy once and keep \(license.displayName) for good."
        case .expired:
            "Buy \(license.displayName) once to keep using it. No subscription, no in-app purchases."
        case .licensed(let email):
            email.isEmpty ? "\(license.displayName) is unlocked on this Mac." : "\(license.displayName) is licensed to \(email)."
        }
    }

    private func activate() {
        license.activate(key: key)
        if license.isLicensed { key = "" }
    }
}

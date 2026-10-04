import SwiftUI

/// Tab "Account": Bose account state, sign-in / sign-out, token validity.
struct SettingsAccountTab: View {
    @ObservedObject var model: AppModel
    let actions: PanelActions

    var body: some View {
        SettingsPage {
            AccountSection(model: model, actions: actions)
        }
    }
}

/// Bose account state with sign-in / sign-out. Signing in opens Bose's own page (see `BoseLogin`).
private struct AccountSection: View {
    @ObservedObject var model: AppModel
    let actions: PanelActions

    var body: some View {
        Section {
            LabeledContent("Bose account") {
                model.signedIn ? Text("Signed in") : Text("Not signed in")
            }
            HStack {
                if model.signedIn {
                    Button("Sign out", role: .destructive, action: actions.signOut)
                } else {
                    Button("Sign in …", action: actions.openSignIn)
                        .disabled(model.isSigningIn)
                }
                if model.isSigningIn { ProgressView().controlSize(.small) }
            }
            if let error = model.signInError {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if model.signedIn, let exp = model.tokenExpiry {
                LabeledContent("Token valid until") {
                    Text(exp, format: .dateTime.day().month().hour().minute())
                }
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Sign in on Bose's own page with the account you use in the Bose app. SoundbarKeys does not read the form; it only keeps the sign-in token in your Keychain.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

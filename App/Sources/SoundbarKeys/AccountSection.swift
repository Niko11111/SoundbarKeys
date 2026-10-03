import SwiftUI

/// Settings section showing the Bose account state with sign-in / sign-out.
/// Signing in opens Bose's own sign-in page (see `BoseLogin`).
struct AccountSection: View {
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
        } header: {
            Text("Account")
        } footer: {
            Text("Sign in on Bose's own page with the account you use in the Bose app. SoundbarKeys does not read the form; it only keeps the sign-in token in your Keychain.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

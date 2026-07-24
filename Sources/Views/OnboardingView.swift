import SwiftUI

/// First-run screen: pick a display name other nearby users will see you as.
/// No phone number, no account, no server - your identity is just a UUID
/// generated on-device plus whatever name you choose here.
struct OnboardingView: View {
    @EnvironmentObject var mesh: MeshManager
    @Binding var onboarded: Bool
    @State private var name: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("MeshChat")
                .font(.largeTitle.bold())
            Text("Message people nearby over Bluetooth - no internet, no server, no account. Messages can even hop through other users' phones to reach further.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            TextField("Your display name", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 32)
                .autocorrectionDisabled()

            Button {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                mesh.myDisplayName = trimmed.isEmpty ? mesh.myDisplayName : trimmed
                onboarded = true
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .onAppear { name = mesh.myDisplayName }
    }
}

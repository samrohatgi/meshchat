import SwiftUI

@main
struct MeshChatApp: App {
    @StateObject private var mesh: MeshManager
    @StateObject private var chatStore: ChatStore
    @AppStorage("meshchat.onboarded") private var onboarded = false

    init() {
        let m = MeshManager()
        _mesh = StateObject(wrappedValue: m)
        _chatStore = StateObject(wrappedValue: ChatStore(mesh: m))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded {
                    ConversationListView()
                        .environmentObject(mesh)
                        .environmentObject(chatStore)
                } else {
                    OnboardingView(onboarded: $onboarded)
                        .environmentObject(mesh)
                }
            }
            .onAppear { mesh.start() }
        }
    }
}

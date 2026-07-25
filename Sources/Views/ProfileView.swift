import SwiftUI
import PhotosUI

/// Lets you set your own display name and profile picture. Both are shared
/// with peers over the mesh as soon as they change - there's no server, so
/// "uploading" a photo just means it rides along in the identity handshake
/// the next time you're near someone.
struct ProfileView: View {
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewPhotoData: Data?

    private var displayedPhoto: Data? { previewPhotoData ?? mesh.myPhotoData }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                ZStack(alignment: .bottomTrailing) {
                                    AvatarView(photoData: displayedPhoto, initials: initials, tint: .green, size: 88)
                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 26))
                                        .foregroundStyle(.white, .green)
                                }
                            }
                            if displayedPhoto != nil {
                                Button("Remove photo", role: .destructive) {
                                    previewPhotoData = nil
                                    mesh.updateMyPhoto(nil)
                                }
                                .font(.footnote)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Your name") {
                    TextField("Display name", text: $name)
                }
            }
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { mesh.myDisplayName = trimmed }
                        dismiss()
                    }
                }
            }
            .onAppear { name = mesh.myDisplayName }
            .onChange(of: pickerItem) { newItem in
                Task {
                    guard let newItem, let raw = try? await newItem.loadTransferable(type: Data.self) else { return }
                    let thumbnail = ImageResizer.thumbnail(from: raw) ?? raw
                    previewPhotoData = thumbnail
                    mesh.updateMyPhoto(thumbnail)
                }
            }
        }
    }

    private var initials: String {
        let parts = mesh.myDisplayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

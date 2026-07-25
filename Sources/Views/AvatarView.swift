import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Shared avatar circle used everywhere a person shows up in the UI -
/// renders their profile photo if we have one, otherwise falls back to a
/// colored initials circle so avatars never look broken while a photo is
/// still propagating over the mesh.
struct AvatarView: View {
    var photoData: Data?
    var initials: String
    var tint: Color
    var size: CGFloat = 40

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
    }

    private var fallback: some View {
        Circle()
            .fill(tint.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }
}

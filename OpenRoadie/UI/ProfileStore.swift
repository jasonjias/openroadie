import SwiftUI
import UIKit

/// The user's profile photo, stored locally (Apple exposes no API for the
/// Apple ID / iCloud picture to third-party apps — first-party only).
@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    private(set) var image: UIImage?

    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("profile.jpg")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL) {
            image = UIImage(data: data)
        }
    }

    func set(imageData: Data) {
        guard let picked = UIImage(data: imageData) else { return }
        // Store a reasonably-sized square crop; avatars are small.
        let squared = Self.squareThumbnail(of: picked, side: 512)
        if let jpeg = squared.jpegData(compressionQuality: 0.85) {
            try? jpeg.write(to: Self.fileURL)
            image = squared
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        image = nil
    }

    private static func squareThumbnail(of image: UIImage, side: CGFloat) -> UIImage {
        let shortest = min(image.size.width, image.size.height)
        let scale = side / shortest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            image.draw(in: CGRect(
                x: (side - size.width) / 2,
                y: (side - size.height) / 2,
                width: size.width,
                height: size.height
            ))
        }
    }
}

/// The avatar shown on toolbars: the chosen photo (or a placeholder) in a
/// bordered circle, Fitness-style.
struct ProfileAvatar: View {
    var size: CGFloat = 34

    private let store = ProfileStore.shared

    var body: some View {
        Group {
            if let image = store.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color(.systemGray5))
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color(.systemGray4), lineWidth: max(1.5, size / 28))
        )
    }
}

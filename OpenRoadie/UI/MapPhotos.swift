import MapKit
import Photos
import SwiftUI
import UIKit

/// A photo from the user's library, placed where it was taken — the
/// Photos-app map experience, on the drive maps. Read-only: photos are
/// referenced in place, never copied, never uploaded.
struct MapPhoto: Identifiable, @unchecked Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let thumbnail: UIImage

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum MapPhotoLibrary {
    /// PhotoKit has no read-only access level — .readWrite is the read
    /// permission. This feature only ever reads; "limited" counts as yes.
    static func authorize() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Geotagged photos taken in any of the given time windows. Windows
    /// beyond ~50 make an unwieldy predicate; callers pass at most a map's
    /// worth of trips.
    static func photos(in windows: [(start: Date, end: Date)], limit: Int = 150) async -> [MapPhoto] {
        guard !windows.isEmpty else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let subpredicates = windows.map {
                NSPredicate(format: "creationDate >= %@ AND creationDate <= %@", $0.start as NSDate, $0.end as NSDate)
            }
            let options = PHFetchOptions()
            options.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assets = PHAsset.fetchAssets(with: .image, options: options)

            let imageOptions = PHImageRequestOptions()
            imageOptions.isSynchronous = true
            imageOptions.deliveryMode = .fastFormat
            imageOptions.resizeMode = .fast
            imageOptions.isNetworkAccessAllowed = false // local thumbnails only

            var photos: [MapPhoto] = []
            assets.enumerateObjects { asset, _, stop in
                guard photos.count < limit else {
                    stop.pointee = true
                    return
                }
                guard let location = asset.location else { return }
                var thumbnail: UIImage?
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: CGSize(width: 120, height: 120),
                    contentMode: .aspectFill,
                    options: imageOptions
                ) { image, _ in
                    thumbnail = image
                }
                guard let thumbnail else { return }
                photos.append(MapPhoto(
                    id: asset.localIdentifier,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    thumbnail: thumbnail
                ))
            }
            return photos
        }.value
    }

    /// A bigger rendition of one photo, for the tap-to-view sheet.
    static func fullImage(id: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            var image: UIImage?
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1200, height: 1200),
                contentMode: .aspectFit,
                options: options
            ) { result, _ in
                image = result
            }
            return image
        }.value
    }
}

/// The photo toggle for a map toolbar, plus the loading/denied states.
/// Owns the fetch; the map just renders `photos`.
@MainActor
@Observable
final class MapPhotosModel {
    private(set) var photos: [MapPhoto] = []
    private(set) var isLoading = false
    private(set) var accessDenied = false
    var isShowing = false

    /// Toggles photos on/off, fetching (and asking permission) on first use.
    func toggle(windows: [(start: Date, end: Date)]) {
        if isShowing {
            isShowing = false
            return
        }
        isShowing = true
        guard photos.isEmpty, !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            guard await MapPhotoLibrary.authorize() else {
                accessDenied = true
                isShowing = false
                return
            }
            photos = await MapPhotoLibrary.photos(in: windows)
        }
    }
}

/// Thumbnail annotations, Photos-map style: rounded square, white border.
/// Tap opens the photo full-size.
struct PhotoAnnotations: MapContent {
    let photos: [MapPhoto]
    @Binding var viewing: MapPhoto?

    var body: some MapContent {
        ForEach(photos) { photo in
            Annotation("", coordinate: photo.coordinate) {
                Button {
                    viewing = photo
                } label: {
                    Image(uiImage: photo.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white, lineWidth: 2))
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Full-size viewer for one tapped photo.
struct MapPhotoViewer: View {
    let photo: MapPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var full: UIImage?

    var body: some View {
        NavigationStack {
            Group {
                if let full {
                    Image(uiImage: full).resizable().scaledToFit()
                } else {
                    Image(uiImage: photo.thumbnail).resizable().scaledToFit()
                        .overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                full = await MapPhotoLibrary.fullImage(id: photo.id)
            }
        }
    }
}

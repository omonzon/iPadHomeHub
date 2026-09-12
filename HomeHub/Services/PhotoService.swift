import Foundation
import Photos
import UIKit

/// Pulls a slideshow out of the local photo library. Reads only — the hub
/// never writes back to the library.
@MainActor
final class PhotoService: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var status: PHAuthorizationStatus = .notDetermined

    private var assets: [PHAsset] = []
    private var cursor = 0
    private let manager = PHImageManager.default()

    func prepare(albumName: String) async {
        status = await requestAuthorization()
        guard status == .authorized || status == .limited else { return }
        assets = fetchAssets(albumName: albumName).shuffled()
        cursor = 0
        await advance()
    }

    /// PHAccessLevel only offers .addOnly and .readWrite — there is no read-only
    /// level — so ask for .readWrite even though the hub never writes back.
    private func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func fetchAssets(albumName: String) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 400

        let collection: PHAssetCollection?
        if albumName.isEmpty {
            collection = nil
        } else {
            let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            var match: PHAssetCollection?
            albums.enumerateObjects { album, _, stop in
                if album.localizedTitle?.caseInsensitiveCompare(albumName) == .orderedSame {
                    match = album
                    stop.pointee = true
                }
            }
            collection = match
        }

        let result: PHFetchResult<PHAsset>
        if let collection = collection {
            result = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            result = PHAsset.fetchAssets(with: .image, options: options)
        }

        var found: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in found.append(asset) }
        return found
    }

    func advance() async {
        guard !assets.isEmpty else { return }
        let asset = assets[cursor % assets.count]
        cursor += 1
        image = await loadImage(asset)
    }

    private func loadImage(_ asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact

        let target = CGSize(width: 2048, height: 2048)
        return await withCheckedContinuation { continuation in
            var resumed = false
            manager.requestImage(for: asset,
                                 targetSize: target,
                                 contentMode: .aspectFit,
                                 options: options) { image, _ in
                // highQualityFormat delivers once, but guard anyway: resuming a
                // continuation twice traps, and never resuming leaks the task.
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    var hasPhotos: Bool { !assets.isEmpty }
}

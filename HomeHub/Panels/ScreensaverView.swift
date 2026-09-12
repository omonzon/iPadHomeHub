import SwiftUI
import Photos
import UIKit

/// Photo slideshow with a large clock, shown after the hub has been idle.
/// Any touch dismisses it.
struct ScreensaverView: View {
    @ObservedObject var photos: PhotoService
    let use24Hour: Bool
    let intervalSeconds: Int
    let onDismiss: () -> Void

    @State private var timer: Timer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = photos.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .id(image)
                    .transition(.opacity)
            }

            LinearGradient(colors: [.black.opacity(0.65), .clear, .black.opacity(0.75)],
                           startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()

            VStack {
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(timeString(context.date))
                            .font(.system(size: 120, weight: .ultraLight, design: .rounded))
                            .monospacedDigit()
                        Text(dateString(context.date))
                            .font(.system(size: 26, weight: .light))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(48)
            }

            if photos.status != .authorized && photos.status != .limited {
                Text("Photo access is off — showing the clock only.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 40)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: photos.image)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        stop()
        let interval = TimeInterval(max(5, intervalSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in await photos.advance() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = use24Hour ? "HH:mm" : "h:mm"
        return formatter.string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }
}

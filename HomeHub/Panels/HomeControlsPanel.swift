import SwiftUI

/// One panel for both smart-home backends. Home Assistant tiles come from the
/// pinned entity list in Settings; HomeKit tiles only exist when the app is
/// built with the HOMEHUB_HOMEKIT flag and the matching entitlement.
struct HomeControlsPanel: View {
    @ObservedObject var homeAssistant: HomeAssistantClient
    let pinnedEntityIDs: [String]
    let isConfigured: Bool

    #if HOMEHUB_HOMEKIT
    @ObservedObject var homeKit: HomeKitService
    #endif

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHeader(title: "Home",
                        systemImage: "house.fill",
                        trailing: statusText)

            if !isConfigured && !hasHomeKit {
                PanelPlaceholder(message: "Add a Home Assistant URL and token in Settings, or build with HomeKit enabled.")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if !pinned.isEmpty {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(pinned) { entity in
                                    haTile(entity)
                                }
                            }
                        } else if isConfigured {
                            PanelPlaceholder(message: "No entities pinned yet — choose some in Settings.")
                        }

                        #if HOMEHUB_HOMEKIT
                        homeKitSection
                        #endif
                    }
                }
            }
        }
        .panel()
    }

    private var pinned: [HAEntity] {
        pinnedEntityIDs.compactMap { homeAssistant.entity($0) }
    }

    private var statusText: String? {
        if let error = homeAssistant.errorMessage { return error }
        return isConfigured ? (homeAssistant.isReachable ? "connected" : "offline") : nil
    }

    private var hasHomeKit: Bool {
        #if HOMEHUB_HOMEKIT
        return !homeKit.accessories.isEmpty || !homeKit.scenes.isEmpty
        #else
        return false
        #endif
    }

    private func haTile(_ entity: HAEntity) -> some View {
        Button {
            Task { await homeAssistant.toggle(entity) }
        } label: {
            Tile(symbol: entity.symbol,
                 name: entity.friendlyName,
                 detail: detail(for: entity),
                 isOn: entity.isOn,
                 isEnabled: entity.isToggleable)
        }
        .buttonStyle(.plain)
        .disabled(!entity.isToggleable)
    }

    private func detail(for entity: HAEntity) -> String {
        if entity.isToggleable { return entity.isOn ? "On" : "Off" }
        return entity.unit.isEmpty ? entity.state : "\(entity.state) \(entity.unit)"
    }

    #if HOMEHUB_HOMEKIT
    @ViewBuilder
    private var homeKitSection: some View {
        if !homeKit.scenes.isEmpty {
            Text("SCENES")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.1)
                .foregroundColor(Theme.tertiaryText)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(homeKit.scenes) { scene in
                    Button { homeKit.run(scene) } label: {
                        Tile(symbol: "theatermasks.fill",
                             name: scene.name,
                             detail: "Run",
                             isOn: false,
                             isEnabled: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if !homeKit.accessories.isEmpty {
            Text(homeKit.homeName.isEmpty ? "HOMEKIT" : homeKit.homeName.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.1)
                .foregroundColor(Theme.tertiaryText)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(homeKit.accessories) { accessory in
                    Button { homeKit.toggle(accessory) } label: {
                        Tile(symbol: accessory.symbol,
                             name: accessory.name,
                             detail: accessory.isReachable ? (accessory.isOn ? "On" : "Off") : "Unreachable",
                             isOn: accessory.isOn,
                             isEnabled: accessory.supportsPower && accessory.isReachable)
                    }
                    .buttonStyle(.plain)
                    .disabled(!accessory.supportsPower || !accessory.isReachable)
                }
            }
        }
    }
    #endif
}

private struct Tile: View {
    let symbol: String
    let name: String
    let detail: String
    let isOn: Bool
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundColor(isOn ? Theme.warm : Theme.secondaryText)
            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(detail)
                .font(.system(size: 13))
                .foregroundColor(Theme.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isOn ? Theme.warm.opacity(0.16) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isOn ? Theme.warm.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(isEnabled ? 1 : 0.75)
    }
}

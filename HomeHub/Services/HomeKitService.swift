import Foundation

#if HOMEHUB_HOMEKIT
import HomeKit

struct HKAccessory: Identifiable, Equatable {
    let id: UUID
    let name: String
    let room: String
    let isOn: Bool
    let isReachable: Bool
    let supportsPower: Bool
    let symbol: String
}

struct HKScene: Identifiable, Equatable {
    let id: UUID
    let name: String
}

/// HomeKit needs the `com.apple.developer.homekit` entitlement, which is only
/// issued to paid Apple Developer Program accounts. The whole file is behind
/// the HOMEHUB_HOMEKIT flag so a free-Apple-ID sideload still builds.
@MainActor
final class HomeKitService: NSObject, ObservableObject, HMHomeManagerDelegate {
    @Published private(set) var accessories: [HKAccessory] = []
    @Published private(set) var scenes: [HKScene] = []
    @Published private(set) var homeName: String = ""
    @Published private(set) var authorized = false

    private var manager: HMHomeManager?

    func start() {
        guard manager == nil else { return }
        let manager = HMHomeManager()
        manager.delegate = self
        self.manager = manager
    }

    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in self.reload() }
    }

    nonisolated func homeManager(_ manager: HMHomeManager,
                                 didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor in
            self.authorized = status.contains(.authorized)
            self.reload()
        }
    }

    private func reload() {
        guard let home = manager?.primaryHome else {
            accessories = []
            scenes = []
            homeName = ""
            return
        }
        homeName = home.name
        scenes = home.actionSets
            .filter { !$0.actions.isEmpty }
            .map { HKScene(id: $0.uniqueIdentifier, name: $0.name) }
            .sorted { $0.name < $1.name }

        accessories = home.accessories.compactMap { accessory in
            let power = Self.powerCharacteristic(accessory)
            let isOn = (power?.value as? Bool) ?? false
            return HKAccessory(id: accessory.uniqueIdentifier,
                               name: accessory.name,
                               room: accessory.room?.name ?? "",
                               isOn: isOn,
                               isReachable: accessory.isReachable,
                               supportsPower: power != nil,
                               symbol: Self.symbol(for: accessory))
        }
        .sorted { ($0.room, $0.name) < ($1.room, $1.name) }
    }

    func toggle(_ item: HKAccessory) {
        guard let home = manager?.primaryHome,
              let accessory = home.accessories.first(where: { $0.uniqueIdentifier == item.id }),
              let characteristic = Self.powerCharacteristic(accessory) else { return }

        let newValue = !item.isOn
        characteristic.writeValue(newValue) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func run(_ scene: HKScene) {
        guard let home = manager?.primaryHome,
              let actionSet = home.actionSets.first(where: { $0.uniqueIdentifier == scene.id }) else { return }
        home.executeActionSet(actionSet) { _ in }
    }

    private static func powerCharacteristic(_ accessory: HMAccessory) -> HMCharacteristic? {
        for service in accessory.services {
            for characteristic in service.characteristics
            where characteristic.characteristicType == HMCharacteristicTypePowerState {
                return characteristic
            }
        }
        return nil
    }

    private static func symbol(for accessory: HMAccessory) -> String {
        for service in accessory.services {
            switch service.serviceType {
            case HMServiceTypeLightbulb: return "lightbulb.fill"
            case HMServiceTypeOutlet: return "poweroutlet.type.b.fill"
            case HMServiceTypeSwitch: return "switch.2"
            case HMServiceTypeFan: return "fanblades.fill"
            case HMServiceTypeThermostat: return "thermometer.medium"
            case HMServiceTypeLockMechanism: return "lock.fill"
            case HMServiceTypeGarageDoorOpener: return "door.garage.closed"
            case HMServiceTypeWindowCovering: return "blinds.horizontal.closed"
            default: continue
            }
        }
        return "homekit"
    }
}
#endif

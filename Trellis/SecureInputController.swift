import Carbon

/// Balance only this process's secure-input request, without disabling another owner's request.
@MainActor
final class SecureInputController {
    private(set) var enabled = false
    private let enable: () -> OSStatus
    private let disable: () -> OSStatus

    init(enable: @escaping () -> OSStatus = { EnableSecureEventInput() },
         disable: @escaping () -> OSStatus = { DisableSecureEventInput() }) {
        self.enable = enable
        self.disable = disable
    }

    @discardableResult
    func update(requested: Bool) -> OSStatus {
        guard requested != enabled else { return noErr }
        let result = requested ? enable() : disable()
        if result == noErr { enabled = requested }
        return result
    }
}

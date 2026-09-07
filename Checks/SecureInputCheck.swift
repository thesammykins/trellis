import Carbon

@main
struct SecureInputCheck {
    @MainActor static func main() {
        var calls: [String] = []
        var failure = false
        let controller = SecureInputController(enable: {
            calls.append("enable")
            return failure ? -1 : noErr
        }, disable: {
            calls.append("disable")
            return failure ? -1 : noErr
        })
        controller.update(requested: false)
        controller.update(requested: true)
        controller.update(requested: true)
        assert(controller.enabled && calls == ["enable"])
        failure = true
        assert(controller.update(requested: false) != noErr && controller.enabled)
        failure = false
        controller.update(requested: false)
        controller.update(requested: false)
        assert(!controller.enabled && calls == ["enable", "disable", "disable"])
        failure = true
        assert(controller.update(requested: true) != noErr && !controller.enabled)
        print("PASS secure-input balance, duplicate requests and error state")
    }
}

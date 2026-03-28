import AVFoundation
import Foundation

@MainActor
final class WebcamActivityMonitor {
    private var observation: NSKeyValueObservation?

    func startMonitoring(onActiveChanged: @escaping (Bool) -> Void) {
        stopMonitoring()
        guard let device = AVCaptureDevice.default(for: .video) else { return }

        observation = device.observe(\.isInUseByAnotherApplication, options: [.new, .initial]) { _, change in
            let isActive = change.newValue ?? false
            Task { @MainActor in
                onActiveChanged(isActive)
            }
        }
    }

    func stopMonitoring() {
        observation?.invalidate()
        observation = nil
    }
}

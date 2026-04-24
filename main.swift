import Cocoa
import AVFoundation

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let completion: (NSImage?) -> Void
    init(completion: @escaping (NSImage?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = NSImage(data: data) else {
            completion(nil); return
        }
        completion(image)
    }
}

final class CameraWindowController: NSWindowController, NSWindowDelegate {
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var photoDelegate: PhotoCaptureDelegate?
    private var statusLabel: NSTextField!
    private var captureButton: NSButton!
    private var cameraPopup: NSPopUpButton!
    private var currentInput: AVCaptureDeviceInput?
    private var availableDevices: [AVCaptureDevice] = []
    private static let lastCameraKey = "NotesSnap.lastCameraUniqueID"

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "NotesSnap"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        buildUI()
        requestAccessAndStart()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let previewView = NSView()
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true
        previewView.layer?.backgroundColor = NSColor.black.cgColor
        contentView.addSubview(previewView)

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspect
        previewView.layer?.addSublayer(previewLayer)

        captureButton = NSButton(title: "Capture", target: self, action: #selector(capturePhoto))
        captureButton.bezelStyle = .rounded
        captureButton.keyEquivalent = "\r"
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.isEnabled = false
        contentView.addSubview(captureButton)

        cameraPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        cameraPopup.translatesAutoresizingMaskIntoConstraints = false
        cameraPopup.target = self
        cameraPopup.action = #selector(cameraSelectionChanged)
        cameraPopup.isEnabled = false
        contentView.addSubview(cameraPopup)

        statusLabel = NSTextField(labelWithString: "Requesting camera access…")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: contentView.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -60),

            captureButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            captureButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

            cameraPopup.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cameraPopup.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            cameraPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 220),

            statusLabel.leadingAnchor.constraint(equalTo: cameraPopup.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: captureButton.leadingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
        ])

        // Keep preview layer sized to its view.
        previewView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: previewView, queue: .main
        ) { [weak self] _ in
            self?.previewLayer.frame = previewView.bounds
        }
    }

    private func requestAccessAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configureSession() : self?.showDenied()
                }
            }
        default:
            showDenied()
        }
    }

    private func showDenied() {
        statusLabel.stringValue = "Camera access denied — enable it in System Settings › Privacy & Security › Camera."
    }

    private func discoverDevices() -> [AVCaptureDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            types.append(.external)
            types.append(.continuityCamera)
        } else {
            types.append(.externalUnknown)
        }
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified
        )
        // Deduplicate by uniqueID (older device types can overlap with newer ones).
        var seen = Set<String>()
        return session.devices.filter { seen.insert($0.uniqueID).inserted }
    }

    private func preferredDevice(from devices: [AVCaptureDevice]) -> AVCaptureDevice? {
        if let saved = UserDefaults.standard.string(forKey: Self.lastCameraKey),
           let match = devices.first(where: { $0.uniqueID == saved }) {
            return match
        }
        return AVCaptureDevice.default(for: .video) ?? devices.first
    }

    private func refreshCameraMenu(selected: AVCaptureDevice?) {
        cameraPopup.removeAllItems()
        for device in availableDevices {
            let item = NSMenuItem(title: device.localizedName, action: nil, keyEquivalent: "")
            item.representedObject = device.uniqueID
            cameraPopup.menu?.addItem(item)
        }
        if let selected = selected,
           let idx = availableDevices.firstIndex(where: { $0.uniqueID == selected.uniqueID }) {
            cameraPopup.selectItem(at: idx)
        }
        cameraPopup.isEnabled = availableDevices.count > 1
    }

    private func configureSession() {
        statusLabel.stringValue = "Starting camera…"
        availableDevices = discoverDevices()
        guard let device = preferredDevice(from: availableDevices) else {
            statusLabel.stringValue = "No camera found."
            return
        }
        refreshCameraMenu(selected: device)
        switchToDevice(device, initial: true)
    }

    private func switchToDevice(_ device: AVCaptureDevice, initial: Bool) {
        captureButton.isEnabled = false
        if !initial { statusLabel.stringValue = "Switching camera…" }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .photo

            if let existing = self.currentInput {
                self.captureSession.removeInput(existing)
                self.currentInput = nil
            }

            guard let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async {
                    self.statusLabel.stringValue = "Couldn't open \(device.localizedName)."
                }
                return
            }
            self.captureSession.addInput(input)
            self.currentInput = input

            if self.captureSession.outputs.isEmpty,
               self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
            }
            self.captureSession.commitConfiguration()

            if !self.captureSession.isRunning { self.captureSession.startRunning() }

            UserDefaults.standard.set(device.uniqueID, forKey: Self.lastCameraKey)

            DispatchQueue.main.async {
                self.captureButton.isEnabled = true
                self.statusLabel.stringValue = "Ready — press ⏎ or click Capture."
            }
        }
    }

    @objc private func cameraSelectionChanged(_ sender: NSPopUpButton) {
        guard let uid = sender.selectedItem?.representedObject as? String,
              let device = availableDevices.first(where: { $0.uniqueID == uid }),
              device.uniqueID != currentInput?.device.uniqueID else { return }
        switchToDevice(device, initial: false)
    }

    @objc private func capturePhoto() {
        captureButton.isEnabled = false
        statusLabel.stringValue = "Capturing…"
        let settings = AVCapturePhotoSettings()
        photoDelegate = PhotoCaptureDelegate { [weak self] image in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let image = image {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([image])
                    self.statusLabel.stringValue = "Copied to clipboard ✓"
                } else {
                    self.statusLabel.stringValue = "Capture failed."
                }
                self.captureButton.isEnabled = true
                // Auto-close shortly after success so the next click gives a fresh window.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.close()
                }
            }
        }
        photoOutput.capturePhoto(with: settings, delegate: photoDelegate!)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var cameraWindow: CameraWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "NotesSnap"
            )
            button.image?.isTemplate = true
            button.action = #selector(handleClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            openCamera()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture Notes", action: #selector(openCamera), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit NotesSnap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach menu so the next left-click triggers the action again.
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    @objc private func openCamera() {
        if cameraWindow == nil || cameraWindow?.window?.isVisible == false {
            cameraWindow = CameraWindowController()
        }
        cameraWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

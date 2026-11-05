#if os(macOS)
  import AppKit
  import Carbon.HIToolbox
  import CoreGraphics
  import SwiftUI
  import HoverClickCore

  private enum ClickAction: UInt32 {
    case left = 1
    case right = 2
  }

  @MainActor
  private final class AppController: ObservableObject {
    @Published private(set) var leftShortcut: Shortcut
    @Published private(set) var rightShortcut: Shortcut
    @Published var statusMessage = "Ready. Move the pointer over a target and use a shortcut."

    private let hotKeys = CarbonHotKeyManager()
    private let leftDefaultsKey = "leftClickShortcut"
    private let rightDefaultsKey = "rightClickShortcut"
    private var isConfiguringShortcuts = false
    private let drawingGestureDefaultsKey = "drawingGestureEnabled"
    private let drawingGestures = MouseDrawingGestureManager()
    @Published private(set) var isDrawingGestureEnabled = UserDefaults.standard.bool(
      forKey: "drawingGestureEnabled")

    init() {
      leftShortcut = Self.loadShortcut(forKey: "leftClickShortcut") ?? .defaultLeftClick
      rightShortcut = Self.loadShortcut(forKey: "rightClickShortcut") ?? .defaultRightClick

      hotKeys.onAction = { [weak self] action in
        // Snapshot the pointer before the actor hop so a quick subsequent
        // mouse movement cannot change the intended click target.
        let pointerPosition = CGEvent(source: nil)?.location
        Task { @MainActor in self?.perform(action, at: pointerPosition) }
      }
      drawingGestures.onStatus = { [weak self] message in
        Task { @MainActor in self?.statusMessage = message }
      }
      do {
        try hotKeys.register(left: leftShortcut, right: rightShortcut)
      } catch {
        statusMessage = "Could not register shortcuts: \(error.localizedDescription)"
      }
      if isDrawingGestureEnabled {
        activateDrawingGesture()
      }
    }

    func setDrawingGestureEnabled(_ enabled: Bool) {
      if enabled {
        activateDrawingGesture()
      } else {
        drawingGestures.stop()
        isDrawingGestureEnabled = false
        UserDefaults.standard.set(false, forKey: drawingGestureDefaultsKey)
        statusMessage = "Right-click drawing gesture disabled."
      }
    }

    private func activateDrawingGesture() {
      guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
        isDrawingGestureEnabled = false
        UserDefaults.standard.set(false, forKey: drawingGestureDefaultsKey)
        statusMessage =
          "Drawing needs the Device Control and Data Access permission (called Accessibility on older macOS versions) to filter the right-button drag and post the resulting context click."
        return
      }
      do {
        try drawingGestures.start()
        isDrawingGestureEnabled = true
        UserDefaults.standard.set(true, forKey: drawingGestureDefaultsKey)
        statusMessage = "Drawing enabled. Hold the right mouse button, draw a C, and release."
      } catch {
        isDrawingGestureEnabled = false
        UserDefaults.standard.set(false, forKey: drawingGestureDefaultsKey)
        statusMessage = "Could not enable drawing: \(error.localizedDescription)"
      }
    }

    func beginShortcutConfiguration() {
      guard !isConfiguringShortcuts else { return }
      isConfiguringShortcuts = true
      // Release our existing global chords while the user records replacements.
      // Otherwise Carbon may intercept a chord before the settings field can see it.
      hotKeys.unregisterCurrent()
      statusMessage =
        "Recording mode active. Save your shortcuts, then close Settings to activate them."
    }

    func endShortcutConfiguration() {
      guard isConfiguringShortcuts else { return }
      isConfiguringShortcuts = false
      do {
        try hotKeys.register(left: leftShortcut, right: rightShortcut)
        statusMessage = "Shortcuts active."
      } catch {
        statusMessage = "Could not activate shortcuts: \(error.localizedDescription)"
      }
    }

    func updateShortcuts(left: Shortcut, right: Shortcut) {
      guard left.hasModifier, right.hasModifier else {
        statusMessage = "Each shortcut must include Command, Option, Control or Shift."
        return
      }
      guard left != right else {
        statusMessage = "The two actions need different shortcuts."
        return
      }

      // While Settings is open, keep Carbon hotkeys unregistered so a just-recorded
      // shortcut cannot be swallowed by our own global handler. Register on close.
      if !isConfiguringShortcuts {
        do {
          try hotKeys.register(left: left, right: right)
        } catch {
          statusMessage =
            "Shortcut registration failed (it may already be in use). \(error.localizedDescription)"
          return
        }
      }

      leftShortcut = left
      rightShortcut = right
      Self.save(left, forKey: leftDefaultsKey)
      Self.save(right, forKey: rightDefaultsKey)
      statusMessage =
        isConfiguringShortcuts
        ? "Shortcuts saved. Close Settings to activate them."
        : "Shortcuts saved and active."
    }

    func resetShortcuts() {
      updateShortcuts(left: .defaultLeftClick, right: .defaultRightClick)
    }

    private func perform(_ action: ClickAction, at position: CGPoint?) {
      guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
        statusMessage =
          "Click permission is not enabled. Allow HoverClick under System Settings → Privacy & Security → Device Control and Data Access (called Accessibility on older macOS versions), then try again."
        showPermissionAlert()
        return
      }

      guard let position else {
        statusMessage = "Could not read the current pointer position."
        return
      }

      let button: CGMouseButton = action == .left ? .left : .right
      let downType: CGEventType = action == .left ? .leftMouseDown : .rightMouseDown
      let upType: CGEventType = action == .left ? .leftMouseUp : .rightMouseUp

      guard
        let down = CGEvent(
          mouseEventSource: nil,
          mouseType: downType,
          mouseCursorPosition: position,
          mouseButton: button
        ),
        let up = CGEvent(
          mouseEventSource: nil,
          mouseType: upType,
          mouseCursorPosition: position,
          mouseButton: button
        )
      else {
        statusMessage = "macOS could not create the mouse event."
        return
      }

      // Mark synthetic events so the optional drawing event tap does not
      // mistake HoverClick's own right-click for a physical drawing gesture.
      down.setIntegerValueField(
        .eventSourceUserData, value: MouseDrawingGestureManager.syntheticEventTag)
      up.setIntegerValueField(
        .eventSourceUserData, value: MouseDrawingGestureManager.syntheticEventTag)
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
      statusMessage =
        action == .left ? "Left-click sent at the pointer." : "Right-click sent at the pointer."
    }

    private func showPermissionAlert() {
      let alert = NSAlert()
      alert.messageText = "HoverClick needs Accessibility permission"
      alert.informativeText =
        "Open System Settings → Privacy & Security → Device Control and Data Access (called Accessibility on older macOS versions) and enable HoverClick. Then press the shortcut again. HoverClick does not request Input Monitoring."
      alert.addButton(withTitle: "Open Accessibility Settings")
      alert.addButton(withTitle: "Later")
      NSApp.activate(ignoringOtherApps: true)
      if alert.runModal() == .alertFirstButtonReturn,
        let url = URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
      {
        NSWorkspace.shared.open(url)
      }
    }

    private static func loadShortcut(forKey key: String) -> Shortcut? {
      guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
      return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    private static func save(_ shortcut: Shortcut, forKey key: String) {
      guard let data = try? JSONEncoder().encode(shortcut) else { return }
      UserDefaults.standard.set(data, forKey: key)
    }
  }

  private final class CarbonHotKeyManager {
    var onAction: ((ClickAction) -> Void)?
    private var eventHandler: EventHandlerRef?
    private var leftReference: EventHotKeyRef?
    private var rightReference: EventHotKeyRef?

    fileprivate static let signature: OSType = 0x4843_4C4B  // "HCLK"

    func register(left: Shortcut, right: Shortcut) throws {
      guard left.hasModifier, right.hasModifier else {
        throw HotKeyError.modifierRequired
      }
      guard left != right else { throw HotKeyError.duplicateShortcuts }
      try installEventHandlerIfNeeded()

      unregisterCurrent()
      do {
        leftReference = try registerOne(left, action: .left)
        rightReference = try registerOne(right, action: .right)
      } catch {
        unregisterCurrent()
        throw error
      }
    }

    private func installEventHandlerIfNeeded() throws {
      guard eventHandler == nil else { return }
      var eventType = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
      )
      let userData = Unmanaged.passUnretained(self).toOpaque()
      let status = InstallEventHandler(
        GetApplicationEventTarget(),
        hoverClickCarbonEventHandler,
        1,
        &eventType,
        userData,
        &eventHandler
      )
      guard status == noErr else {
        eventHandler = nil
        throw HotKeyError.eventHandlerInstallFailed(status)
      }
    }

    private func registerOne(_ shortcut: Shortcut, action: ClickAction) throws -> EventHotKeyRef {
      var reference: EventHotKeyRef?
      let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
      let status = RegisterEventHotKey(
        UInt32(shortcut.keyCode),
        shortcut.modifiers,
        hotKeyID,
        GetApplicationEventTarget(),
        0,
        &reference
      )
      guard status == noErr, let reference else {
        throw HotKeyError.registrationFailed(status)
      }
      return reference
    }

    fileprivate func unregisterCurrent() {
      if let leftReference { UnregisterEventHotKey(leftReference) }
      if let rightReference { UnregisterEventHotKey(rightReference) }
      leftReference = nil
      rightReference = nil
    }

    deinit {
      unregisterCurrent()
      if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private enum HotKeyError: LocalizedError {
      case modifierRequired
      case duplicateShortcuts
      case registrationFailed(OSStatus)
      case eventHandlerInstallFailed(OSStatus)

      var errorDescription: String? {
        switch self {
        case .modifierRequired:
          return "A shortcut must include at least one modifier key."
        case .duplicateShortcuts:
          return "Left-click and right-click shortcuts cannot be identical."
        case .registrationFailed(let status):
          return "macOS returned hotkey registration error \(status)."
        case .eventHandlerInstallFailed(let status):
          return "Could not install the global shortcut handler (error \(status))."
        }
      }
    }
  }

  // A top-level function cannot capture the manager's dynamic Self, so it is
  // safe to pass directly as Carbon's C-compatible event-handler callback.
  private func hoverClickCarbonEventHandler(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
  ) -> OSStatus {
    guard let event, let userData else { return noErr }
    let manager = Unmanaged<CarbonHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    var hotKeyID = EventHotKeyID()
    let result = GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &hotKeyID
    )
    guard result == noErr,
      hotKeyID.signature == CarbonHotKeyManager.signature,
      let action = ClickAction(rawValue: hotKeyID.id)
    else { return noErr }
    manager.onAction?(action)
    return noErr
  }

  /// Optional BTT-style right-button drawing mode. A physical right-click is
  /// held briefly by an active session event tap. A short press is replayed as
  /// a normal context click; a right-button drag is treated as a unistroke.
  /// This uses the app's Accessibility permission and does not install a
  /// listen-only keyboard event tap or request Input Monitoring.
  private final class MouseDrawingGestureManager {
    fileprivate static let syntheticEventTag: Int64 = 0x4843_4C4B_4D4F_5553  // "HCLKMOUS"
    private static let minimumGestureTravel = 42.0
    private static let minimumBoundingDisplacement = 22.0
    private static let recognitionThreshold = 0.72

    var onStatus: ((String) -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isTrackingRightButton = false
    private var startPosition: CGPoint?
    private var points: [GesturePoint] = []
    private var lastPoint: CGPoint?
    private var totalTravel = 0.0
    private let cTemplate = UnistrokeRecognizer.cTemplate()

    deinit {
      stop()
    }

    func start() throws {
      guard eventTap == nil else { return }
      let eventMask =
        (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
        | (CGEventMask(1) << CGEventType.rightMouseDragged.rawValue)
        | (CGEventMask(1) << CGEventType.rightMouseUp.rawValue)

      let context = Unmanaged.passUnretained(self).toOpaque()
      guard
        let tap = CGEvent.tapCreate(
          tap: .cgSessionEventTap,
          place: .headInsertEventTap,
          options: .defaultTap,
          eventsOfInterest: eventMask,
          callback: hoverClickMouseGestureEventTapCallback,
          userInfo: context
        )
      else {
        throw DrawingError.eventTapUnavailable
      }

      guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
        CFMachPortInvalidate(tap)
        throw DrawingError.runLoopSourceUnavailable
      }

      eventTap = tap
      runLoopSource = source
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
      // Do not leave a physical right-button press swallowed if the user turns
      // the feature off in the middle of a drawing.
      if isTrackingRightButton, let startPosition {
        postRightClick(at: startPosition)
      }
      resetGesture()
      if let source = runLoopSource {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      }
      if let tap = eventTap {
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
      }
      runLoopSource = nil
      eventTap = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
      // Pass through events generated by HoverClick itself.
      if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventTag {
        return Unmanaged.passUnretained(event)
      }

      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        return Unmanaged.passUnretained(event)
      }

      switch type {
      case .rightMouseDown:
        // Hold the physical down event until release so an unrecognized short
        // press can be replayed as an ordinary right-click without leaking a
        // partial click into the target application.
        resetGesture()
        isTrackingRightButton = true
        startPosition = event.location
        append(event.location, force: true)
        return nil

      case .rightMouseDragged:
        guard isTrackingRightButton else { return Unmanaged.passUnretained(event) }
        append(event.location)
        return nil

      case .rightMouseUp:
        guard isTrackingRightButton else { return Unmanaged.passUnretained(event) }
        append(event.location, force: true)
        finishGesture(at: event.location)
        return nil

      default:
        return Unmanaged.passUnretained(event)
      }
    }

    private func append(_ position: CGPoint, force: Bool = false) {
      if let lastPoint {
        let dx = position.x - lastPoint.x
        let dy = position.y - lastPoint.y
        let step = hypot(dx, dy)
        totalTravel += step
        if force || step >= 2.0 {
          points.append(GesturePoint(x: position.x, y: position.y))
          self.lastPoint = position
        }
      } else {
        points.append(GesturePoint(x: position.x, y: position.y))
        lastPoint = position
      }
      // A user can generate thousands of drag events in a single gesture.
      // Keep enough points for shape detail without unbounded memory growth.
      if points.count > 512 {
        points = stride(from: 0, to: points.count, by: 2).map { points[$0] }
      }
    }

    private func finishGesture(at endPosition: CGPoint) {
      defer { resetGesture() }
      guard let startPosition else { return }

      let displacement = hypot(
        endPosition.x - startPosition.x,
        endPosition.y - startPosition.y
      )
      if totalTravel < Self.minimumGestureTravel || displacement < Self.minimumBoundingDisplacement
      {
        postRightClick(at: startPosition)
        onStatus?("Right-click sent. Draw a longer C-shaped drag to use the gesture.")
        return
      }

      let confidence = UnistrokeRecognizer.score(points, against: cTemplate)
      guard confidence >= Self.recognitionThreshold else {
        onStatus?(
          "Drawing not recognized (\(Int(confidence * 100))%). Try a single C-shaped stroke.")
        return
      }

      postRightClick(at: endPosition)
      onStatus?("C gesture recognized (\(Int(confidence * 100))%). Context-click sent.")
    }

    private func postRightClick(at position: CGPoint) {
      guard
        let down = CGEvent(
          mouseEventSource: nil,
          mouseType: .rightMouseDown,
          mouseCursorPosition: position,
          mouseButton: .right
        ),
        let up = CGEvent(
          mouseEventSource: nil,
          mouseType: .rightMouseUp,
          mouseCursorPosition: position,
          mouseButton: .right
        )
      else {
        onStatus?("macOS could not create the right-click event.")
        return
      }
      down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
      up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventTag)
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
    }

    private func resetGesture() {
      isTrackingRightButton = false
      startPosition = nil
      points.removeAll(keepingCapacity: true)
      lastPoint = nil
      totalTravel = 0
    }

    private enum DrawingError: LocalizedError {
      case eventTapUnavailable
      case runLoopSourceUnavailable

      var errorDescription: String? {
        switch self {
        case .eventTapUnavailable:
          return
            "macOS did not allow the mouse event tap. Check HoverClick under System Settings → Privacy & Security → Accessibility. No Input Monitoring permission is requested."
        case .runLoopSourceUnavailable:
          return "Could not attach the mouse gesture monitor to the app's run loop."
        }
      }
    }
  }

  private func hoverClickMouseGestureEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
  ) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<MouseDrawingGestureManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handle(type: type, event: event)
  }

  @main
  struct HoverClickApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
      MenuBarExtra {
        VStack(alignment: .leading, spacing: 12) {
          Text("HoverClick").font(.headline)
          Text("Move your pointer over an item, then use a shortcut.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          Divider()
          LabeledContent("Left-click", value: controller.leftShortcut.displayText)
          LabeledContent("Right-click", value: controller.rightShortcut.displayText)
          LabeledContent("Draw a C", value: controller.isDrawingGestureEnabled ? "On" : "Off")
          Divider()
          Text(controller.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          SettingsLink {
            Label("Configure shortcuts…", systemImage: "keyboard")
          }
          Button("Quit HoverClick") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 280)
      } label: {
        Image(systemName: "cursorarrow.click")
      }
      .menuBarExtraStyle(.window)

      Settings {
        ShortcutSettingsView(controller: controller)
          .onAppear { controller.beginShortcutConfiguration() }
          .onDisappear { controller.endShortcutConfiguration() }
      }
    }
  }

  private struct ShortcutSettingsView: View {
    @ObservedObject var controller: AppController
    @State private var leftDraft: Shortcut
    @State private var rightDraft: Shortcut

    init(controller: AppController) {
      self.controller = controller
      _leftDraft = State(initialValue: controller.leftShortcut)
      _rightDraft = State(initialValue: controller.rightShortcut)
    }

    var body: some View {
      Form {
        Section("Mouse actions") {
          HStack {
            Text("Select / left-click")
            Spacer()
            ShortcutRecorder(shortcut: leftDraft) { leftDraft = $0 }
          }
          HStack {
            Text("Context menu / right-click")
            Spacer()
            ShortcutRecorder(shortcut: rightDraft) { rightDraft = $0 }
          }
        }

        Section("Drawing gesture") {
          Toggle(
            "Enable right-click drawing",
            isOn: Binding(
              get: { controller.isDrawingGestureEnabled },
              set: { controller.setDrawingGestureEnabled($0) }
            )
          )
          Text(
            "Hold the right mouse button, draw a C in one continuous stroke, then release. HoverClick recognizes the C and sends a context-click at the end of the stroke. A short right-click stays a normal context-click; an unrecognized drag is ignored."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }

        Section {
          HStack {
            Button("Reset defaults") {
              leftDraft = .defaultLeftClick
              rightDraft = .defaultRightClick
            }
            Spacer()
            Button("Save shortcuts") {
              controller.updateShortcuts(left: leftDraft, right: rightDraft)
            }
            .keyboardShortcut(.defaultAction)
          }
        }

        Section("How it works") {
          Text(
            "Click a shortcut field, then press a key combination that includes at least one modifier (⌘, ⌥, ⌃ or ⇧). The click is sent at the pointer’s current position; the pointer itself does not move."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
        Section("Status") {
          Text(controller.statusMessage)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .padding(18)
      .frame(width: 520, height: 480)
    }
  }

  private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut
    let onChange: (Shortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
      let view = ShortcutRecorderView()
      view.shortcut = shortcut
      view.onCapture = onChange
      return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
      nsView.shortcut = shortcut
      nsView.onCapture = onChange
      nsView.needsDisplay = true
    }
  }

  private final class ShortcutRecorderView: NSView {
    var shortcut = Shortcut.defaultLeftClick
    var onCapture: ((Shortcut) -> Void)?
    private var isRecording = false
    private var localKeyMonitor: Any?

    deinit {
      if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 170, height: 32) }

    override func mouseDown(with event: NSEvent) {
      guard let window, window.makeFirstResponder(self) else {
        NSSound.beep()
        return
      }
      startRecording()
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil { stopRecording() }
    }

    private func startRecording() {
      stopRecording()
      isRecording = true
      // A local monitor sees key-down events before AppKit routes Command
      // combinations through menus/key equivalents. Carbon shortcuts are
      // suspended for the lifetime of the Settings window by the controller.
      localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, self.isRecording, event.window === self.window else { return event }
        _ = self.capture(event)
        return nil
      }
      needsDisplay = true
    }

    private func stopRecording() {
      isRecording = false
      if let localKeyMonitor {
        NSEvent.removeMonitor(localKeyMonitor)
        self.localKeyMonitor = nil
      }
      needsDisplay = true
    }

    // Keep a responder-chain fallback in case a host window bypasses the
    // local monitor for a key equivalent.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      guard isRecording else { return super.performKeyEquivalent(with: event) }
      return capture(event)
    }

    override func keyDown(with event: NSEvent) {
      guard isRecording else {
        super.keyDown(with: event)
        return
      }
      _ = capture(event)
    }

    @discardableResult
    private func capture(_ event: NSEvent) -> Bool {
      if event.keyCode == 53 {  // Escape cancels capture.
        stopRecording()
        return true
      }

      let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
      var carbonFlags: UInt32 = 0
      if flags.contains(.command) { carbonFlags |= Shortcut.commandMask }
      if flags.contains(.option) { carbonFlags |= Shortcut.optionMask }
      if flags.contains(.control) { carbonFlags |= Shortcut.controlMask }
      if flags.contains(.shift) { carbonFlags |= Shortcut.shiftMask }

      guard carbonFlags != 0 else {
        NSSound.beep()
        needsDisplay = true
        return true
      }

      let captured = Shortcut(keyCode: event.keyCode, modifiers: carbonFlags)
      shortcut = captured
      stopRecording()
      onCapture?(captured)
      needsDisplay = true
      return true
    }

    override func draw(_ dirtyRect: NSRect) {
      let rect = bounds.insetBy(dx: 1, dy: 1)
      let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
      (isRecording
        ? NSColor.controlAccentColor.withAlphaComponent(0.13) : NSColor.controlBackgroundColor)
        .setFill()
      path.fill()
      (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
      path.lineWidth = 1
      path.stroke()

      let title = isRecording ? "Press shortcut…" : shortcut.displayText
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor.labelColor,
      ]
      let text = NSAttributedString(string: title, attributes: attributes)
      let size = text.size()
      text.draw(
        at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
  }

#else
  import Foundation

  @main
  struct HoverClickUnsupportedPlatform {
    static func main() {
      print("HoverClick is a macOS menu-bar utility. Build and run it on macOS.")
    }
  }
#endif

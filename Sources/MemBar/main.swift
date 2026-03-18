import AppKit
import Foundation
import Network

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Memory Stats
// ─────────────────────────────────────────────────────────────────────────────

struct MemoryStats {
    let used:   UInt64
    let wired:  UInt64
    let total:  UInt64

    var usedGB:   Double { Double(used)  / 1_073_741_824 }
    var totalGB:  Double { Double(total) / 1_073_741_824 }
    var usedMB:   Double { Double(used)  / 1_048_576 }
    var pressure: Double { totalGB > 0 ? usedGB / totalGB : 0 }

    static func current() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let pageSize = UInt64(vm_page_size)
        let total    = ProcessInfo.processInfo.physicalMemory
        guard kr == KERN_SUCCESS else {
            return MemoryStats(used: 0, wired: 0, total: total)
        }
        let active     = UInt64(stats.active_count)          * pageSize
        let wired      = UInt64(stats.wire_count)            * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        return MemoryStats(used: active + wired + compressed, wired: wired, total: total)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Wi-Fi IP helper
// ─────────────────────────────────────────────────────────────────────────────

func wifiIPAddress() -> String {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "—" }
    defer { freeifaddrs(ifaddr) }

    // Preferred Wi-Fi interface names on macOS
    let wifiNames: Set<String> = ["en0", "en1"]
    var ptr = first

    while true {
        let name = String(cString: ptr.pointee.ifa_name)
        let family = ptr.pointee.ifa_addr.pointee.sa_family

        if wifiNames.contains(name) && family == UInt8(AF_INET) {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: hostname)
            }
        }
        guard let next = ptr.pointee.ifa_next else { break }
        ptr = next
    }
    return "Not connected"
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – App Delegate
// ─────────────────────────────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var timer:      Timer?
    private var popover:    NSPopover?
    private var popoverVC:  PopoverViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        setupPopover()
        updateDisplay()

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
    }

    private func updateDisplay() {
        guard let button = statusItem.button else { return }
        let s = MemoryStats.current()

        // No leading symbol — just the number
        let value = s.usedGB >= 1
            ? String(format: "%.1f GB", s.usedGB)
            : String(format: "%.0f MB", s.usedMB)

        let attr  = NSMutableAttributedString(string: value)
        let range = NSRange(location: 0, length: value.utf16.count)

        let color: NSColor
        switch s.pressure {
        case ..<0.60: color = NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.45, alpha: 1)
        case ..<0.80: color = NSColor(calibratedRed: 1.00, green: 0.75, blue: 0.00, alpha: 1)
        default:      color = NSColor(calibratedRed: 1.00, green: 0.27, blue: 0.27, alpha: 1)
        }

        attr.addAttribute(.foregroundColor, value: color, range: range)
        attr.addAttribute(.font,
                          value: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                          range: range)

        button.attributedTitle = attr
        popoverVC?.update(stats: s)
    }

    private func setupPopover() {
        let vc    = PopoverViewController()
        popoverVC = vc
        let pop   = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        popover = pop
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let pop = popover else { return }
        if pop.isShown {
            pop.close()
        } else {
            pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Popover View Controller
// ─────────────────────────────────────────────────────────────────────────────

final class PopoverViewController: NSViewController {

    private let usedLabel     = makeLabel(size: 28, weight: .bold)
    private let totalLabel    = makeLabel(size: 12, weight: .regular, alpha: 0.55)
    private let barOuter      = NSView()
    private let barInner      = NSView()
    private let wiredLabel    = makeLabel(size: 11, weight: .regular, alpha: 0.6)
    private let pressureLabel = makeLabel(size: 11, weight: .medium)
    private let ipLabel       = makeLabel(size: 11, weight: .regular, alpha: 0.55)
    private let quitButton    = NSButton()
    private var barWidthConstraint: NSLayoutConstraint?

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 210))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 0.10, alpha: 0.96).cgColor
        v.layer?.cornerRadius    = 14
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
    }

    private func buildLayout() {
        let title = makeLabel(size: 11, weight: .semibold, alpha: 0.45)
        title.stringValue = "MEMORY  PRESSURE"
        title.alignment   = .center

        // Progress bar
        barOuter.wantsLayer = true
        barOuter.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        barOuter.layer?.cornerRadius    = 4

        barInner.wantsLayer = true
        barInner.layer?.backgroundColor = NSColor(calibratedRed: 0.2, green: 0.78, blue: 0.45, alpha: 1).cgColor
        barInner.layer?.cornerRadius    = 4
        barOuter.addSubview(barInner)

        // Divider
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor

        // Wi-Fi row
        let wifiIcon = makeLabel(size: 11, weight: .regular, alpha: 0.45)
        wifiIcon.stringValue = "Wi-Fi"
        let ipRow = hstack([wifiIcon, NSView(), ipLabel])

        // Quit button
        quitButton.title    = "Quit MemBar"
        quitButton.bezelStyle = .rounded
        quitButton.isBordered = false
        quitButton.wantsLayer = true
        quitButton.layer?.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
        quitButton.layer?.cornerRadius    = 8
        quitButton.font     = .systemFont(ofSize: 12, weight: .medium)
        quitButton.contentTintColor = NSColor(white: 1, alpha: 0.50)
        quitButton.target   = self
        quitButton.action   = #selector(quit)

        let topRow = hstack([usedLabel, NSView(), totalLabel])
        let midRow = hstack([wiredLabel, NSView(), pressureLabel])

        let stack = NSStackView(views: [title, topRow, barOuter, midRow, divider, ipRow, quitButton])
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 10
        stack.edgeInsets  = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            barOuter.heightAnchor.constraint(equalToConstant: 8),
            barOuter.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            barInner.leadingAnchor.constraint(equalTo: barOuter.leadingAnchor),
            barInner.topAnchor.constraint(equalTo: barOuter.topAnchor),
            barInner.bottomAnchor.constraint(equalTo: barOuter.bottomAnchor),

            divider.heightAnchor.constraint(equalToConstant: 1),
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),

            quitButton.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            quitButton.heightAnchor.constraint(equalToConstant: 30),
        ])

        barWidthConstraint = barInner.widthAnchor.constraint(equalToConstant: 0)
        barWidthConstraint?.isActive = true
    }

    func update(stats s: MemoryStats) {
        usedLabel.stringValue  = s.usedGB >= 1
            ? String(format: "%.2f GB", s.usedGB)
            : String(format: "%.0f MB", s.usedMB)
        totalLabel.stringValue  = String(format: "/ %.0f GB total", s.totalGB)
        wiredLabel.stringValue  = String(format: "Wired: %.1f GB", Double(s.wired) / 1_073_741_824)

        let pct = s.pressure
        pressureLabel.stringValue = String(format: "%.0f%%", pct * 100)

        let barColor: NSColor
        switch pct {
        case ..<0.60: barColor = NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.45, alpha: 1)
        case ..<0.80: barColor = NSColor(calibratedRed: 1.00, green: 0.75, blue: 0.00, alpha: 1)
        default:      barColor = NSColor(calibratedRed: 1.00, green: 0.27, blue: 0.27, alpha: 1)
        }
        pressureLabel.textColor = barColor
        barInner.layer?.backgroundColor = barColor.cgColor

        let barContainerWidth = view.bounds.width - 40
        let targetWidth = max(8, barContainerWidth * CGFloat(pct))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.barWidthConstraint?.animator().constant = targetWidth
        }

        // Update Wi-Fi IP (off main queue to avoid blocking)
        DispatchQueue.global(qos: .utility).async {
            let ip = wifiIPAddress()
            DispatchQueue.main.async { self.ipLabel.stringValue = ip }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Helpers
// ─────────────────────────────────────────────────────────────────────────────

private func makeLabel(size: CGFloat, weight: NSFont.Weight, alpha: CGFloat = 1.0) -> NSTextField {
    let f = NSTextField(labelWithString: "")
    f.font      = .monospacedSystemFont(ofSize: size, weight: weight)
    f.textColor = NSColor(white: 1, alpha: alpha)
    f.alignment = .left
    return f
}

private func hstack(_ views: [NSView]) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .horizontal
    s.alignment   = .centerY
    s.spacing     = 6
    return s
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Entry point
// ─────────────────────────────────────────────────────────────────────────────

@main
struct MemBarApp {
    static func main() {
        let app      = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum Command: String {
    case snapshot
    case content
    case display
    case point
    case windows
}

guard CommandLine.arguments.count >= 2,
      let command = Command(rawValue: CommandLine.arguments[1]) else {
    fputs("usage: readme_menu_windows snapshot | content <pid> <display-id> <x> <y> <width> <height> <pixel-width> <pixel-height> <output-path> | display | point <x> <y> | windows <snapshot-file> <display-id> <pid>\n", stderr)
    exit(2)
}

func onlineDisplayIDs() -> [CGDirectDisplayID] {
    var displayCount: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success,
          displayCount > 0 else {
        return []
    }

    var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
    guard CGGetOnlineDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
        return []
    }
    return Array(displayIDs.prefix(Int(displayCount)))
}

func pixelDimensions(of displayID: CGDirectDisplayID) -> (width: Int, height: Int) {
    guard let displayMode = CGDisplayCopyDisplayMode(displayID) else {
        return (CGDisplayPixelsWide(displayID), CGDisplayPixelsHigh(displayID))
    }
    return (displayMode.pixelWidth, displayMode.pixelHeight)
}

func displayIDsWithMenuBar() -> Set<CGDirectDisplayID> {
    let displayIDs = NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
        guard screen.frame.maxY - screen.visibleFrame.maxY > 0.5,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber else {
            return nil
        }
        return number.uint32Value
    }
    return Set(displayIDs.isEmpty ? [CGMainDisplayID()] : displayIDs)
}

func printDisplayInfo(_ displayID: CGDirectDisplayID) {
    let bounds = CGDisplayBounds(displayID)
    let pixels = pixelDimensions(of: displayID)
    print(
        "\(displayID),\(Int(bounds.minX)),\(Int(bounds.minY)),"
            + "\(Int(bounds.width)),\(Int(bounds.height)),"
            + "\(pixels.width),\(pixels.height)"
    )
}

func captureContent() async throws {
    guard CommandLine.arguments.count == 11,
          let processID = pid_t(CommandLine.arguments[2]),
          let displayID = CGDirectDisplayID(CommandLine.arguments[3]),
          let x = Double(CommandLine.arguments[4]),
          let y = Double(CommandLine.arguments[5]),
          let width = Double(CommandLine.arguments[6]),
          let height = Double(CommandLine.arguments[7]),
          let pixelWidth = Int(CommandLine.arguments[8]),
          let pixelHeight = Int(CommandLine.arguments[9]) else {
        throw NSError(
            domain: "ReadmeMenuWindows",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Invalid content capture arguments."]
        )
    }

    let shareableContent = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
    )
    guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }),
          let application = shareableContent.applications.first(where: {
              $0.processID == processID
          }) else {
        throw NSError(
            domain: "ReadmeMenuWindows",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to find the selected display or TypeSwitch process."]
        )
    }

    let displayBounds = CGDisplayBounds(displayID)
    let filter = SCContentFilter(
        display: display,
        including: [application],
        exceptingWindows: []
    )
    let configuration = SCStreamConfiguration()
    configuration.sourceRect = CGRect(
        x: x - displayBounds.minX,
        y: y - displayBounds.minY,
        width: width,
        height: height
    )
    configuration.width = pixelWidth
    configuration.height = pixelHeight
    configuration.showsCursor = false

    let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: configuration
    )
    let representation = NSBitmapImageRep(cgImage: image)
    guard let pngData = representation.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "ReadmeMenuWindows",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to encode the captured menu content."]
        )
    }
    try pngData.write(to: URL(fileURLWithPath: CommandLine.arguments[10]))
}

switch command {
case .snapshot:
    guard let windowInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        fputs("Unable to read the macOS window list.\n", stderr)
        exit(1)
    }
    for info in windowInfo {
        if let windowNumber = info[kCGWindowNumber as String] as? NSNumber {
            print(windowNumber.uint32Value)
        }
    }

case .content:
    let application = NSApplication.shared
    Task {
        do {
            try await captureContent()
            exit(0)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    application.run()

case .display:
    let menuBarDisplayIDs = displayIDsWithMenuBar()
    guard let displayID = onlineDisplayIDs().filter(menuBarDisplayIDs.contains).max(by: { lhs, rhs in
        let lhsPixels = pixelDimensions(of: lhs)
        let rhsPixels = pixelDimensions(of: rhs)
        let lhsArea = UInt64(lhsPixels.width) * UInt64(lhsPixels.height)
        let rhsArea = UInt64(rhsPixels.width) * UInt64(rhsPixels.height)
        if lhsArea != rhsArea { return lhsArea < rhsArea }
        if lhsPixels.width != rhsPixels.width {
            return lhsPixels.width < rhsPixels.width
        }
        return lhs < rhs
    }) else {
        fputs("No online displays were found.\n", stderr)
        exit(1)
    }
    printDisplayInfo(displayID)

case .point:
    guard CommandLine.arguments.count == 4,
          let x = Double(CommandLine.arguments[2]),
          let y = Double(CommandLine.arguments[3]),
          let displayID = onlineDisplayIDs().first(where: {
              CGDisplayBounds($0).contains(CGPoint(x: x, y: y))
          }) else {
        fputs("point requires coordinates inside an online display.\n", stderr)
        exit(2)
    }
    printDisplayInfo(displayID)

case .windows:
    guard CommandLine.arguments.count == 5,
          let displayID = CGDirectDisplayID(CommandLine.arguments[3]),
          let processID = pid_t(CommandLine.arguments[4]) else {
        fputs("windows requires a snapshot file, display ID, and process ID.\n", stderr)
        exit(2)
    }
    guard let windowInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] else {
        fputs("Unable to read the macOS window list.\n", stderr)
        exit(1)
    }

    let snapshotURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let snapshotText = try String(contentsOf: snapshotURL, encoding: .utf8)
    let existingWindowIDs = Set(
        snapshotText.split(whereSeparator: \.isWhitespace).compactMap { UInt32($0) }
    )
    let displayBounds = CGDisplayBounds(displayID)
    let pixels = pixelDimensions(of: displayID)
    let scaleX = Double(pixels.width) / displayBounds.width
    let scaleY = Double(pixels.height) / displayBounds.height

    let windows = windowInfo.compactMap { info -> (id: UInt32, bounds: CGRect)? in
        guard let windowNumber = info[kCGWindowNumber as String] as? NSNumber,
              !existingWindowIDs.contains(windowNumber.uint32Value),
              let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
              ownerPID.int32Value == processID,
              let layer = info[kCGWindowLayer as String] as? NSNumber,
              layer.intValue > 0,
              let alpha = info[kCGWindowAlpha as String] as? NSNumber,
              alpha.doubleValue > 0,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
              displayBounds.contains(CGPoint(x: bounds.midX, y: bounds.midY)),
              bounds.width >= 100,
              bounds.height >= 40 else {
            return nil
        }
        return (windowNumber.uint32Value, bounds)
    }

    guard !windows.isEmpty else {
        fputs("No new menu windows were found after opening TypeSwitch.\n", stderr)
        exit(1)
    }

    for window in windows.reversed() {
        let pixelX = Int(((window.bounds.minX - displayBounds.minX) * scaleX).rounded())
        let pixelY = Int(((window.bounds.minY - displayBounds.minY) * scaleY).rounded())
        let pixelWidth = Int((window.bounds.width * scaleX).rounded())
        let pixelHeight = Int((window.bounds.height * scaleY).rounded())
        print(
            "\(window.id),\(pixelX),\(pixelY),\(pixelWidth),\(pixelHeight),"
                + "\(Int(window.bounds.minX)),\(Int(window.bounds.minY)),"
                + "\(Int(window.bounds.width)),\(Int(window.bounds.height))"
        )
    }
}

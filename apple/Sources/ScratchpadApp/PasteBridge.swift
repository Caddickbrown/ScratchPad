import SwiftUI
import UniformTypeIdentifiers
import ScratchpadCore

/// Reduces the platform pasteboard to ClipboardContents. The classifier in ScratchpadCore does the rest.
enum PasteBridge {
    static let readableTypes: [UTType] = [.fileURL, .image, .html, .utf8PlainText, .url]

    static func read() -> ClipboardContents {
        #if os(macOS)
        let pb = NSPasteboard.general
        var c = ClipboardContents()
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            c.fileURLs = urls
        }
        if let img = pb.readObjects(forClasses: [NSImage.self])?.first as? NSImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            c.imageData = png; c.imageExtension = "png"
        }
        c.html = pb.string(forType: .html)
        c.plain = pb.string(forType: .string)
        return c
        #else
        let pb = UIPasteboard.general
        var c = ClipboardContents()
        if let img = pb.image, let png = img.pngData() { c.imageData = png; c.imageExtension = "png" }
        if let data = pb.data(forPasteboardType: UTType.html.identifier) { c.html = String(data: data, encoding: .utf8) }
        c.plain = pb.string ?? pb.url?.absoluteString
        return c
        #endif
    }

    #if os(macOS)
    /// Item providers from onPasteCommand / onDrop. Loads each type once and calls back on the main actor.
    static func read(providers: [NSItemProvider], completion: @escaping @MainActor (ClipboardContents) -> Void) {
        var c = ClipboardContents()
        let group = DispatchGroup()
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { c.fileURLs.append(url) }
                    else if let url = item as? URL { c.fileURLs.append(url) }
                    group.leave()
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                group.enter()
                p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data, let img = NSImage(data: data), let tiff = img.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) { c.imageData = png }
                    group.leave()
                }
            } else {
                if p.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                    group.enter()
                    p.loadDataRepresentation(forTypeIdentifier: UTType.html.identifier) { data, _ in
                        c.html = data.flatMap { String(data: $0, encoding: .utf8) }; group.leave()
                    }
                }
                if p.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                    group.enter()
                    p.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, _ in
                        c.plain = data.flatMap { String(data: $0, encoding: .utf8) }; group.leave()
                    }
                }
            }
        }
        group.notify(queue: .main) { Task { @MainActor in completion(c) } }
    }
    #endif
}

import Foundation
import UniformTypeIdentifiers

public enum FileKind: CaseIterable, Sendable, Hashable {
    case video, audio, archive, diskImage, document, other

    /// Packages (`.rtfd`, `.photoslibrary`) are `.other`.
    public static func of(_ url: URL) -> FileKind {
        if (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { return .other }
        return of(extension: url.pathExtension)
    }

    public static func of(extension ext: String) -> FileKind {
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .diskImage) { return .diskImage }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .image) { return .other }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .content)
        {
            return .document
        }
        return .other
    }
}

extension FileKind {
    public var title: LocalizedStringResource {
        switch self {
        case .video: L("Video", "Video")
        case .audio: L("Audio", "Audio")
        case .archive: L("Archive", "Archive")
        case .diskImage: L("Disk image", "Disk image")
        case .document: L("Document", "Document")
        case .other: L("Other", "Other")
        }
    }

    public var symbol: String {
        switch self {
        case .video: "film"
        case .audio: "music.note"
        case .archive: "archivebox"
        case .diskImage: "opticaldisc"
        case .document: "doc.text"
        case .other: "doc"
        }
    }
}

import Darwin
import Foundation

public enum DiskUsage {
    /// Physical bytes on disk (`st_blocks * 512`) of the entry and everything below it, on the same volume.
    /// Symlinks count as themselves; unreadable entries are skipped; a missing path is 0.
    public static func allocatedSize(of url: URL) -> Int64 {
        guard let root = strdup(url.path) else { return 0 }
        defer { free(root) }
        var paths: [UnsafeMutablePointer<CChar>?] = [root, nil]
        guard let stream = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else { return 0 }
        defer { fts_close(stream) }

        var total: Int64 = 0
        while let entry = fts_read(stream) {
            switch Int32(entry.pointee.fts_info) {
            case FTS_D, FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                if let info = entry.pointee.fts_statp {
                    total += Int64(info.pointee.st_blocks) * 512
                }
            default:
                continue
            }
        }
        return total
    }
}

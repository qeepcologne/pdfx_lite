import Foundation
import CoreGraphics

enum RepositoryError: Error {
    case ItemNotFound
}

/// Documents are registered on the platform thread but read from the render queue (`renderPage` hands the heavy work
/// to a background queue and looks the document up there), so the map is genuinely shared across threads and is
/// guarded by a lock.
///
/// There is deliberately no page repository: pages are opened and dropped within a single call, never registered.
///
/// `@unchecked Sendable`, not `Sendable`: the stored values wrap a CoreGraphics handle (`CGPDFDocument`) that carries
/// no Sendable conformance. The lock below is the only thing making this safe, hence "unchecked".
class Repository<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: T] = [:]

    func get(id: String) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let item = items[id] else {
            throw RepositoryError.ItemNotFound
        }
        return item
    }

    func set(id: String, item: T) {
        lock.lock()
        defer { lock.unlock() }
        items[id] = item
    }

    func close(id: String) {
        lock.lock()
        defer { lock.unlock() }
        items.removeValue(forKey: id)
    }

    /// Drop everything. Used on engine detach, where no per-item `close` from Dart is ever going to arrive.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll()
    }
}

//Sendable is inherited from Repository; restating it here would be a redundant conformance.
final class DocumentRepository: Repository<Document> {
    func register(renderer: CGPDFDocument) -> Document {
        let id = UUID().uuidString
        let document = Document(id: id, renderer: renderer)
        set(id: id, item: document)
        return document
    }
}

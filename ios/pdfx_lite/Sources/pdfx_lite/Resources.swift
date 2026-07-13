import Foundation
import CoreGraphics

enum RepositoryError: Error {
    case ItemNotFound
}

/// Documents and pages are registered on the platform thread but read from the render queue (`renderPage` hands the
/// heavy work to a background queue and looks the page up there), so the map is genuinely shared across threads and
/// is guarded by a lock.
///
/// `@unchecked Sendable`, not `Sendable`: the stored values wrap CoreGraphics handles (`CGPDFDocument`/`CGPDFPage`)
/// that carry no Sendable conformance. The lock below is the only thing making this safe, hence "unchecked".
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

final class PageRepository: Repository<Page> {
    func register(documentId: String, renderer: CGPDFPage) -> Page {
        let id = UUID().uuidString
        let page = Page(id: id, documentId: documentId, renderer: renderer)
        set(id: id, item: page)
        return page
    }
}

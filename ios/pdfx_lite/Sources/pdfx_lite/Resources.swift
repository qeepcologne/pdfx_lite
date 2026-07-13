import Foundation
import CoreGraphics

enum RepositoryError: Error {
    case ItemNotFound
}

class Repository<T> {
    var items: [String: T] = [:]

    func get(id: String) throws -> T {
        guard let item = items[id] else {
            throw RepositoryError.ItemNotFound
        }
        return item
    }

    func set(id: String, item: T) {
        items[id] = item
    }

    func close(id: String) {
        items.removeValue(forKey: id)
    }
}

class DocumentRepository : Repository<Document> {
    func register(renderer: CGPDFDocument) -> Document {
        let id = UUID().uuidString
        let page = Document(id: id, renderer: renderer)
        set(id: id, item: page)
        return page
    }
}

class PageRepository : Repository<Page> {
    func register(documentId: String, renderer: CGPDFPage) -> Page {
        let id = UUID().uuidString
        let page = Page(id: id, documentId: documentId, renderer: renderer)
        set(id: id, item: page)
        return page
    }
}

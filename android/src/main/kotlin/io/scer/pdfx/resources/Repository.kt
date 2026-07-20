package io.scer.pdfx.resources

import java.util.concurrent.ConcurrentHashMap

class RepositoryItemNotFoundException(message: String) : Exception(message)

abstract class Repository<T> {
    /**
     * Concurrent because it genuinely is: `renderPage` reads it from a background coroutine while `register`,
     * `close` and `updateTexture` read and write it from the platform thread. A plain `HashMap` could miss an entry
     * or, mid-resize, corrupt a bucket.
     */
    private val items: MutableMap<String, T> = ConcurrentHashMap()

    @Throws(RepositoryItemNotFoundException::class)
    fun get(id: String): T = items[id] ?: throw RepositoryItemNotFoundException(id)

    fun set(id: String, item: T) {
        items[id] = item
    }

    /** Every item still held, so a subclass can release what it owns before the map is emptied. */
    protected fun drain(): List<T> {
        val all = items.values.toList()
        items.clear()
        return all
    }

    open fun clear() = items.clear()

    protected open fun close(id: String) {
        items.remove(id)
    }
}

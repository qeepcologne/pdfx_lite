package io.scer.pdfx.resources

class RepositoryItemNotFoundException(message: String) : Exception(message)

abstract class Repository<T> {
    private val items: MutableMap<String, T> = HashMap()

    @Throws(RepositoryItemNotFoundException::class)
    fun get(id: String): T = items[id] ?: throw RepositoryItemNotFoundException(id)

    fun set(id: String, item: T) {
        items[id] = item
    }

    fun clear() = items.clear()

    protected open fun close(id: String) {
        items.remove(id)
    }
}

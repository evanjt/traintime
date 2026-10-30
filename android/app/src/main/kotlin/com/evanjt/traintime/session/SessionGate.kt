package com.evanjt.traintime.session

// Orders a tracking session's outputs against its teardown. The service posts
// notifications and registers location updates from background coroutines,
// while its teardown runs on the main thread. A post that loses that race
// re-creates the card after the system removed it, as a plain ongoing
// notification with no service behind it. Every output goes through open(),
// teardown through close(), and the shared lock means no output can land
// after close() returns.
class SessionGate {
    private var closed = false

    val isClosed: Boolean get() = synchronized(this) { closed }

    // Runs the output only while the session is live; null once closed.
    fun <T> open(output: () -> T): T? = synchronized(this) {
        if (closed) null else output()
    }

    // Always runs the teardown, so a repeat close still clears a card that
    // something else left behind.
    fun close(teardown: () -> Unit) = synchronized(this) {
        closed = true
        teardown()
    }
}

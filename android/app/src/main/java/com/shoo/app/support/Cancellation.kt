package com.shoo.app.support

import kotlinx.coroutines.CancellationException

/** A coroutine that was cancelled (screen gone, refresh replaced): not a failure to show. */
val Throwable.isCancellation: Boolean
    get() = this is CancellationException

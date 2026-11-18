package com.shoo.app

import java.io.File

/** contracts/fixtures, read straight from the repo (unit tests run in android/app), like the APK's assets/fixtures. */
object TestFixtures {
    val directory = File("../../contracts/fixtures")

    fun read(name: String): String? = File(directory, "$name.json").takeIf { it.exists() }?.readText()

    /** The loader `MockRepository` takes. */
    val loader: (String) -> String? = { read(it) }
}

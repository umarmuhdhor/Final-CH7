package com.shoo.app.data

import com.shoo.app.support.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * A JSON array decoded one element at a time (issue #493 part 1). An element that does not decode (a wrong type,
 * a missing field, a value or nested object this build does not know, `null`) is left out and the rest are kept,
 * so one row from a newer server can't make a whole list fail to load.
 *
 * Only the elements are forgiven: a value that is not an array still throws (the caller's `array(key)`), so a
 * response that breaks the contract is still `RepositoryError.Decoding`.
 */
data class LossyList<T>(
    val elements: List<T>,
    /** How many elements were left out. */
    val dropped: Int,
    /** Where the first left-out element failed, as contract field names only (logged; never a row value). */
    val firstProblem: String?,
) {
    companion object {
        /** `list` names the array in the log (`items`, `members`). */
        fun <T> decode(array: JSONArray, list: String, decodeElement: (JSONObject) -> T): LossyList<T> {
            val elements = ArrayList<T>(array.length())
            var dropped = 0
            var firstProblem: String? = null
            for (index in 0 until array.length()) {
                val element = array.opt(index)
                try {
                    if (element !is JSONObject) throw DecodingException("(row)")
                    elements.add(decodeElement(element))
                } catch (error: Exception) {
                    dropped += 1
                    if (firstProblem == null) firstProblem = (error as? DecodingException)?.message ?: "?"
                }
            }
            if (dropped > 0) {
                // Field names from the contract and counts only: never a value from the row (P6).
                Log.data.error(
                    "List rows did not match the contract and were left out",
                    "$list: $dropped of ${dropped + elements.size}, first at ${firstProblem ?: "?"}",
                )
            }
            return LossyList(elements, dropped, firstProblem)
        }
    }
}

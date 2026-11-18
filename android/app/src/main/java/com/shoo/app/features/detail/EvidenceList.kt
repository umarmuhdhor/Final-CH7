package com.shoo.app.features.detail

import androidx.compose.ui.geometry.Rect
import com.shoo.app.data.Signal
import com.shoo.app.data.UserMode
import com.shoo.app.support.AppLanguage
import com.shoo.app.support.Formatters
import com.shoo.app.support.L10n

/**
 * One reason on the Detail screen (DT-04): "Domain age 3 days", +30 %, the kind of signal and, when the page copy
 * marked it, where it sits on the page.
 */
data class Evidence(
    val id: String,
    /** Position in the list, heaviest first (`detail.evidence.N`). */
    val index: Int,
    val signalId: String,
    val text: String,
    val weight: Int,
    /** This reason's weight and every heavier one before it, for the stacked contribution bar. */
    val runningWeights: List<Int>,
    /** Areas on the page for this signal (`marks` in the page copy's meta), in page CSS px. */
    val highlights: List<Rect> = emptyList(),
    /** The signal's `host` (#497): which parts of the address to mark and the brand's real address. */
    val host: Signal.Host? = null,
) {
    val kind: SignalKind get() = SignalKind.from(signalId)

    /** "+30%". */
    fun weightText(language: AppLanguage): String = "+" + Formatters.percent(weight, language)

    /** TalkBack: "Domain age 3 days, adds 30 percent to the risk score". */
    fun spokenLine(language: AppLanguage): String =
        L10n.string("%@, adds %lld percent to the risk score", language, text, weight)

    companion object {
        /**
         * The heaviest `limit` signals; equal weights keep the contract's order.
         * Guardian reads `label`, Protected reads the simpler `labelSimple`.
         */
        fun top(
            signals: List<Signal>,
            mode: UserMode,
            language: AppLanguage,
            marks: List<ReplicaMark> = emptyList(),
            limit: Int = 3,
        ): List<Evidence> {
            // Stable sort: equal weights keep their order.
            val picked = signals.withIndex().sortedByDescending { it.value.weight }.take(limit)
            val running = ArrayList<Int>()
            return picked.mapIndexed { position, entry ->
                val signal = entry.value
                running.add(signal.weight)
                val text = if (mode == UserMode.GUARDIAN) signal.label else signal.labelSimple
                Evidence(
                    id = "${entry.index}-${signal.id}",
                    index = position,
                    signalId = signal.id,
                    text = text.text(language.code),
                    weight = signal.weight,
                    runningWeights = running.toList(),
                    highlights = marks.filter { it.signalId == signal.id }.map { it.rect },
                    host = signal.host,
                )
            }
        }
    }
}

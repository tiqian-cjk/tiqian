package org.tiqian.layout

import org.tiqian.core.TextRange
import org.tiqian.core.LineEndReason
import org.tiqian.linebreak.BreakKind

data class BreakCandidate(
    val index: Int,
    val kind: BreakKind,
    val naturalWidth: Float,
    val compressedWidth: Float,
    val expandedWidth: Float,
    val forbiddenReason: String? = null,
    val repairOptions: List<RepairOption> = emptyList(),
)

sealed interface RepairOption {
    val penalty: Int
    val reason: String

    data class PushIn(
        override val penalty: Int,
        override val reason: String,
        val offenderClusterIndex: Int,
        /**
         * CLREQ 推入 semantics — compress in-line glue to make the offender
         * fit on the previous line. The shrink is distributed across every
         * cluster in the merged line whose punctuation atoms still have
         * compressible trailing glue (after spacing-compression and edge-trim
         * have run). Listed in cluster order.
         */
        val allocations: List<PushInAllocation>,
        val totalShrink: Float,
        val totalAvailableCapacity: Float,
    ) : RepairOption

    data class Hang(
        override val penalty: Int,
        override val reason: String,
        val offenderClusterIndex: Int,
    ) : RepairOption

    data class CarryPrevious(
        override val penalty: Int,
        override val reason: String,
        val offenderClusterIndex: Int,
        val carriedClusterIndex: Int,
    ) : RepairOption

    /**
     * CLREQ 行尾禁则: a forbidden-at-line-end mark (开引号/开括号; GB·严格
     * 追加分隔号) at the line's end is moved to the NEXT line's start. The
     * break retreats past it — only the current line shortens, so no
     * overflow cascade. [movedClusterIndex] is the mark moved down.
     */
    data class CarryNext(
        override val penalty: Int,
        override val reason: String,
        val movedClusterIndex: Int,
    ) : RepairOption

    data class LeaveRagged(
        override val penalty: Int,
        override val reason: String,
        val offenderClusterIndex: Int,
    ) : RepairOption
}

data class PushInAllocation(
    val clusterIndex: Int,
    val shrink: Float,
    val availableCapacity: Float,
    /** Which resource the shrink consumes (ADR 0020). */
    val channel: ShrinkChannel = ShrinkChannel.TrailingGlue,
)

data class LineCandidate(
    val clusterRange: IntRange,
    val sourceRange: TextRange,
    val naturalWidth: Float,
    val adjustedWidth: Float,
    val endReason: LineEndReason = LineEndReason.AutoWrap,
    val repair: RepairOption? = null,
    val repairCandidates: List<RepairCandidate> = emptyList(),
    /**
     * `LineEndHangingPunctuation`: when set, this cluster (the line's last)
     * hangs past the measure — it is excluded from the line's measure-fill
     * width so justification fills the content to `maxWidth` and the mark
     * sits beyond (突出版心). Null on non-hanging lines.
     */
    val hangingClusterIndex: Int? = null,
)

data class RepairCandidate(
    val kind: String,
    val reasonCode: String,
    val offenderClusterIndex: Int,
    val penalty: Int,
    val accepted: Boolean,
    val rejectionReason: String? = null,
    val targetClusterIndex: Int? = null,
    val carriedClusterIndex: Int? = null,
    val shrink: Float = 0f,
    val requiredShrink: Float = 0f,
    val availableCapacity: Float = 0f,
)

data class LineSolution(
    val lines: List<LineCandidate>,
    val totalBadness: Float = 0f,
)

enum class LineOptimizationStrategy {
    Greedy,
    Lookahead,
    ParagraphDynamicProgramming,
}

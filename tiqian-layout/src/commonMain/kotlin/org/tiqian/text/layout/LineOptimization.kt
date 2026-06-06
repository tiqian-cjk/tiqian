package org.tiqian.text.layout

import org.tiqian.text.core.TextRange
import org.tiqian.text.linebreak.BreakKind

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
        val targetClusterIndex: Int,
        val shrink: Float,
    ) : RepairOption

    data class Hang(
        override val penalty: Int,
        override val reason: String,
    ) : RepairOption

    data class CarryPrevious(
        override val penalty: Int,
        override val reason: String,
    ) : RepairOption

    data class LeaveRagged(
        override val penalty: Int,
        override val reason: String,
    ) : RepairOption
}

data class LineCandidate(
    val clusterRange: IntRange,
    val sourceRange: TextRange,
    val naturalWidth: Float,
    val adjustedWidth: Float,
    val repair: RepairOption? = null,
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

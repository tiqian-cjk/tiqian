package org.tiqian.text.core

data class TextRange(
    val start: Int,
    val end: Int,
) {
    init {
        require(start <= end) { "TextRange start must not be greater than end." }
        require(start >= 0) { "TextRange start must be non-negative." }
    }

    val length: Int get() = end - start
    val isEmpty: Boolean get() = length == 0
}

data class Size(
    val width: Float,
    val height: Float,
)

data class Rect(
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
}

data class LayoutConstraints(
    val maxWidth: Float,
    val maxHeight: Float = Float.POSITIVE_INFINITY,
) {
    init {
        require(maxWidth > 0f) { "maxWidth must be positive." }
        require(maxHeight > 0f) { "maxHeight must be positive." }
    }
}


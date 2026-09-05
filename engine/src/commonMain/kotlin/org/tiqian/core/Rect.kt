package org.tiqian.core

data class Rect(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    val width: Float get() = get_width()
    val height: Float get() = get_height()

    fun get_width(): Float {
        return this.right - this.left
    }

    fun get_height(): Float {
        return this.bottom - this.top
    }

    override fun toString(): String {
        return "Rect(left=" + this.left + ", top=" + this.top + ", right=" + this.right + ", bottom=" + this.bottom + ")"
    }
}

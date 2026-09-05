package org.tiqian.core

data class TextRange(val start: Int, val end: Int) {
    init {
        if ((start > end)) {
            throw TiqianIllegalArgumentException.StartGreaterThanEnd
        }
        if ((start < 0)) {
            throw TiqianIllegalArgumentException.NegativeStart
        }
    }
    val length: Int get() = get_length()
    val isEmpty: Boolean get() = get_isEmpty()

    fun get_length(): Int {
        return this.end - this.start
    }

    fun get_isEmpty(): Boolean {
        return this.get_length() == 0
    }

    override fun toString(): String {
        return "TextRange(start=" + this.start + ", end=" + this.end + ")"
    }
}

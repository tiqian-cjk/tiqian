package org.tiqian.core

data class Size(val width: Float, val height: Float) {

    override fun toString(): String {
        return "Size(width=" + this.width + ", height=" + this.height + ")"
    }
}

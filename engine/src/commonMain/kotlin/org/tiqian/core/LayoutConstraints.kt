package org.tiqian.core

class LayoutConstraints(val maxWidth: Float, val maxHeight: Float = Float.POSITIVE_INFINITY, val maxLines: Int = 2147483647) {
    init {
        if ((!(this.maxWidth > 0.0f))) {
            throw TiqianIllegalArgumentException.Message("maxWidth must be positive.")
        }
        if ((!(this.maxHeight > 0.0f))) {
            throw TiqianIllegalArgumentException.Message("maxHeight must be positive.")
        }
        if ((this.maxLines <= 0)) {
            throw TiqianIllegalArgumentException.Message("maxLines must be positive.")
        }
    }

    override fun toString(): String {
        return "LayoutConstraints(maxWidth=" + this.maxWidth + ", maxHeight=" + this.maxHeight + ", maxLines=" + this.maxLines + ")"
    }
}

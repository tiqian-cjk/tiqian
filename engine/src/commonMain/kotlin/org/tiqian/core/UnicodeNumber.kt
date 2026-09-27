package org.tiqian.core

internal object UnicodeNumber {
    fun contains(codePoint: Int): Boolean {
        if ((codePoint < 0 || codePoint > 1114111)) {
            throw TiqianIllegalArgumentException.Message("Not a Unicode scalar value: " + codePoint)
        }
        if ((codePoint >= 55296 && codePoint <= 57343)) {
            throw TiqianIllegalArgumentException.Message("Surrogate is not a Unicode scalar value: " + codePoint)
        }
        return UnicodeNumberData.contains(codePoint)
    }
}

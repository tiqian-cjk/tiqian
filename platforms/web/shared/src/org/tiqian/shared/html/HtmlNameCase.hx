package org.tiqian.shared.html;

/**
 * The ASCII-only name folding the HTML query lane compares with. Rust folds
 * tag and attribute names through eq_ignore_ascii_case (A-Z only);
 * String.toLowerCase would also fold non-ASCII letters and change those
 * comparisons.
 */
class HtmlNameCase {
    public static function asciiLower(value:String):String {
        final buffer = new StringBuf();
        var index = 0;
        while (index < value.length) {
            final code:Int = value.charCodeAt(index);
            if (code >= 0x41 && code <= 0x5A) {
                buffer.add(String.fromCharCode(code + 0x20));
            } else {
                buffer.add(String.fromCharCode(code));
            }
            index += 1;
        }
        return buffer.toString();
    }
}

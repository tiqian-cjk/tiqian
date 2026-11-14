package org.tiqian.shared;

/**
 * The value-style class generation rules, single-sourced so the snapshot
 * namespace (tqv-N) and the runtime namespace (tqvr-N) mint the same class
 * name on every platform. The snapshot class pins an interned declaration
 * index in base 36 (matching the Rust engine's to_string_36 in
 * snapshot_bundle.rs); the runtime class pins the double-FNV-1a key the
 * hand-written TypeScript lane computed in prepared-dom.ts before the
 * cutover (Stage2-shared). Both lanes must stay byte-equal: the criterion
 * is the same declaration mapping to the same class name on the browser
 * (snapshot) and the Node precompute (runtime), item by item.
 */
class SnapshotValueStyle {
    /**
     * The value-style DOM integration names, single-sourced for the
     * hand-written TypeScript lane (prepared-dom.ts) and its Stage2-shared
     * sibling. VALUE_STYLE_SCOPE_ATTRIBUTE marks the root scope; the element
     * attribute marks the injected <style> element; SNAPSHOT_STYLE_OWNER is
     * the owner sentinel that never collides with a host Element. Haxe has no
     * string-literal type, so each field widens to a plain string; the
     * consumer's StyleOwner type therefore resolves to Element | string.
     */
    public static final VALUE_STYLE_SCOPE_ATTRIBUTE:String = "data-tq-value-style-scope";
    public static final VALUE_STYLE_ELEMENT_ATTRIBUTE:String = "data-tq-prepared-value-styles";
    public static final SNAPSHOT_STYLE_OWNER:String = "tiqian-snapshot-style-owner";

    /** tqv-<index in base 36>: the snapshot value-style class for an interned index. */
    public static function snapshotValueStyleClass(index:Int):String {
        return "tqv-" + toBase36Unsigned(index);
    }

    /** tqvr-<key>: the runtime value-style class for a double-FNV-1a key. */
    public static function runtimeValueStyleClass(key:String):String {
        return "tqvr-" + key;
    }

    /**
     * RuntimeValueStyleContentAddressing: runtime lowering mints the same
     * class name for the same declaration in every session, so a fresh
     * one-shot enhance over a root reproduces the coordinated DOM byte for
     * byte even though the coordinated registry still holds declarations
     * from earlier widths. The snapshot namespace (tqv-) stays index based
     * because frozen snapshot tables persist those indexes across builds.
     *
     * The runtime value-style key for one declaration: double-FNV-1a over
     * UTF-16 code units, base-36-concatenating the two seeds without a
     * separator. The constants and the fold match the hand-written
     * prepared-dom.ts runtimeValueStyleKey exactly (a ^= code then imul by
     * 0x01000193; b ^= code+i then imul by 0x811c9dc5; both >>> 0).
     */
    public static function runtimeValueStyleKey(declaration:String):String {
        var a:Int = 0x811c9dc5;
        var b:Int = 0x01000193;
        final len = declaration.length;
        for (i in 0...len) {
            final code:Int = declaration.charCodeAt(i);
            a = mulMod32(a ^ code, 0x01000193);
            b = mulMod32(b ^ (code + i), 0x811c9dc5);
        }
        return toBase36Unsigned(a) + toBase36Unsigned(b);
    }

    /**
     * The low 32 bits of a signed Int rendered as unsigned base 36, matching
     * JavaScript's Number.prototype.toString(36) on the same bit pattern and
     * the Rust engine's to_string_36 reverse-collect algorithm.
     */
    public static function toBase36Unsigned(value:Int):String {
        final digits = "0123456789abcdefghijklmnopqrstuvwxyz";
        var n:Float = value < 0 ? value + 4294967296.0 : value;
        var out = "";
        while (true) {
            final digit:Int = Std.int(n % 36);
            out = digits.charAt(digit) + out;
            n = Math.floor(n / 36);
            if (n == 0) {
                break;
            }
        }
        return out;
    }

    /**
     * The low 32 bits of value * prime, computed through 16-bit limbs so no
     * intermediate crosses 2^31 (JavaScript numbers and the TypeScript
     * emitter stay exact, and the result is byte-equal to Math.imul). See
     * the commit message for the limb algebra.
     */
    static function mulMod32(value:Int, prime:Int):Int {
        final vh = (value >>> 16) & 0xFFFF;
        final vl = value & 0xFFFF;
        final ph = (prime >>> 16) & 0xFFFF;
        final pl = prime & 0xFFFF;
        final d = mul16Full(vl, pl);
        final dLow = d & 0xFFFF;
        final dHigh = (d >>> 16) & 0xFFFF;
        final xLow = mul16Full(vl, ph) & 0xFFFF;
        final yLow = mul16Full(vh, pl) & 0xFFFF;
        final crossLow = (xLow + yLow + dHigh) & 0xFFFF;
        return (crossLow << 16) | dLow;
    }

    /**
     * The full 32-bit product of two 16-bit values through 8-bit limbs, so
     * the multiply never leaves 2^31. Returns the product bit pattern as a
     * (possibly negative) Int.
     */
    static function mul16Full(a:Int, b:Int):Int {
        final ah = a >> 8;
        final al = a & 0xFF;
        final bh = b >> 8;
        final bl = b & 0xFF;
        final t0 = al * bl;
        final t1 = ah * bl + al * bh;
        final t2 = ah * bh;
        final lowAccum = (t1 << 8) + t0;
        final low16 = lowAccum & 0xFFFF;
        final carry = (lowAccum >>> 16) & 0xFFFF;
        final high16 = (t2 + carry) & 0xFFFF;
        return (high16 << 16) | low16;
    }
}

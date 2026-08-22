//! JS value semantics shared by the `precompute-fonts.js` port: Number →
//! String formatting, `String.prototype.trim`, and the UTF-16 code-unit
//! ordering of `Array.prototype.sort` (ADR 0050 parity oracle).

/// Kotlin `toFloat()`: rounds a binary64 number to the nearest binary32
/// value, ties to even. The engine geometry types are Kotlin `Float`
/// (binary32) while the request JSON carries binary64 numbers; this is the
/// single narrowing point that matches `toFloat()`. std offers no
/// conversion primitive in this direction, and the decimal round trip can
/// double-round the other way at f32 tie points, so the bits are rounded
/// here.
pub fn kotlin_to_float(value: f64) -> f32 {
    let bits = value.to_bits();
    let sign = (bits >> 63) << 31;
    let exponent = (bits >> 52) & 0x7ff;
    let fraction = bits & 0x000f_ffff_ffff_ffff;
    let f32_bits = if exponent == 0x7ff {
        // Infinity passes through; NaN keeps quietness and drops the payload.
        sign | (0xff << 23) | (u64::from(fraction != 0) << 22)
    } else if exponent == 0 {
        // Every f64 subnormal lies below half of the f32 minimum subnormal
        // (2^-1022 against 2^-150), so subnormals and zero round to zero.
        sign
    } else {
        // Normal f64: 2^(exponent - 1023) * (1 + fraction / 2^52). The f32
        // mantissa keeps 24 of these 53 bits; the bias difference is 896.
        let mantissa = (1 << 52) | fraction;
        if exponent > 896 {
            normal_f32_bits(sign, exponent - 896, mantissa)
        } else {
            subnormal_f32_bits(sign, exponent, mantissa)
        }
    };
    // The assembled word never exceeds the f32 bit width; the arm is dead.
    match u32::try_from(f32_bits) {
        Ok(narrow) => f32::from_bits(narrow),
        Err(_) => 0.0,
    }
}

// Rounds the 53-bit f64 mantissa to 24 bits, ties to even, and places it
// under the given f32 biased exponent.
fn normal_f32_bits(sign: u64, biased: u64, mantissa: u64) -> u64 {
    let dropped = mantissa & ((1 << 29) - 1);
    let kept = mantissa >> 29;
    let half = 1u64 << 28;
    let mut rounded = kept + u64::from(dropped > half || (dropped == half && (kept & 1) == 1));
    let mut biased = biased;
    if rounded == 1 << 24 {
        // Rounding carried into a new binary digit.
        rounded = 1 << 23;
        biased += 1;
    }
    if biased >= 255 {
        // Round-to-nearest sends overflow to infinity.
        return sign | (0xffu64 << 23);
    }
    sign | (biased << 23) | (rounded & ((1 << 23) - 1))
}

// Rounds mantissa * 2^(exponent - 1075) onto the f32 subnormal grid 2^-149;
// exponent <= 896, so the result is below 2^-126.
fn subnormal_f32_bits(sign: u64, exponent: u64, mantissa: u64) -> u64 {
    // Target: m * 2^-149 from mantissa * 2^(exponent - 926).
    let shift = 926 - exponent;
    if shift >= 64 {
        // mantissa < 2^53 lies below the halfway point; rounds to zero.
        return sign;
    }
    let dropped = mantissa & ((1 << shift) - 1);
    let kept = mantissa >> shift;
    let half = 1u64 << (shift - 1);
    let rounded = kept + u64::from(dropped > half || (dropped == half && (kept & 1) == 1));
    // At most 2^23: rounding up to exactly 2^-126 lands on the smallest
    // normal, whose bit pattern the same expression produces.
    sign | rounded
}

/// JavaScript ToNumber on an integer: rounds to the nearest f64, ties to
/// even. Hex, octal, and binary literals parse as i64 first; this is the
/// i64 to f64 step, and integer counters or cursors that JavaScript holds
/// as Numbers take it too. Both 32-bit halves convert losslessly and the
/// single addition performs the rounding. The byte split below keeps each
/// half a u32 without a narrowing conversion.
pub fn js_int_to_number(value: i64) -> f64 {
    let magnitude = value.unsigned_abs();
    let bytes = magnitude.to_le_bytes();
    let high =
        f64::from(u32::from_le_bytes([bytes[4], bytes[5], bytes[6], bytes[7]])) * 4_294_967_296.0;
    let low = f64::from(u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]));
    let magnitude = high + low;
    if value < 0 {
        -magnitude
    } else {
        magnitude
    }
}

/// Truncates toward zero and saturates: NaN to 0, values past the target
/// range to its bounds, infinity to the bounds. These are the semantics of
/// Rust's float-to-int casts, which the ported code used when reading JS
/// numbers into protocol integers. std has no checked float-to-int
/// conversion; `TryFrom` covers integer pairs only. After the range checks
/// below the value travels through its decimal form; the parse arm is dead
/// and returns zero.
pub fn trunc_sat_i64(value: f64) -> i64 {
    let integral = value.trunc();
    if integral.is_nan() {
        return 0;
    }
    if integral >= 9_223_372_036_854_775_808.0 {
        return i64::MAX;
    }
    if integral <= -9_223_372_036_854_775_808.0 {
        return i64::MIN;
    }
    format!("{integral:.0}").parse().unwrap_or(0)
}

/// `trunc_sat_i64` narrowed to the i32 range. The clamp runs first, so the
/// conversion cannot fail and the fallback bound stays unreachable.
pub fn trunc_sat_i32(value: f64) -> i32 {
    let wide = trunc_sat_i64(value);
    let clamped = wide.clamp(i64::from(i32::MIN), i64::from(i32::MAX));
    i32::try_from(clamped).unwrap_or(i32::MAX)
}

/// `trunc_sat_i64` narrowed to the u32 range; negative values truncate or
/// saturate to zero.
pub fn trunc_sat_u32(value: f64) -> u32 {
    if value.is_nan() {
        return 0;
    }
    if value <= -1.0 {
        return 0;
    }
    if value >= 4_294_967_296.0 {
        return u32::MAX;
    }
    u32::try_from(trunc_sat_i64(value)).unwrap_or(u32::MAX)
}

/// `trunc_sat_i64` narrowed to the usize range. Values from 2^63 upward
/// cannot index memory, so they collapse to `usize::MAX`; a 32-bit target
/// saturates the same way.
pub fn trunc_sat_usize(value: f64) -> usize {
    if value.is_nan() {
        return 0;
    }
    if value <= -1.0 {
        return 0;
    }
    if value >= 9_223_372_036_854_775_808.0 {
        return usize::MAX;
    }
    usize::try_from(trunc_sat_i64(value)).unwrap_or(usize::MAX)
}

/// Rounds half away from zero, then saturates into i32; the form the
/// shaping port used for `f32.round() as i32`.
pub fn round_sat_i32(value: f32) -> i32 {
    let integral = f64::from(value.round());
    let clamped = trunc_sat_i64(integral).clamp(i64::from(i32::MIN), i64::from(i32::MAX));
    i32::try_from(clamped).unwrap_or(i32::MAX)
}

/// Formats an f64 the way JavaScript `String(number)` does: shortest
/// round-trip digits, integer form below 1e21, exponential form with a
/// signed exponent at 1e21 and below 1e-6.
pub fn js_number_string(value: f64) -> String {
    if value.is_nan() {
        return "NaN".to_string();
    }
    if value.is_infinite() {
        return if value > 0.0 { "Infinity" } else { "-Infinity" }.to_string();
    }
    if value == 0.0 {
        return "0".to_string(); // covers -0: String(-0) === "0"
    }
    let magnitude = value.abs();
    if value.fract() == 0.0 && magnitude < 1e21 {
        // Display never uses the exponential form and prints integral
        // values as plain digits, which is the JS integer form here.
        return format!("{value}");
    }
    if (1e-6..1e21).contains(&magnitude) {
        return format!("{value}");
    }
    // Exponential range. Rust's {:e} is shortest round-trip but omits the
    // '+' on positive exponents; JavaScript always writes the sign.
    let rust_form = format!("{value:e}");
    match rust_form.split_once('e') {
        Some((mantissa, exponent)) if !exponent.starts_with('-') => {
            format!("{mantissa}e+{exponent}")
        }
        _ => rust_form,
    }
}

/// `String.prototype.trim`: strips Unicode White_Space plus U+FEFF from both
/// ends. Rust's `str::trim` covers White_Space but not U+FEFF.
pub fn js_trim(value: &str) -> &str {
    value.trim_matches(|c: char| c.is_whitespace() || c == '\u{feff}')
}

/// ECMAScript `\s`: WhiteSpace plus LineTerminator, including U+FEFF.
pub fn is_js_whitespace(character: char) -> bool {
    matches!(
        character,
        '\u{9}'
            | '\u{a}'
            | '\u{b}'
            | '\u{c}'
            | '\u{d}'
            | '\u{20}'
            | '\u{a0}'
            | '\u{1680}'
            | '\u{2000}'
            ..='\u{200a}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202f}'
                | '\u{205f}'
                | '\u{3000}'
                | '\u{feff}'
    )
}

/// Splits on ECMAScript `\s+` the way `String.prototype.split(/\s+/u)` does.
pub fn split_js_whitespace(value: &str) -> Vec<&str> {
    let mut parts = Vec::new();
    let mut start = None;
    let mut index = 0;
    for character in value.chars() {
        if is_js_whitespace(character) {
            if let Some(begin) = start.take() {
                parts.push(&value[begin..index]);
            }
        } else if start.is_none() {
            start = Some(index);
        }
        index += character.len_utf8();
    }
    if let Some(begin) = start {
        parts.push(&value[begin..]);
    }
    parts
}

/// `Math.min`: NaN propagates (Rust's `f64::min` drops it); `-0` wins over
/// `+0` (Rust's may return either).
pub fn js_min(left: f64, right: f64) -> f64 {
    if left.is_nan() || right.is_nan() {
        return f64::NAN;
    }
    if left == right {
        return if left.is_sign_negative() || right.is_sign_negative() {
            -0.0
        } else {
            left
        };
    }
    if left < right {
        left
    } else {
        right
    }
}

/// `Math.max`: NaN propagates; `+0` wins over `-0`.
pub fn js_max(left: f64, right: f64) -> f64 {
    if left.is_nan() || right.is_nan() {
        return f64::NAN;
    }
    if left == right {
        return if left.is_sign_negative() && right.is_sign_negative() {
            left
        } else {
            left.abs()
        };
    }
    if left > right {
        left
    } else {
        right
    }
}

/// Orders strings by UTF-16 code units, the comparison `Array.prototype.sort`
/// uses on strings. It differs from Unicode scalar ordering when a
/// supplementary character (surrogate pair, D800–DFFF) meets a BMP character
/// at or above U+E000.
pub fn cmp_utf16(left: &str, right: &str) -> std::cmp::Ordering {
    left.encode_utf16().cmp(right.encode_utf16())
}

/// Converts a string the way `Number(value)` does: trimmed input, empty to 0,
/// `Infinity`/`NaN` tokens, `0x`/`0o`/`0b` literals, decimal with optional
/// exponent, anything else to NaN.
pub fn js_to_number(value: &str) -> f64 {
    let text = js_trim(value);
    if text.is_empty() {
        return 0.0;
    }
    let (sign, body) = match text.strip_prefix('-') {
        Some(rest) => (-1.0, rest),
        None => (1.0, text.strip_prefix('+').unwrap_or(text)),
    };
    if body == "Infinity" {
        return sign * f64::INFINITY;
    }
    if body == "NaN" {
        return f64::NAN;
    }
    if let Some(digits) = body.strip_prefix("0x").or_else(|| body.strip_prefix("0X")) {
        return match i64::from_str_radix(digits, 16) {
            Ok(value) => sign * js_int_to_number(value),
            Err(_) => f64::NAN,
        };
    }
    if let Some(digits) = body.strip_prefix("0o").or_else(|| body.strip_prefix("0O")) {
        return match i64::from_str_radix(digits, 8) {
            Ok(value) => sign * js_int_to_number(value),
            Err(_) => f64::NAN,
        };
    }
    if let Some(digits) = body.strip_prefix("0b").or_else(|| body.strip_prefix("0B")) {
        return match i64::from_str_radix(digits, 2) {
            Ok(value) => sign * js_int_to_number(value),
            Err(_) => f64::NAN,
        };
    }
    // Decimal: digits [. digits] [e sign digits]; a bare "." or "e" is NaN.
    let invalid = body.strip_prefix(['e', 'E']).is_some()
        || body.starts_with(|c: char| !c.is_ascii_digit() && c != '.');
    if invalid {
        return f64::NAN;
    }
    let mut mantissa = String::new();
    let mut rest = body;
    let mut seen_digit = false;
    for c in rest.chars() {
        if c.is_ascii_digit() {
            mantissa.push(c);
            seen_digit = true;
        } else {
            break;
        }
    }
    rest = &rest[mantissa.len()..];
    if let Some(after_dot) = rest.strip_prefix('.') {
        let mut fraction = String::new();
        for c in after_dot.chars() {
            if c.is_ascii_digit() {
                fraction.push(c);
                seen_digit = true;
            } else {
                break;
            }
        }
        mantissa.push('.');
        mantissa.push_str(&fraction);
        rest = &after_dot[fraction.len()..];
    }
    if !seen_digit {
        return f64::NAN;
    }
    let mut number_text = mantissa;
    if let Some(exponent) = rest.strip_prefix(['e', 'E']) {
        let exponent_text = exponent
            .strip_prefix('+')
            .or_else(|| exponent.strip_prefix('-'))
            .unwrap_or(exponent);
        if exponent_text.is_empty() || !exponent_text.bytes().all(|b| b.is_ascii_digit()) {
            return f64::NAN;
        }
        number_text.push('e');
        number_text.push_str(exponent);
    } else if !rest.is_empty() {
        return f64::NAN;
    }
    sign * number_text.parse::<f64>().unwrap_or(f64::NAN)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cmp::Ordering;

    #[test]
    fn kotlin_to_float_round_trips_every_f32_shape() {
        // Widening to f64 is exact, so narrowing must return the same bits.
        for exponent in 0..=254u32 {
            for fraction in [0u32, 1, (1 << 22) - 1, 1 << 22, (1 << 23) - 1] {
                for sign in [0u32, 1] {
                    let bits = (sign << 31) | (exponent << 23) | fraction;
                    let value = f32::from_bits(bits);
                    assert_eq!(kotlin_to_float(f64::from(value)), value, "bits {bits:08x}");
                }
            }
        }
    }

    #[test]
    fn kotlin_to_float_rounds_ties_to_even() {
        assert_eq!(kotlin_to_float(16_777_217.0), 16_777_216.0f32);
        assert_eq!(kotlin_to_float(16_777_219.0), 16_777_220.0f32);
        assert_eq!(kotlin_to_float(16_777_218.0), 16_777_218.0f32);
    }

    #[test]
    fn kotlin_to_float_handles_extremes_and_the_subnormal_grid() {
        assert_eq!(kotlin_to_float(f64::INFINITY), f32::INFINITY);
        assert_eq!(kotlin_to_float(f64::NEG_INFINITY), f32::NEG_INFINITY);
        assert!(kotlin_to_float(f64::NAN).is_nan());
        assert_eq!(kotlin_to_float(1e300), f32::INFINITY);
        assert_eq!(kotlin_to_float(-1e300), f32::NEG_INFINITY);
        assert_eq!(kotlin_to_float(1e-310).to_bits(), 0);
        assert_eq!(kotlin_to_float(-1e-310).to_bits(), 1 << 31);
        // 1.5 * 2^-150 rounds up to the minimum subnormal; the halfway
        // value 2^-150 ties to even and rounds to zero.
        let rounds_up = f64::from_bits((873u64 << 52) | (1u64 << 51));
        assert_eq!(kotlin_to_float(rounds_up).to_bits(), 1);
        let halfway = f64::from_bits(873u64 << 52);
        assert_eq!(kotlin_to_float(halfway).to_bits(), 0);
    }

    #[test]
    fn trunc_sat_i64_truncates_and_saturates() {
        assert_eq!(trunc_sat_i64(0.0), 0);
        assert_eq!(trunc_sat_i64(0.9), 0);
        assert_eq!(trunc_sat_i64(-0.9), 0);
        assert_eq!(trunc_sat_i64(1.9), 1);
        assert_eq!(trunc_sat_i64(-1.9), -1);
        assert_eq!(trunc_sat_i64(f64::NAN), 0);
        assert_eq!(trunc_sat_i64(f64::INFINITY), i64::MAX);
        assert_eq!(trunc_sat_i64(f64::NEG_INFINITY), i64::MIN);
        // The largest finite value below 2^63 converts exactly; the next
        // representable step up is 2^63 and saturates.
        assert_eq!(
            trunc_sat_i64(9_223_372_036_854_774_784.0),
            9_223_372_036_854_774_784
        );
        assert_eq!(
            trunc_sat_i64(-9_223_372_036_854_774_784.0),
            -9_223_372_036_854_774_784
        );
        assert_eq!(trunc_sat_i64(9_223_372_036_854_775_808.0), i64::MAX);
        assert_eq!(trunc_sat_i64(-9_223_372_036_854_775_808.0), i64::MIN);
        // Powers of two and values above 2^52 cover the decimal path.
        assert_eq!(trunc_sat_i64(1_048_576.0), 1 << 20);
        assert_eq!(trunc_sat_i64(4_611_686_018_427_387_904.0), 1 << 62);
    }

    #[test]
    fn trunc_sat_narrows_with_saturation() {
        assert_eq!(trunc_sat_i32(f64::NAN), 0);
        assert_eq!(trunc_sat_i32(2_147_483_647.9), 2147483647);
        assert_eq!(trunc_sat_i32(2_147_483_648.0), i32::MAX);
        assert_eq!(trunc_sat_i32(-2_147_483_648.9), i32::MIN);
        assert_eq!(trunc_sat_i32(-2_147_483_649.0), i32::MIN);
        assert_eq!(trunc_sat_u32(-1.0), 0);
        assert_eq!(trunc_sat_u32(-0.5), 0);
        assert_eq!(trunc_sat_u32(f64::NAN), 0);
        assert_eq!(trunc_sat_u32(4_294_967_295.9), u32::MAX);
        assert_eq!(trunc_sat_u32(4_294_967_296.0), u32::MAX);
        assert_eq!(trunc_sat_usize(-0.5), 0);
        assert_eq!(trunc_sat_usize(3.7), 3);
        assert_eq!(trunc_sat_usize(1e19), usize::MAX);
    }

    #[test]
    fn round_sat_i32_rounds_half_away_from_zero() {
        assert_eq!(round_sat_i32(0.4), 0);
        assert_eq!(round_sat_i32(-0.4), 0);
        assert_eq!(round_sat_i32(0.5), 1);
        assert_eq!(round_sat_i32(-0.5), -1);
        assert_eq!(round_sat_i32(2.5), 3);
        assert_eq!(round_sat_i32(f32::NAN), 0);
        assert_eq!(round_sat_i32(-2_147_483_648.0), i32::MIN);
        assert_eq!(round_sat_i32(2_147_483_648.0), i32::MAX);
        assert_eq!(round_sat_i32(f32::MAX), i32::MAX);
        assert_eq!(round_sat_i32(f32::NEG_INFINITY), i32::MIN);
    }

    #[test]
    fn js_int_to_number_rounds_ties_to_even() {
        assert_eq!(js_int_to_number(0), 0.0);
        assert_eq!(js_int_to_number(-2), -2.0);
        assert_eq!(js_int_to_number(4_000_000_000), 4e9);
        // 2^53 + 1 ties down to 2^53; 2^53 + 3 ties up to 2^53 + 4.
        assert_eq!(
            js_int_to_number(9_007_199_254_740_993),
            9_007_199_254_740_992.0
        );
        assert_eq!(
            js_int_to_number(9_007_199_254_740_995),
            9_007_199_254_740_996.0
        );
        assert_eq!(js_int_to_number(i64::MIN), -9_223_372_036_854_775_808.0);
        assert_eq!(js_int_to_number(i64::MAX), 9_223_372_036_854_775_808.0);
    }

    #[test]
    fn number_string_matches_javascript_forms() {
        assert_eq!(js_number_string(0.0), "0");
        assert_eq!(js_number_string(-0.0), "0");
        assert_eq!(js_number_string(400.0), "400");
        assert_eq!(js_number_string(400.5), "400.5");
        assert_eq!(js_number_string(0.5), "0.5");
        assert_eq!(js_number_string(-42.75), "-42.75");
        assert_eq!(js_number_string(1e20), "100000000000000000000");
        assert_eq!(js_number_string(1e21), "1e+21");
        assert_eq!(js_number_string(1.5e25), "1.5e+25");
        assert_eq!(js_number_string(-1e21), "-1e+21");
        assert_eq!(js_number_string(1e-6), "0.000001");
        assert_eq!(js_number_string(1e-7), "1e-7");
        assert_eq!(js_number_string(1.5e-7), "1.5e-7");
        assert_eq!(js_number_string(f64::NAN), "NaN");
        assert_eq!(js_number_string(f64::INFINITY), "Infinity");
        assert_eq!(js_number_string(f64::NEG_INFINITY), "-Infinity");
    }

    #[test]
    fn math_min_max_propagate_nan_like_javascript() {
        assert_eq!(js_min(1.0, 2.0), 1.0);
        assert_eq!(js_max(1.0, 2.0), 2.0);
        assert!(js_min(f64::NAN, 2.0).is_nan());
        assert!(js_max(1.0, f64::NAN).is_nan());
        assert!(js_min(f64::NAN, f64::NAN).is_nan());
        assert_eq!(js_min(-0.0, 0.0).is_sign_negative(), true);
        assert_eq!(js_max(-0.0, 0.0).is_sign_negative(), false);
    }

    #[test]
    fn trim_strips_whitespace_and_bom() {
        assert_eq!(js_trim("  Source Han\t"), "Source Han");
        assert_eq!(js_trim("\u{feff}思源黑体\u{feff}"), "思源黑体");
        assert_eq!(js_trim("\u{00a0}x\u{2028}"), "x");
        assert_eq!(js_trim(""), "");
    }

    #[test]
    fn utf16_order_puts_surrogate_pairs_before_high_bmp() {
        let astral = "x\u{10000}";
        let high_bmp = "x\u{fffd}";
        assert_eq!(cmp_utf16(astral, high_bmp), Ordering::Less);
        // scalar order is the opposite; the comparator must not use it
        assert!(astral.chars().collect::<Vec<_>>() > high_bmp.chars().collect::<Vec<_>>());
    }
}

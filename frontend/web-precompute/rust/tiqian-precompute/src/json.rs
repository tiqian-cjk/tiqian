//! JSON emission matching `JSON.stringify`: the replay keys of
//! `snapshot-schema.js` are `JSON.stringify([...])` calls, so the Rust port
//! needs byte-compatible output: same key order (insertion), same number
//! formatting (`String(number)`), `NaN`/`Infinity` as `null`, `-0` as `0`.

use crate::js_compat::js_number_string;

/// A JSON value built in insertion order, the way JS object literals order
/// keys for `JSON.stringify`.
#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

impl Json {
    pub fn str(value: impl Into<String>) -> Json {
        Json::Str(value.into())
    }

    /// Renders the value the way `JSON.stringify` does.
    pub fn render(&self) -> String {
        let mut out = String::new();
        self.write(&mut out);
        out
    }

    fn write(&self, out: &mut String) {
        match self {
            Json::Null => out.push_str("null"),
            Json::Bool(value) => out.push_str(if *value { "true" } else { "false" }),
            Json::Num(value) => {
                // JSON.stringify maps NaN and ±Infinity to null.
                if value.is_finite() {
                    out.push_str(&js_number_string(*value));
                } else {
                    out.push_str("null");
                }
            }
            Json::Str(value) => out.push_str(&json_string(value)),
            Json::Arr(items) => {
                out.push('[');
                for (index, item) in items.iter().enumerate() {
                    if index > 0 {
                        out.push(',');
                    }
                    item.write(out);
                }
                out.push(']');
            }
            Json::Obj(fields) => {
                out.push('{');
                for (index, (key, value)) in fields.iter().enumerate() {
                    if index > 0 {
                        out.push(',');
                    }
                    out.push_str(&json_string(key));
                    out.push(':');
                    value.write(out);
                }
                out.push('}');
            }
        }
    }
}

/// `JSON.stringify(string)`: escapes `"`, `\`, the C0 shorthands and other
/// control characters; leaves everything above U+001F (including U+007F and
/// non-ASCII) as raw text.
pub fn json_string(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{0008}' => out.push_str("\\b"),
            '\u{0009}' => out.push_str("\\t"),
            '\u{000a}' => out.push_str("\\n"),
            '\u{000c}' => out.push_str("\\f"),
            '\u{000d}' => out.push_str("\\r"),
            c if u32::from(c) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", u32::from(c)));
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// A parse failure: position plus reason. Positions are byte offsets into the
/// input, so a caller can point at the offending text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JsonParseError {
    pub offset: usize,
    pub reason: String,
}

impl std::fmt::Display for JsonParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{} at offset {}", self.reason, self.offset)
    }
}

impl std::error::Error for JsonParseError {}

/// Parses one JSON document. The grammar is RFC 8259; recursion depth is
/// capped so hostile nesting cannot exhaust the stack.
pub fn parse_json(input: &str) -> Result<Json, JsonParseError> {
    let mut parser = Parser {
        bytes: input.as_bytes(),
        offset: 0,
        depth: 0,
    };
    parser.skip_whitespace();
    let value = parser.value()?;
    parser.skip_whitespace();
    if parser.offset != parser.bytes.len() {
        return Err(parser.fail("trailing content"));
    }
    Ok(value)
}

const MAX_DEPTH: usize = 100;

struct Parser<'a> {
    bytes: &'a [u8],
    offset: usize,
    depth: usize,
}

impl<'a> Parser<'a> {
    fn fail(&self, reason: &str) -> JsonParseError {
        JsonParseError {
            offset: self.offset,
            reason: reason.to_string(),
        }
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.offset).copied()
    }

    fn skip_whitespace(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\t' | b'\n' | b'\r')) {
            self.offset += 1;
        }
    }

    fn expect_byte(&mut self, byte: u8) -> Result<(), JsonParseError> {
        if self.peek() == Some(byte) {
            self.offset += 1;
            Ok(())
        } else {
            Err(self.fail(&format!("expected '{}'", char::from(byte))))
        }
    }

    fn literal(&mut self, word: &str, value: Json) -> Result<Json, JsonParseError> {
        if self.bytes[self.offset..].starts_with(word.as_bytes()) {
            self.offset += word.len();
            Ok(value)
        } else {
            Err(self.fail(&format!("expected '{word}'")))
        }
    }

    fn value(&mut self) -> Result<Json, JsonParseError> {
        match self.peek() {
            Some(b'{') => self.object(),
            Some(b'[') => self.array(),
            Some(b'"') => Ok(Json::Str(self.string()?)),
            Some(b't') => self.literal("true", Json::Bool(true)),
            Some(b'f') => self.literal("false", Json::Bool(false)),
            Some(b'n') => self.literal("null", Json::Null),
            Some(byte) if byte == b'-' || byte.is_ascii_digit() => self.number(),
            _ => Err(self.fail("expected a JSON value")),
        }
    }

    fn enter(&mut self) -> Result<(), JsonParseError> {
        self.depth += 1;
        if self.depth > MAX_DEPTH {
            Err(self.fail("nesting too deep"))
        } else {
            Ok(())
        }
    }

    fn object(&mut self) -> Result<Json, JsonParseError> {
        self.enter()?;
        self.expect_byte(b'{')?;
        let mut fields = Vec::new();
        self.skip_whitespace();
        if self.peek() == Some(b'}') {
            self.offset += 1;
            self.depth -= 1;
            return Ok(Json::Obj(fields));
        }
        loop {
            self.skip_whitespace();
            let key = self.string()?;
            self.skip_whitespace();
            self.expect_byte(b':')?;
            self.skip_whitespace();
            let value = self.value()?;
            fields.push((key, value));
            self.skip_whitespace();
            match self.peek() {
                Some(b',') => self.offset += 1,
                Some(b'}') => {
                    self.offset += 1;
                    self.depth -= 1;
                    return Ok(Json::Obj(fields));
                }
                _ => return Err(self.fail("expected ',' or '}'")),
            }
        }
    }

    fn array(&mut self) -> Result<Json, JsonParseError> {
        self.enter()?;
        self.expect_byte(b'[')?;
        let mut items = Vec::new();
        self.skip_whitespace();
        if self.peek() == Some(b']') {
            self.offset += 1;
            self.depth -= 1;
            return Ok(Json::Arr(items));
        }
        loop {
            self.skip_whitespace();
            items.push(self.value()?);
            self.skip_whitespace();
            match self.peek() {
                Some(b',') => self.offset += 1,
                Some(b']') => {
                    self.offset += 1;
                    self.depth -= 1;
                    return Ok(Json::Arr(items));
                }
                _ => return Err(self.fail("expected ',' or ']'")),
            }
        }
    }

    fn string(&mut self) -> Result<String, JsonParseError> {
        self.expect_byte(b'"')?;
        let mut out = String::new();
        loop {
            let byte = self
                .peek()
                .ok_or_else(|| self.fail("unterminated string"))?;
            match byte {
                b'"' => {
                    self.offset += 1;
                    return Ok(out);
                }
                b'\\' => {
                    self.offset += 1;
                    let escape = self
                        .peek()
                        .ok_or_else(|| self.fail("unterminated escape"))?;
                    self.offset += 1;
                    match escape {
                        b'"' => out.push('"'),
                        b'\\' => out.push('\\'),
                        b'/' => out.push('/'),
                        b'b' => out.push('\u{0008}'),
                        b'f' => out.push('\u{000c}'),
                        b'n' => out.push('\n'),
                        b'r' => out.push('\r'),
                        b't' => out.push('\t'),
                        b'u' => {
                            let high = self.hex4()?;
                            let scalar = if (0xD800..0xDC00).contains(&high) {
                                // A leading surrogate must be followed by its trail.
                                if self.peek() != Some(b'\\') {
                                    return Err(self.fail("lone leading surrogate"));
                                }
                                self.offset += 1;
                                if self.peek() != Some(b'u') {
                                    return Err(self.fail("lone leading surrogate"));
                                }
                                self.offset += 1;
                                let low = self.hex4()?;
                                if !(0xDC00..0xE000).contains(&low) {
                                    return Err(self.fail("invalid surrogate pair"));
                                }
                                0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                            } else if (0xDC00..0xE000).contains(&high) {
                                return Err(self.fail("lone trailing surrogate"));
                            } else {
                                high
                            };
                            out.push(
                                char::from_u32(scalar)
                                    .ok_or_else(|| self.fail("invalid escape"))?,
                            );
                        }
                        _ => return Err(self.fail("unknown escape")),
                    }
                }
                byte if byte < 0x20 => return Err(self.fail("raw control character")),
                _ => {
                    // Copy one UTF-8 scalar. The input is a &str, so the
                    // encoding is valid at every scalar boundary.
                    let start = self.offset;
                    let width = utf8_width(byte);
                    let chunk = self
                        .bytes
                        .get(start..start + width)
                        .and_then(|slice| std::str::from_utf8(slice).ok())
                        .ok_or_else(|| self.fail("invalid UTF-8"))?;
                    self.offset += width;
                    out.push_str(chunk);
                }
            }
        }
    }

    fn hex4(&mut self) -> Result<u32, JsonParseError> {
        let mut value = 0u32;
        for _ in 0..4 {
            let digit = self
                .peek()
                .ok_or_else(|| self.fail("truncated \\u escape"))?;
            let nibble = match digit {
                b'0'..=b'9' => u32::from(digit - b'0'),
                b'a'..=b'f' => u32::from(digit - b'a' + 10),
                b'A'..=b'F' => u32::from(digit - b'A' + 10),
                _ => return Err(self.fail("invalid \\u escape")),
            };
            value = value * 16 + nibble;
            self.offset += 1;
        }
        Ok(value)
    }

    fn number(&mut self) -> Result<Json, JsonParseError> {
        let start = self.offset;
        if self.peek() == Some(b'-') {
            self.offset += 1;
        }
        let digits_start = self.offset;
        while self.peek().is_some_and(|byte| byte.is_ascii_digit()) {
            self.offset += 1;
        }
        if self.offset == digits_start {
            return Err(self.fail("expected a digit"));
        }
        if self.bytes[digits_start] == b'0' && self.offset - digits_start > 1 {
            return Err(self.fail("leading zero"));
        }
        if self.peek() == Some(b'.') {
            self.offset += 1;
            let frac_start = self.offset;
            while self.peek().is_some_and(|byte| byte.is_ascii_digit()) {
                self.offset += 1;
            }
            if self.offset == frac_start {
                return Err(self.fail("expected a digit after '.'"));
            }
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.offset += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.offset += 1;
            }
            let exponent_start = self.offset;
            while self.peek().is_some_and(|byte| byte.is_ascii_digit()) {
                self.offset += 1;
            }
            if self.offset == exponent_start {
                return Err(self.fail("expected a digit in the exponent"));
            }
        }
        let text = std::str::from_utf8(&self.bytes[start..self.offset]).unwrap_or("");
        text.parse::<f64>()
            .map(Json::Num)
            .map_err(|_| self.fail("invalid number"))
    }
}

fn utf8_width(byte: u8) -> usize {
    match byte {
        0x00..=0x7F => 1,
        0xC0..=0xDF => 2,
        0xE0..=0xEF => 3,
        _ => 4,
    }
}

/// Reads one object member; non-objects and missing keys read as absent.
pub fn member<'a>(value: &'a Json, name: &str) -> Option<&'a Json> {
    let Json::Obj(fields) = value else {
        return None;
    };
    fields
        .iter()
        .find(|(key, _)| key == name)
        .map(|(_, inner)| inner)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn string_escapes_match_json_stringify() {
        assert_eq!(json_string("plain"), "\"plain\"");
        assert_eq!(json_string("a\"b\\c"), "\"a\\\"b\\\\c\"");
        assert_eq!(json_string("line\nbreak\ttab"), "\"line\\nbreak\\ttab\"");
        assert_eq!(json_string("\u{0001}\u{001f}"), "\"\\u0001\\u001f\"");
        // U+007F and astral characters stay raw, the way stringify writes them.
        assert_eq!(json_string("\u{007f}你😀"), "\"\u{007f}你😀\"");
    }

    #[test]
    fn numbers_render_like_stringify() {
        assert_eq!(Json::Num(400.0).render(), "400");
        assert_eq!(Json::Num(400.5).render(), "400.5");
        assert_eq!(Json::Num(-0.0).render(), "0");
        assert_eq!(Json::Num(f64::NAN).render(), "null");
        assert_eq!(Json::Num(f64::INFINITY).render(), "null");
        assert_eq!(Json::Num(1e21).render(), "1e+21");
        assert_eq!(Json::Num(0.000001).render(), "0.000001");
        assert_eq!(Json::Num(1e-7).render(), "1e-7");
    }

    #[test]
    fn arrays_and_objects_keep_insertion_order() {
        let value = Json::Arr(vec![
            Json::str("a\u{001f}b"),
            Json::Num(700.0),
            Json::Bool(false),
            Json::Null,
            Json::Obj(vec![
                ("wght".to_string(), Json::Num(350.0)),
                ("rest".to_string(), Json::Null),
            ]),
        ]);
        assert_eq!(
            value.render(),
            "[\"a\\u001fb\",700,false,null,{\"wght\":350,\"rest\":null}]"
        );
    }

    #[test]
    fn parse_reads_primitives_and_nesting() {
        assert_eq!(parse_json("null").unwrap(), Json::Null);
        assert_eq!(parse_json(" true\t").unwrap(), Json::Bool(true));
        assert_eq!(parse_json("-12.5e2").unwrap(), Json::Num(-1250.0));
        assert_eq!(parse_json("\"a\\nb\"").unwrap(), Json::str("a\nb"));
        assert_eq!(
            parse_json("{\"lines\":[1,{\"end\":\"AutoWrap\"}]}").unwrap(),
            Json::Obj(vec![(
                "lines".to_string(),
                Json::Arr(vec![
                    Json::Num(1.0),
                    Json::Obj(vec![("end".to_string(), Json::str("AutoWrap"),)]),
                ])
            ),])
        );
    }

    #[test]
    fn parse_handles_escape_and_surrogate_pairs() {
        assert_eq!(parse_json("\"\\u0041\"").unwrap(), Json::str("A"));
        assert_eq!(parse_json("\"\\uD83D\\uDE00\"").unwrap(), Json::str("😀"));
        assert!(parse_json("\"\\uD83D\"").is_err());
        assert!(parse_json("\"\\uDC00\"").is_err());
        assert!(parse_json("\"\\uD83D\\u0041\"").is_err());
    }

    #[test]
    fn parse_rejects_damage() {
        assert!(parse_json("").is_err());
        assert!(parse_json("{} extra").is_err());
        assert!(parse_json("{").is_err());
        assert!(parse_json("[1,]").is_err());
        assert!(parse_json("01").is_err());
        assert!(parse_json("1.").is_err());
        assert!(parse_json("\"raw\nline\"").is_err());
        assert!(parse_json(&"[".repeat(200)).is_err());
    }

    #[test]
    fn parse_round_trips_plan_shaped_documents() {
        let value = parse_json(
            "{\"schema\":1,\"width\":80.0,\"cells\":[{\"source\":\"正文\",\"flag\":true}]}",
        )
        .unwrap();
        assert_eq!(
            value.render(),
            "{\"schema\":1,\"width\":80,\"cells\":[{\"source\":\"正文\",\"flag\":true}]}"
        );
    }
}

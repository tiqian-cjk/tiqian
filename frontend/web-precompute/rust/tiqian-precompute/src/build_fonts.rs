//! `parseBuildFontStylesheet` of `precompute-node-fonts.js` (ADR 0050): the
//! pure half of build font loading. The host lane reads the stylesheet bytes,
//! resolves the source path against the working directory and reads the font
//! files this parse points at; everything here works on the CSS text and the
//! resolved `file:` URL. Error names and their payloads match the js throws
//! byte for byte. Two inputs the js layer answers with a Node `TypeError`
//! (an invalid `file:` URL path or an unparseable asset URL) surface here as
//! the named issues `InvalidFileUrlPath` and `InvalidStylesheetAssetUrl`.

use tiqian::NamedError;
use url::Url;

use crate::font_record::FontWeightSpec;
use crate::js_compat::{js_to_number, js_trim, split_js_whitespace};

/// The origin relative public URLs resolve against; a result back on this
/// origin collapses to its path, query and hash.
const DUMMY_PUBLIC_ORIGIN: &str = "https://tiqian.invalid";

/// One face of `parseBuildFontStylesheet`. `source_path` is the filesystem
/// path of the font binary; the host reads it.
pub struct StylesheetFace {
    pub family: String,
    pub source_path: String,
    pub public_url: String,
    pub weight: FontWeightSpec,
    pub style: String,
    pub unicode_range: String,
}

/// `parseBuildFontStylesheet(css, { source, publicUrl })`. `source_file_url`
/// is the stylesheet location as a `file:` URL string; `stylesheet_public_url`
/// is the URL the host serves that stylesheet from, `None` when absent.
pub fn parse_build_font_stylesheet(
    css: &str,
    source_file_url: &str,
    stylesheet_public_url: Option<&str>,
) -> Result<Vec<StylesheetFace>, NamedError> {
    let stylesheet_url = Url::parse(source_file_url)
        .map_err(|_| NamedError(format!("UnsupportedFontStylesheetSource:{source_file_url}")))?;
    if stylesheet_url.scheme() != "file" {
        return Err(NamedError(format!(
            "RemoteFontStylesheetNotSupported:{}",
            stylesheet_url.as_str()
        )));
    }
    let stylesheet_path = file_url_path(&stylesheet_url)?;
    let mut faces = Vec::new();
    for body in font_face_bodies(&strip_css_comments(css)) {
        let family = unquote(css_property(body, "font-family"));
        if family.is_empty() {
            return Err(NamedError("MissingFontStylesheetFamily".to_string()));
        }
        let source = css_property(body, "src");
        let asset_url = match url_property(&source) {
            Some(url) => url,
            None => return Err(NamedError(format!("MissingFontStylesheetUrl:{family}"))),
        };
        let source_url = join_url(&stylesheet_url, &asset_url)?;
        if source_url.scheme() != "file" {
            return Err(NamedError(format!(
                "RemoteFontSourceNotSupported:{}",
                source_url.as_str()
            )));
        }
        let source_path = file_url_path(&source_url)?;
        let public_url = resolve_public_asset_url(&asset_url, stylesheet_public_url)?;
        let weight = parse_weight(css_property(body, "font-weight"))?;
        let style = parse_style(css_property(body, "font-style"))?;
        let unicode_range = css_property(body, "unicode-range").to_string();
        faces.push(StylesheetFace {
            family: family.to_string(),
            source_path,
            public_url,
            weight,
            style,
            unicode_range,
        });
    }
    if faces.is_empty() {
        return Err(NamedError(format!(
            "MissingFontFacesInStylesheet:{stylesheet_path}"
        )));
    }
    Ok(faces)
}

/// `/\/\*[\s\S]*?\*\//gu`: every comment up to its nearest terminator. An
/// unterminated comment stays in place; the js pattern needs the terminator.
fn strip_css_comments(css: &str) -> String {
    let mut out = String::with_capacity(css.len());
    let mut rest = css;
    while let Some(start) = rest.find("/*") {
        let after = &rest[start + 2..];
        match after.find("*/") {
            Some(end) => {
                out.push_str(&rest[..start]);
                rest = &after[end + 2..];
            }
            None => break,
        }
    }
    out.push_str(rest);
    out
}

/// `/@font-face\s*\{([^}]*)\}/giu`: the bodies of every well-formed rule, in
/// document order. The needle is ASCII, so a byte scan cannot start inside a
/// multi-byte character.
fn font_face_bodies(css: &str) -> Vec<&str> {
    let mut bodies = Vec::new();
    let bytes = css.as_bytes();
    let needle = b"@font-face";
    let mut cursor = 0;
    while cursor <= css.len() {
        let start = match find_ascii_ci(bytes, needle, cursor) {
            Some(start) => start,
            None => break,
        };
        let mut after = start + needle.len();
        after += whitespace_run(bytes, after);
        if bytes.get(after) != Some(&b'{') {
            cursor = next_char_boundary(css, start);
            continue;
        }
        match css[after + 1..].find('}') {
            Some(end) => {
                bodies.push(&css[after + 1..after + 1 + end]);
                cursor = after + 1 + end + 1;
            }
            None => cursor = next_char_boundary(css, start),
        }
    }
    bodies
}

/// Finds `needle` case-insensitively from `from`; ASCII needles only match
/// on char boundaries because their bytes are all below 0x80.
fn find_ascii_ci(bytes: &[u8], needle: &[u8], from: usize) -> Option<usize> {
    if needle.is_empty() || from >= bytes.len() {
        return None;
    }
    let last = bytes.len() - needle.len();
    let mut position = from;
    while position <= last {
        if bytes[position..position + needle.len()]
            .iter()
            .zip(needle)
            .all(|(left, right)| left.eq_ignore_ascii_case(right))
        {
            return Some(position);
        }
        position += 1;
    }
    None
}

/// The length of the ECMAScript `\s*` run starting at `from`.
fn whitespace_run(bytes: &[u8], from: usize) -> usize {
    let mut length = 0;
    for byte in bytes.iter().skip(from) {
        match byte {
            b'\t' | b'\n' | b'\x0b' | b'\x0c' | b'\r' | b' ' => length += 1,
            // Multibyte whitespace cannot continue an ASCII \s run.
            _ => break,
        }
    }
    length
}

fn next_char_boundary(css: &str, position: usize) -> usize {
    let mut next = position + 1;
    while next < css.len() && !css.is_char_boundary(next) {
        next += 1;
    }
    next
}

/// `cssProperty(body, name)`: the first `(?:^|;)\s*name\s*:\s*([^;}]+)`
/// match, trimmed. The name occurs in document order and must sit after a
/// semicolon or at the start, separated by whitespace only.
fn css_property<'a>(body: &'a str, name: &str) -> &'a str {
    let bytes = body.as_bytes();
    let name_bytes = name.as_bytes();
    let mut cursor = 0;
    while cursor <= body.len() {
        let found = match find_ascii_ci(bytes, name_bytes, cursor) {
            Some(found) => found,
            None => break,
        };
        let before = whitespace_run_back(bytes, found);
        if found - before != 0 && bytes.get(found - before - 1) != Some(&b';') {
            cursor = next_char_boundary(body, found);
            continue;
        }
        let mut value = found + name.len();
        value += whitespace_run(bytes, value);
        if bytes.get(value) != Some(&b':') {
            cursor = next_char_boundary(body, found);
            continue;
        }
        value += 1;
        value += whitespace_run(bytes, value);
        let end = bytes[value..]
            .iter()
            .position(|byte| *byte == b';' || *byte == b'}')
            .map_or(body.len(), |offset| value + offset);
        if end == value {
            cursor = next_char_boundary(body, found);
            continue;
        }
        return js_trim(&body[value..end]);
    }
    ""
}

/// The length of the ASCII whitespace run ending at `from`.
fn whitespace_run_back(bytes: &[u8], from: usize) -> usize {
    let mut length = 0;
    for byte in bytes[..from].iter().rev() {
        match byte {
            b'\t' | b'\n' | b'\x0b' | b'\x0c' | b'\r' | b' ' => length += 1,
            _ => break,
        }
    }
    length
}

/// `unquote(value)`: one surrounding quote pair removed.
fn unquote(value: &str) -> &str {
    let trimmed = js_trim(value);
    let bytes = trimmed.as_bytes();
    if bytes.len() >= 2 {
        let (first, last) = (bytes[0], bytes[bytes.len() - 1]);
        if (first == b'"' && last == b'"') || (first == b'\'' && last == b'\'') {
            return &trimmed[1..trimmed.len() - 1];
        }
    }
    trimmed
}

/// `/url\(\s*(['"]?)([^'")]+)\1\s*\)/iu` over a `src` value: the first
/// `url(...)` payload with its quote, if any.
fn url_property(source: &str) -> Option<String> {
    let bytes = source.as_bytes();
    let needle = b"url(";
    let mut cursor = 0;
    while cursor <= source.len() {
        let start = find_ascii_ci(bytes, needle, cursor)?;
        let mut value = start + needle.len();
        value += whitespace_run(bytes, value);
        let (quote, forbidden_close) = match bytes.get(value) {
            Some(b'"') => (b'"', true),
            Some(b'\'') => (b'\'', true),
            _ => (0, false),
        };
        if quote != 0 {
            value += 1;
        }
        let end = bytes[value..]
            .iter()
            .position(|byte| *byte == b'"' || *byte == b'\'' || *byte == b')')?;
        let payload = &source[value..value + end];
        if payload.is_empty() {
            cursor = next_char_boundary(source, start);
            continue;
        }
        let mut after = value + end;
        if quote != 0 {
            if bytes.get(after) != Some(&quote) {
                cursor = next_char_boundary(source, start);
                continue;
            }
            after += 1;
        } else if forbidden_close {
            cursor = next_char_boundary(source, start);
            continue;
        }
        after += whitespace_run(bytes, after);
        if bytes.get(after) == Some(&b')') {
            return Some(payload.to_string());
        }
        cursor = next_char_boundary(source, start);
    }
    None
}

/// `new URL(asset, stylesheetFileUrl)`; both sides follow WHATWG parsing.
fn join_url(base: &Url, asset: &str) -> Result<Url, NamedError> {
    base.join(asset)
        .map_err(|_| NamedError(format!("InvalidStylesheetAssetUrl:{asset}")))
}

/// `fileURLToPath(url)`; `InvalidFileUrlPath` replaces the Node TypeError for
/// locations `to_file_path` cannot express.
fn file_url_path(url: &Url) -> Result<String, NamedError> {
    url.to_file_path()
        .map(|path| path.to_string_lossy().into_owned())
        .map_err(|_| NamedError(format!("InvalidFileUrlPath:{}", url.as_str())))
}

/// `parseWeight`: one positive number or an ascending pair.
fn parse_weight(value: &str) -> Result<FontWeightSpec, NamedError> {
    let text = if value.is_empty() { "400" } else { value };
    let weights: Vec<f64> = split_js_whitespace(js_trim(text))
        .iter()
        .map(|part| js_to_number(part))
        .collect();
    if weights.len() == 1 && weights[0].is_finite() && weights[0] > 0.0 {
        return Ok(FontWeightSpec::Single(Some(weights[0])));
    }
    if weights.len() == 2
        && weights
            .iter()
            .all(|weight| weight.is_finite() && *weight > 0.0)
        && weights[1] >= weights[0]
    {
        return Ok(FontWeightSpec::Range(weights[0], weights[1]));
    }
    Err(NamedError(format!(
        "UnsupportedFontStylesheetWeight:{value}"
    )))
}

/// `parseStyle`: `normal` or `italic`, case-insensitive.
fn parse_style(value: &str) -> Result<String, NamedError> {
    let text = if value.is_empty() { "normal" } else { value };
    let style = js_trim(text).to_lowercase();
    if style == "normal" || style == "italic" {
        return Ok(style);
    }
    Err(NamedError(format!(
        "UnsupportedFontStylesheetStyle:{value}"
    )))
}

/// `resolvePublicAssetUrl`: scheme-prefixed assets keep their absolute URL;
/// relative ones resolve against the stylesheet's public URL. Results back on
/// the dummy origin reduce to path, query and hash.
fn resolve_public_asset_url(
    asset_url: &str,
    public_url: Option<&str>,
) -> Result<String, NamedError> {
    if has_url_scheme(asset_url) {
        let absolute = Url::parse(asset_url)
            .map_err(|_| NamedError(format!("InvalidStylesheetAssetUrl:{asset_url}")))?;
        return Ok(absolute.as_str().to_string());
    }
    let stylesheet_public_url = js_trim(public_url.unwrap_or("")).to_string();
    if stylesheet_public_url.is_empty() {
        return Err(NamedError(format!(
            "MissingFontStylesheetPublicUrl:{asset_url}"
        )));
    }
    let dummy = Url::parse(DUMMY_PUBLIC_ORIGIN)
        .map_err(|_| NamedError("InvalidDummyPublicOrigin".to_string()))?;
    let base = join_url(&dummy, &stylesheet_public_url)?;
    let resolved = join_url(&base, asset_url)?;
    if resolved.origin() == dummy.origin() {
        let query = resolved
            .query()
            .map(|value| format!("?{value}"))
            .unwrap_or_default();
        let fragment = resolved
            .fragment()
            .map(|value| format!("#{value}"))
            .unwrap_or_default();
        return Ok(format!("{}{query}{fragment}", resolved.path()));
    }
    Ok(resolved.as_str().to_string())
}

/// `/^[a-z][a-z0-9+.-]*:/iu`.
fn has_url_scheme(value: &str) -> bool {
    let mut characters = value.chars();
    match characters.next() {
        Some(first) if first.is_ascii_alphabetic() => {}
        _ => return false,
    }
    for character in characters {
        if character == ':' {
            return true;
        }
        if !(character.is_ascii_alphanumeric()
            || character == '+'
            || character == '.'
            || character == '-')
        {
            return false;
        }
    }
    false
}

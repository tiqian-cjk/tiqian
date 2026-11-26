//! Revision constants and `stableStringify` of `snapshot-schema.js`
//! (ADR 0050). The constants stay byte-identical to the js oracle for the
//! whole parity period; `stableStringify` feeds every artifact hash.
//!
//! The constants are single-sourced in the generated crate (boring cutover
//! Stage1-P4): every declaration below re-exports the associated constant
//! of the `Revision` type of `tiqian-protocol`, so the Haxe source
//! (engine-haxe/src/org/tiqian/protocol/Revision.hx) is the one place the
//! family is written.

use std::sync::LazyLock;

use crate::js_compat::{cmp_utf16, js_number_string};
use crate::json::{json_string, Json};
// The single-sourced revision family (generated crate); the constants below
// and the C ABI mirrors re-export its associated constants.
pub use tiqian_protocol::org::tiqian::protocol::revision::Revision as RevisionFamily;

/// `SNAPSHOT_SCHEMA` of every snapshot this revision understands.
pub const SNAPSHOT_SCHEMA: i64 = RevisionFamily::REVISION_SNAPSHOT_SCHEMA as i64;

/// `SNAPSHOT_TABLES_SCHEMA` of the manifest schema this revision reads and writes.
pub const SNAPSHOT_TABLES_SCHEMA: i64 = RevisionFamily::REVISION_SNAPSHOT_TABLES_SCHEMA as i64;

/// `LAYOUT_REVISION` of every snapshot this revision understands.
/// The generated constants are `&'static UStr` (UTF-16 units); the host
/// lane keeps `String`, so each re-export decodes once through
/// `to_utf8_lossy` behind a lazy static.
pub static LAYOUT_REVISION: LazyLock<String> =
    LazyLock::new(|| RevisionFamily::REVISION_LAYOUT_REVISION.to_utf8_lossy());

/// `RENDER_REVISION` of the prepared DOM lowering.
pub static RENDER_REVISION: LazyLock<String> =
    LazyLock::new(|| RevisionFamily::REVISION_RENDER_REVISION.to_utf8_lossy());

/// `FONT_SOURCE_POLICY` of the snapshot font evidence.
pub static FONT_SOURCE_POLICY: LazyLock<String> =
    LazyLock::new(|| RevisionFamily::REVISION_FONT_SOURCE_POLICY.to_utf8_lossy());

/// `FONT_BACKEND_REVISION` of the shared shaping backend.
pub static FONT_BACKEND_REVISION: LazyLock<String> =
    LazyLock::new(|| RevisionFamily::REVISION_FONT_BACKEND_REVISION.to_utf8_lossy());

/// `FONT_REPLAY_REVISION` of the replay tables.
pub static FONT_REPLAY_REVISION: LazyLock<String> =
    LazyLock::new(|| RevisionFamily::REVISION_FONT_REPLAY_REVISION.to_utf8_lossy());

/// `FONT_REPLAY_TRANSPORT` of the compact replay encoding.
pub static FONT_REPLAY_TRANSPORT: LazyLock<String> =
    LazyLock::new(|| RevisionFamily::REVISION_FONT_REPLAY_TRANSPORT.to_utf8_lossy());

/// `stableStringify`: primitives render through `JSON.stringify`, arrays
/// keep element order, object keys sort by UTF-16 code units.
pub fn stable_stringify(value: &Json) -> String {
    match value {
        Json::Null => "null".to_string(),
        Json::Bool(inner) => inner.to_string(),
        Json::Num(inner) => {
            if inner.is_finite() {
                js_number_string(*inner)
            } else {
                "null".to_string()
            }
        }
        Json::Str(inner) => json_string(inner),
        Json::Arr(items) => {
            let parts: Vec<String> = items.iter().map(stable_stringify).collect();
            format!("[{}]", parts.join(","))
        }
        Json::Obj(fields) => {
            let mut entries: Vec<&(String, Json)> = fields.iter().collect();
            entries.sort_by(|left, right| cmp_utf16(&left.0, &right.0));
            let parts: Vec<String> = entries
                .iter()
                .map(|(key, inner)| format!("{}:{}", json_string(key), stable_stringify(inner)))
                .collect();
            format!("{{{}}}", parts.join(","))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn revision_constants_match_the_js_oracle() {
        // The module constants now re-export the generated crate's
        // constants (Stage1-P4 single source), so asserting the literals
        // pins the generated values item by item.
        assert_eq!(SNAPSHOT_SCHEMA, 1);
        assert_eq!(SNAPSHOT_TABLES_SCHEMA, 2);
        assert_eq!(LAYOUT_REVISION.as_str(), "tiqian-layout-v2");
        assert_eq!(RENDER_REVISION.as_str(), "prebroken-dom-v16");
        assert_eq!(FONT_SOURCE_POLICY.as_str(), "host-compatible-stylesheet-v1");
        assert_eq!(FONT_BACKEND_REVISION.as_str(), "tiqian-shared-harfbuzz-v5");
        assert_eq!(
            FONT_REPLAY_REVISION.as_str(),
            "tiqian-server-shaping-replay-v1"
        );
        assert_eq!(FONT_REPLAY_TRANSPORT.as_str(), "shared-strings-v1");
        // The plan reader and the session constants re-export the same
        // single source; the declarations must not drift.
        assert_eq!(
            LAYOUT_REVISION.as_str(),
            crate::plan::PLAN_LAYOUT_REVISION.as_str()
        );
        assert_eq!(
            crate::session::BACKEND_REVISION.as_str(),
            RevisionFamily::REVISION_FONT_BACKEND_REVISION.to_utf8_lossy()
        );
        assert_eq!(
            crate::session::FONT_REPLAY_REVISION.as_str(),
            RevisionFamily::REVISION_FONT_REPLAY_REVISION.to_utf8_lossy()
        );
    }

    #[test]
    fn stable_stringify_sorts_object_keys_and_keeps_array_order() {
        let value = Json::Obj(vec![
            ("z".to_string(), Json::Num(1.0)),
            (
                "a".to_string(),
                Json::Arr(vec![Json::Num(2.0), Json::Num(1.0)]),
            ),
            (
                "m".to_string(),
                Json::Obj(vec![("k".to_string(), Json::str("v"))]),
            ),
        ]);
        assert_eq!(
            stable_stringify(&value),
            "{\"a\":[2,1],\"m\":{\"k\":\"v\"},\"z\":1}"
        );
    }

    #[test]
    fn stable_stringify_renders_primitives_like_json() {
        assert_eq!(stable_stringify(&Json::Null), "null");
        assert_eq!(stable_stringify(&Json::Bool(true)), "true");
        assert_eq!(stable_stringify(&Json::Num(400.5)), "400.5");
        assert_eq!(stable_stringify(&Json::Num(-0.0)), "0");
        assert_eq!(stable_stringify(&Json::Num(f64::NAN)), "null");
        assert_eq!(stable_stringify(&Json::str("a\"b")), "\"a\\\"b\"");
        assert_eq!(stable_stringify(&Json::Arr(vec![])), "[]");
        assert_eq!(stable_stringify(&Json::Obj(vec![])), "{}");
    }

    #[test]
    fn stable_stringify_orders_keys_by_utf16_units() {
        // U+10000 encodes as a surrogate pair below U+E000, so the astral key
        // sorts before the BMP key under JS ordering.
        let value = Json::Obj(vec![
            ("\u{fffd}".to_string(), Json::Num(1.0)),
            ("\u{10000}".to_string(), Json::Num(2.0)),
        ]);
        assert_eq!(stable_stringify(&value), "{\"\u{10000}\":2,\"\u{fffd}\":1}");
    }
}
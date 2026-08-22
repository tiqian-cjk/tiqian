//! Revision constants and `stableStringify` of `snapshot-schema.js`
//! (ADR 0050). The constants stay byte-identical to the js oracle for the
//! whole parity period; `stableStringify` feeds every artifact hash.

use crate::js_compat::{cmp_utf16, js_number_string};
use crate::json::{json_string, Json};

/// `SNAPSHOT_SCHEMA` of every snapshot this revision understands.
pub const SNAPSHOT_SCHEMA: i64 = 1;

/// `LAYOUT_REVISION` of every snapshot this revision understands.
pub const LAYOUT_REVISION: &str = "tiqian-layout-v2";

/// `RENDER_REVISION` of the prepared DOM lowering.
pub const RENDER_REVISION: &str = "prebroken-dom-v15";

/// `FONT_SOURCE_POLICY` of the snapshot font evidence.
pub const FONT_SOURCE_POLICY: &str = "host-compatible-stylesheet-v1";

/// `FONT_BACKEND_REVISION` of the shared shaping backend.
pub const FONT_BACKEND_REVISION: &str = "tiqian-shared-harfbuzz-v5";

/// `FONT_REPLAY_REVISION` of the replay tables.
pub const FONT_REPLAY_REVISION: &str = "tiqian-server-shaping-replay-v1";

/// `FONT_REPLAY_TRANSPORT` of the compact replay encoding.
pub const FONT_REPLAY_TRANSPORT: &str = "shared-strings-v1";

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
        assert_eq!(SNAPSHOT_SCHEMA, 1);
        assert_eq!(LAYOUT_REVISION, "tiqian-layout-v2");
        assert_eq!(RENDER_REVISION, "prebroken-dom-v15");
        assert_eq!(FONT_SOURCE_POLICY, "host-compatible-stylesheet-v1");
        assert_eq!(FONT_BACKEND_REVISION, "tiqian-shared-harfbuzz-v5");
        assert_eq!(FONT_REPLAY_REVISION, "tiqian-server-shaping-replay-v1");
        assert_eq!(FONT_REPLAY_TRANSPORT, "shared-strings-v1");
        // The plan reader carries its own copy of the layout revision; the two
        // declarations must not drift.
        assert_eq!(LAYOUT_REVISION, crate::plan::PLAN_LAYOUT_REVISION);
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

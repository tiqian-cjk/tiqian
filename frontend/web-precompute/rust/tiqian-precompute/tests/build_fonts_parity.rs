//! Build-font stylesheet parity against the frozen js oracle dump (ADR 0050
//! amendment `PrecomputeInRust`). The js implementation was removed with the
//! legacy cutover, so the matrix in this file compares against
//! `tests/build-fonts-golden.txt`: one `name\tdump` line per case
//! (stableStringify of the face list, or `ERROR:<message>` for throws),
//! recorded when the lane still ran the js oracle and matched byte for byte.
//! Regenerate with `TIQIAN_UPDATE_GOLDEN=1 cargo test --test
//! build_fonts_parity` after reviewing the diff. Every case names its
//! stylesheet as a `file:` URL string, so Node path resolution stayed out of
//! the comparison when the golden was recorded. Pure parsing; the engine link
//! is not required.

use std::path::PathBuf;

use tiqian_precompute::build_fonts::parse_build_font_stylesheet;
use tiqian_precompute::font_record::FontWeightSpec;
use tiqian_precompute::json::Json;
use tiqian_precompute::schema::stable_stringify;

const SOURCE_URL: &str = "file:///srv/styles/main.css";

fn case(name: &str, css: &str, public_url: Option<&str>) -> Json {
    let mut fields = vec![
        ("name".to_string(), Json::str(name)),
        ("css".to_string(), Json::str(css)),
        ("source".to_string(), Json::str(SOURCE_URL)),
    ];
    if let Some(public_url) = public_url {
        fields.push(("publicUrl".to_string(), Json::str(public_url)));
    }
    Json::Obj(fields)
}

fn case_matrix() -> Vec<Json> {
    vec![
        case(
            "simpleFace",
            "@font-face { font-family: Test; src: url(font.woff2); }",
            Some("/styles/main.css"),
        ),
        case(
            "quotedFamilyAndUrl",
            "@font-face { font-family: 'Dela Gothic One'; src: url('font.ttf'); }",
            Some("https://cdn.example/styles/main.css"),
        ),
        case(
            "subdirTraversal",
            "@font-face { font-family: Test; src: url(../fonts/f.woff2); }",
            Some("/styles/main.css"),
        ),
        case(
            "absoluteAssetPath",
            "@font-face { font-family: Test; src: url(/assets/f.woff2); }",
            Some("/styles/main.css"),
        ),
        case(
            "queryHash",
            "@font-face { font-family: Test; src: url(font.woff2?v=3#h); }",
            Some("/styles/main.css"),
        ),
        case(
            "weightRange",
            "@font-face { font-family: T; src: url(f); font-weight: 300 500; }",
            Some("/styles/main.css"),
        ),
        case(
            "propertyCasing",
            "@font-face { FONT-FAMILY: T; SRC: url(f); FONT-WEIGHT: 700; }",
            Some("/styles/main.css"),
        ),
        case(
            "missingFamily",
            "@font-face { src: url(f); }",
            Some("/styles/main.css"),
        ),
        case(
            "localSourceOnly",
            "@font-face { font-family: T; src: local(T); }",
            Some("/styles/main.css"),
        ),
        case(
            "badWeight",
            "@font-face { font-family: T; src: url(f); font-weight: bold; }",
            Some("/styles/main.css"),
        ),
        case(
            "descendingWeight",
            "@font-face { font-family: T; src: url(f); font-weight: 500 300; }",
            Some("/styles/main.css"),
        ),
        case(
            "negativeWeight",
            "@font-face { font-family: T; src: url(f); font-weight: -400; }",
            Some("/styles/main.css"),
        ),
        case(
            "italicStyleUpper",
            "@font-face { font-family: T; src: url(f); font-style: ITALIC; }",
            Some("/styles/main.css"),
        ),
        case(
            "obliqueStyle",
            "@font-face { font-family: T; src: url(f); font-style: oblique; }",
            Some("/styles/main.css"),
        ),
        case(
            "unicodeRangePresent",
            "@font-face { font-family: T; src: url(f); unicode-range: U+4E00-9FFF; }",
            Some("/styles/main.css"),
        ),
        case(
            "commentedOutRule",
            "/* @font-face { font-family: Hidden; src: url(h); } */\n@font-face { font-family: T; src: url(f); }",
            Some("/styles/main.css"),
        ),
        case(
            "inlineComment",
            "@font-face { /* font-family: Hidden; */ font-family: T; src: url(f); }",
            Some("/styles/main.css"),
        ),
        case(
            "plainRulesOnly",
            "p { color: red; }",
            Some("/styles/main.css"),
        ),
        case(
            "noPublicUrlRelative",
            "@font-face { font-family: T; src: url(font.woff2); }",
            None,
        ),
        case(
            "schemeAssetUrl",
            "@font-face { font-family: T; src: url(https://cdn.example/f.woff2); }",
            Some("/styles/main.css"),
        ),
        case(
            "spacesInUrl",
            "@font-face { font-family: T; src: url( \"my font.ttf\" ); }",
            Some("/styles/main.css"),
        ),
        case(
            "firstUrlWins",
            "@font-face { font-family: T; src: url(a.woff2) format(\"woff2\"), url(b.ttf); }",
            Some("/styles/main.css"),
        ),
        case(
            "uppercaseAtRule",
            "@FONT-FACE { font-family: T; src: url(f); }",
            Some("/styles/main.css"),
        ),
        case(
            "noSpaceBeforeBrace",
            "@font-face{font-family:T;src:url(f)}",
            Some("/styles/main.css"),
        ),
        case(
            "twoFaces",
            "@font-face { font-family: A; src: url(a); }\n@font-face { font-family: B; src: url(b); font-weight: 550; }",
            Some("/styles/main.css"),
        ),
        case(
            "driveLetterAsset",
            "@font-face { font-family: T; src: url(C:/fonts/f.ttf); }",
            Some("/styles/main.css"),
        ),
        case(
            "decimalWeight",
            "@font-face { font-family: T; src: url(f); font-weight: 400.5; }",
            Some("/styles/main.css"),
        ),
    ]
}

fn weight_json(weight: &FontWeightSpec) -> Json {
    match weight {
        FontWeightSpec::Single(Some(value)) => Json::Num(*value),
        FontWeightSpec::Single(None) => Json::Null,
        FontWeightSpec::Range(low, high) => Json::Arr(vec![Json::Num(*low), Json::Num(*high)]),
    }
}

fn run_rust_side(cases: &[Json]) -> Vec<String> {
    cases
        .iter()
        .map(|entry| {
            let Json::Obj(fields) = entry else {
                panic!("case object");
            };
            let member = |key: &str| {
                fields
                    .iter()
                    .find(|(name, _)| name == key)
                    .map(|(_, value)| value.clone())
            };
            let name = match member("name") {
                Some(Json::Str(name)) => name,
                _ => panic!("case name"),
            };
            let css = match member("css") {
                Some(Json::Str(css)) => css,
                _ => panic!("case css"),
            };
            let source = match member("source") {
                Some(Json::Str(source)) => source,
                _ => panic!("case source"),
            };
            let public_url = match member("publicUrl") {
                Some(Json::Str(value)) => Some(value),
                _ => None,
            };
            let result = parse_build_font_stylesheet(&css, &source, public_url.as_deref());
            match result {
                Ok(faces) => {
                    let dumped = Json::Arr(
                        faces
                            .iter()
                            .map(|face| {
                                Json::Obj(vec![
                                    ("family".to_string(), Json::str(face.family.clone())),
                                    ("source".to_string(), Json::str(face.source_path.clone())),
                                    ("publicUrl".to_string(), Json::str(face.public_url.clone())),
                                    ("weight".to_string(), weight_json(&face.weight)),
                                    ("style".to_string(), Json::str(face.style.clone())),
                                    (
                                        "unicodeRange".to_string(),
                                        Json::str(face.unicode_range.clone()),
                                    ),
                                ])
                            })
                            .collect(),
                    );
                    format!("{name}\t{}", stable_stringify(&dumped))
                }
                Err(error) => format!("{name}\tERROR:{}", error.0),
            }
        })
        .collect()
}

#[test]
fn build_font_stylesheet_matches_the_frozen_oracle_dump() {
    let cases = case_matrix();
    let rust_lines = run_rust_side(&cases);
    let golden_path =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/build-fonts-golden.txt");
    let golden = format!("{}\n", rust_lines.join("\n"));
    if std::env::var("TIQIAN_UPDATE_GOLDEN").is_ok_and(|value| value == "1") {
        std::fs::write(&golden_path, &golden).expect("golden writes");
        return;
    }
    let recorded = match std::fs::read_to_string(&golden_path) {
        Ok(recorded) => recorded,
        Err(error) => panic!(
            "build-fonts golden unreadable at {}: {error}; record it with \
             TIQIAN_UPDATE_GOLDEN=1 cargo test --test build_fonts_parity",
            golden_path.display()
        ),
    };
    let recorded_lines: Vec<&str> = recorded.trim().lines().collect();
    if recorded_lines.len() != rust_lines.len() {
        panic!(
            "line count differs: golden {} rust {}",
            recorded_lines.len(),
            rust_lines.len()
        );
    }
    let mut failed = false;
    for (golden_line, rust_line) in recorded_lines.iter().zip(rust_lines.iter()) {
        if golden_line == rust_line {
            continue;
        }
        failed = true;
        eprintln!("golden: {golden_line}\nrust:   {rust_line}");
    }
    if failed {
        panic!("build-font stylesheet dump differs from the frozen oracle dump");
    }
}

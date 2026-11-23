//! The vendored font fixture shared by the session-layout, precomputer-parity
//! and submission-parity tests.
//!
//! `precomputer_parity.rs` compares entry bytes against a dump produced by the
//! js oracle over this exact file. `font_record.rs` derives `sourceSha256` and
//! `sfntSha256` from the supplied bytes, and the expected dump pins
//! `57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e`, so a
//! synthesized face cannot satisfy the comparison.
//!
//! The file is Dela Gothic One Regular, licensed under the SIL Open Font
//! License 1.1; the license text is `fixtures/OFL.txt`. `include_bytes!` makes
//! the file a compile-time dependency, so a checkout without the fixture fails
//! to build the tests instead of skipping them.

/// Dela Gothic One Regular, the face the js oracle dump was generated over.
pub const DELA_GOTHIC_ONE: &[u8] = include_bytes!("../fixtures/DelaGothicOne-Regular.ttf");

/// The family name every test registers the fixture under.
pub const FAMILY: &str = "Dela Gothic One";

/// The public URL every test registers the fixture under.
pub const PUBLIC_URL: &str = "/fonts/DelaGothicOne-Regular.ttf";

//! Font session and precompute orchestration in Rust (ADR 0050).
//!
//! The Kotlin/JS implementation stays the parity oracle; the font session
//! (HarfBuzz, WOFF2, face selection), the wire orchestration and the two cache
//! lanes land slice by slice.

pub use tiqian::NamedError;

pub mod base_table;
pub mod build_fonts;
pub mod cache;
pub mod canonical;
pub mod context;
pub mod emit;
pub mod engine_bridge;
pub mod font_contract;
pub mod font_face;
pub mod font_record;
pub mod font_record_cache;
pub mod font_source;
pub mod js_compat;
pub mod json;
pub mod metrics;
pub mod name_language;
pub mod name_table;
pub mod normalize;
mod numeric;
pub mod paragraph;
pub mod parallel;
pub mod plan;
pub mod plan_packed;
pub mod policy;
pub mod precompute_html;
pub mod precomputer;
pub mod renderer;
pub mod replay;
pub mod schema;
pub mod selection;
pub mod session;
pub mod sfnt;
pub mod shaping;
pub mod snapshot_bundle;
pub mod snapshot_manifest;
pub mod snapshot_source;
pub mod snapshot_table_binary;
pub mod snapshot_tables;
pub mod source_boundaries;
pub mod submission;
pub mod unicode_tables;

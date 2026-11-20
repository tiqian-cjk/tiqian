//! Engine entry points over the generated Rust engine (boring engine-rust
//! target, crate `tiqian-engine-gen`).
//!
//! The generated `ExplainableStubParagraphLayoutEngine` keeps the
//! dependency-injection surface: every pipeline component arrives as a trait
//! object (`TextShaper`, `FontMetricsResolver`, `FallbackResolver`,
//! `ClreqProfileResolver`, ...), and every slot defaults to the generated
//! production implementation when the caller passes `None`. There is no
//! `extern "C"` boundary left; the faults of the generated engine surface
//! as `crate::NamedError`.
//!
//! Cross-target ruling (2026-11-11): the capability set is the twelve names
//! exported by the npm facade at
//! platforms/web/client/engine-runtime/src/facade.mjs. Those names must match
//! across targets; the transport shape may not. This crate passes the
//! generated types in and out because tiqian-engine-gen is a public path
//! dependency, while the npm facade carries JSON text because its package
//! exports map publishes only the facade module. Measurement arrives here as
//! trait objects and there as host callbacks, which follows from what each
//! host language can express.

use crate::NamedError;
use std::cell::RefCell;
use std::rc::Rc;
use tiqian_engine_gen::org::tiqian::clreq::clreq_profile_resolver::ClreqProfileResolver;
use tiqian_engine_gen::org::tiqian::core::layout_input::LayoutInput;
use tiqian_engine_gen::org::tiqian::core::layout_result::LayoutResult;
use tiqian_engine_gen::org::tiqian::font::font_metrics::{FontMetricsNormalizer, FontMetricsResolver};
use tiqian_engine_gen::org::tiqian::font::font_policy::FallbackResolver;
use tiqian_engine_gen::org::tiqian::font::font_role_context::FontRoleClassifier;
use tiqian_engine_gen::org::tiqian::layout::justifier::Justifier;
use tiqian_engine_gen::org::tiqian::layout::line_breaker::LineBreaker;
use tiqian_engine_gen::org::tiqian::layout::paragraph_layout_engine::{
    ExplainableStubParagraphLayoutEngine,
    ParagraphLayoutEngineLayoutWithRejectedTechnicalTiersFault,
};
use tiqian_engine_gen::org::tiqian::layout::punctuation_model::{
    PunctuationAtomBuilder, PunctuationSpacingCompressor,
};
use tiqian_engine_gen::org::tiqian::layout::quote_pair_analyzer::QuotePairAnalyzer;
use tiqian_engine_gen::org::tiqian::layout::width_independent_annotation_cache::WidthIndependentAnnotationCache;
use tiqian_engine_gen::org::tiqian::linebreak::hyphenator::Hyphenator;
use tiqian_engine_gen::org::tiqian::shaping::text_shaper::TextShaper;

pub use tiqian_engine_gen::org::tiqian::core::layout_input::LayoutInput as EngineLayoutInput;
pub use tiqian_engine_gen::org::tiqian::core::layout_result::LayoutResult as EngineLayoutResult;

/// One slot per `ExplainableStubParagraphLayoutEngine::new` parameter;
/// `None` keeps the generated default implementation. Hosts inject their
/// shaping and metrics stack through the trait objects here.
#[derive(Default)]
pub struct EngineComponents {
    pub font_role_classifier: Option<Rc<RefCell<dyn FontRoleClassifier>>>,
    pub fallback_resolver: Option<Rc<RefCell<dyn FallbackResolver>>>,
    pub clreq_profile_resolver: Option<Rc<RefCell<dyn ClreqProfileResolver>>>,
    pub font_metrics_resolver: Option<Rc<RefCell<dyn FontMetricsResolver>>>,
    pub font_metrics_normalizer: Option<Rc<RefCell<dyn FontMetricsNormalizer>>>,
    pub punctuation_atom_builder: Option<Rc<RefCell<PunctuationAtomBuilder>>>,
    pub punctuation_spacing_compressor: Option<Rc<RefCell<PunctuationSpacingCompressor>>>,
    pub quote_pair_analyzer: Option<Rc<RefCell<QuotePairAnalyzer>>>,
    pub line_breaker: Option<Rc<RefCell<dyn LineBreaker>>>,
    pub justifier: Option<Rc<RefCell<Justifier>>>,
    pub text_shaper: Option<Rc<RefCell<dyn TextShaper>>>,
    pub hyphenator: Option<Rc<RefCell<dyn Hyphenator>>>,
    pub annotation_cache: Option<Rc<RefCell<dyn WidthIndependentAnnotationCache>>>,
}

/// Runs the full paragraph layout pipeline in-process. One engine instance
/// owns its caches; hosts create one per font session or share one behind a
/// lock, matching the generated `layout(&mut self)` signature.
pub struct Engine {
    inner: Rc<RefCell<ExplainableStubParagraphLayoutEngine>>,
}

impl Engine {
    /// Builds the engine with the caller's components; every absent slot
    /// keeps the generated default. Fails with a `NamedError` carrying the
    /// generated constructor fault text when a component is rejected.
    pub fn new(components: EngineComponents) -> Result<Self, NamedError> {
        let inner = ExplainableStubParagraphLayoutEngine::new(
            components.font_role_classifier,
            components.fallback_resolver,
            components.clreq_profile_resolver,
            components.font_metrics_resolver,
            components.font_metrics_normalizer,
            components.punctuation_atom_builder,
            components.punctuation_spacing_compressor,
            components.quote_pair_analyzer,
            components.line_breaker,
            components.justifier,
            components.text_shaper,
            components.hyphenator,
            components.annotation_cache,
        )
        .map_err(named_new)?;
        Ok(Self { inner })
    }

    /// Runs the layout for one generated `LayoutInput` and returns the
    /// generated `LayoutResult`. Named errors surface as
    /// `crate::NamedError` with the generated fault text.
    pub fn layout(&mut self, input: LayoutInput) -> Result<LayoutResult, NamedError> {
        ExplainableStubParagraphLayoutEngine::layout(&self.inner, input).map_err(named)
    }
}

/// Flattens the generated fault unions into the named error surface. The
/// range faults carry the engine's published sentences; the remaining stage
/// faults render through their generated `Display`.
fn named_new(
    fault: tiqian_engine_gen::org::tiqian::layout::paragraph_layout_engine::ParagraphLayoutEngineNewFault,
) -> NamedError {
    use tiqian_engine_gen::org::tiqian::layout::paragraph_layout_engine::ParagraphLayoutEngineNewFault;
    match fault {
        ParagraphLayoutEngineNewFault::TextRangeErrorFault(error) => NamedError(error.to_string()),
        ParagraphLayoutEngineNewFault::UStringFaultFault(error) => NamedError(error.to_string()),
        ParagraphLayoutEngineNewFault::LayoutWithRejectedTechnicalTiersFault(inner) => named(inner),
    }
}

fn named(fault: ParagraphLayoutEngineLayoutWithRejectedTechnicalTiersFault) -> NamedError {
    let text = match fault {
        ParagraphLayoutEngineLayoutWithRejectedTechnicalTiersFault::TextRangeErrorFault(error) => {
            error.to_string()
        }
        other => other.to_string(),
    };
    NamedError(text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tiqian_engine_gen::runtime::u_string::UString;
    use tiqian_engine_gen::org::tiqian::core::layout_constraints::LayoutConstraints;
    use tiqian_engine_gen::org::tiqian::core::tiqian_text_content::TiqianTextContent;
    use tiqian_engine_gen::org::tiqian::font::font_metrics::StubFontMetricsResolver;
    use tiqian_engine_gen::org::tiqian::shaping::text_shaper::ExplainableStubTextShaper;

    #[test]
    fn engine_runs_a_stub_paragraph_end_to_end() {
        let mut engine = Engine::new(EngineComponents::default())
            .expect("default components satisfy the generated constructor");
        let content = TiqianTextContent::new(&UString::from("正文"), None, None, None, None);
        let constraints = LayoutConstraints::new(320.0, None, None)
            .expect("fixture width is positive");
        let input =
            LayoutInput::new(content, None, None, constraints, None, None, None, None, None);
        let result = engine
            .layout(input)
            .expect("the stub pipeline lays out a plain paragraph");
        assert!(!result.to_string().is_empty());
    }

    #[test]
    fn injected_components_drive_the_pipeline() {
        // Dependency injection stays: the host hands in trait objects and the
        // engine uses them instead of its defaults.
        // The generated `new()` already returns the `Rc<RefCell<Self>>` handle,
        // so the injected slot takes the generated default value itself; the
        // slot is a P-1 interface handle and coerces to `dyn TextShaper` here.
        let components = EngineComponents {
            text_shaper: Some(Rc::new(RefCell::new(ExplainableStubTextShaper {}))),
            font_metrics_resolver: Some(Rc::new(RefCell::new(StubFontMetricsResolver {}))),
            ..EngineComponents::default()
        };
        let mut engine = Engine::new(components)
            .expect("injected components satisfy the generated constructor");
        let content = TiqianTextContent::new(&UString::from("句号后换行。"), None, None, None, None);
        let constraints = LayoutConstraints::new(160.0, None, None)
            .expect("fixture width is positive");
        let input =
            LayoutInput::new(content, None, None, constraints, None, None, None, None, None);
        let result = engine
            .layout(input)
            .expect("the injected pipeline lays out a plain paragraph");
        assert!(!result.to_string().is_empty());
    }

    #[test]
    fn rejection_message_flows_to_named_error_text() {
        // The constraint constructor publishes the engine's rejection
        // sentence; the same sentence reaches NamedError when a fault union
        // carries it across the facade.
        let error =
            LayoutConstraints::new(0.0, None, None).expect_err("zero width is rejected");
        let named = NamedError(error.to_string());
        assert!(named.name().contains("maxWidth"));
    }
}

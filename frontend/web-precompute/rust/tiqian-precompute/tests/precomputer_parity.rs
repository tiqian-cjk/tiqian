//! Precomputer parity against the js oracle (ADR 0050 amendment
//! `PrecomputeInRust`). The oracle is `createPrecomputer` from
//! `frontend/web/npm/precompute.js` over the fixture font; every case dumps
//! `stableStringify(entry)` (or `ERROR:<message>` for throws). The one exempt
//! engine-identity field, `fontEvidence.harfbuzzVersion`, is aligned before
//! the byte comparison. The engine archive must be linked.

#![cfg(tiqian_engine_link)]

use std::path::PathBuf;

use tiqian_precompute::font_record::{FontFaceSpec, FontWeightSpec};
use tiqian_precompute::json::{parse_json, Json};
use tiqian_precompute::normalize::TypographyInput;
use tiqian_precompute::precomputer::{
    create_precomputer, Precomputer, PrecomputerOptions, PrepareInput,
};
use tiqian_precompute::schema::stable_stringify;
use tiqian_precompute::session::SessionFaceSpec;

const PLAIN: &str = r###"{"fontEvidence":{"backendRevision":"tiqian-shared-harfbuzz-v5","faces":[{"axes":{},"coverageText":"中文字排版段落","faceIndex":0,"family":"Dela Gothic One","localNames":["Dela Gothic One","Dela Gothic One Regular","DelaGothicOne-Regular"],"probe":{"advancePx":18,"features":[],"fontSizePx":18,"fontWeight":400,"italic":false,"language":"zh-Hans","script":"Hani","text":"中"},"publicUrl":"/fonts/DelaGothicOne-Regular.ttf","sfntSha256":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e","sourceOrder":0,"sourceSha256":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e","style":"normal","unicodeRange":"","weight":[400,400]}],"harfbuzzVersion":"14.2.1","replay":{"metrics":[{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"中\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"文\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"字\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"排\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"版\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"段\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"落\"]","valuesEm":[1.16,0.288,0,0.88,0.12]}],"revision":"tiqian-server-shaping-replay-v1","shapes":[{"key":"[\"中\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"中\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.045,-0.772,0.955,-0.009],"id":687,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"文\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"文\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.002,-0.766,0.998,0.007],"id":3099,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"字\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"字\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.019,-0.761,0.981,0],"id":2006,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"排\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"排\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.01,-0.762,0.97,0.001],"id":2927,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"版\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"版\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[-0.011,-0.746,0.984,0.008],"id":4392,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"段\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"段\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[-0.012,-0.782,0.989,0.002],"id":3793,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"落\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"落\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[-0.007,-0.766,0.995,0.003],"id":6106,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}}]}},"html":"<span aria-hidden=\"true\" class=\"tq-line\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-line-baseline=\"20.34000015258789\" data-tq-line-bottom=\"27\" data-tq-line-empty=\"false\" data-tq-line-end=\"ParagraphEnd\" data-tq-line-flow-width=\"144\" data-tq-line-index=\"0\" data-tq-line-range=\"0-8\" data-tq-line-top=\"0\" data-tq-line-width=\"144\" data-tq-paragraph-height=\"27\" style=\"--tq-line-height:27px!important;--tq-line-baseline-offset:-6.66px!important\"></span>中文文字排版段落<span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-line-end-sentinel=\"0\"></span><span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-selection-end=\"true\">​</span>","inlineBoxes":[],"key":"p-1","layoutRevision":"tiqian-layout-v2","maxWidthPx":144,"plan":{"height":27,"layoutRevision":"tiqian-layout-v2","lines":[{"baseline":20.34000015258789,"bottom":27,"cells":[{"display":"中","drawX":0,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":1,"rangeStart":0,"source":"中"},{"display":"文","drawX":18,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":2,"rangeStart":1,"source":"文"},{"display":"文","drawX":36,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":3,"rangeStart":2,"source":"文"},{"display":"字","drawX":54,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":4,"rangeStart":3,"source":"字"},{"display":"排","drawX":72,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":5,"rangeStart":4,"source":"排"},{"display":"版","drawX":90,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":6,"rangeStart":5,"source":"版"},{"display":"段","drawX":108,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":7,"rangeStart":6,"source":"段"},{"display":"落","drawX":126,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":8,"rangeStart":7,"source":"落"}],"endReason":"ParagraphEnd","hyphenAdvance":0,"indent":0,"rangeEnd":8,"rangeStart":0,"top":0,"visualWidth":144}],"schema":1,"width":144},"renderArtifactSha256":"c86c3d3d7f04009c1112dcb570bc9da44ab83c0cd6333eb61e57bf32a4a50309","renderFontFamilies":["Dela Gothic One"],"renderRevision":"prebroken-dom-v15","renderTextSpans":[],"schema":1,"semantics":[],"sourceArtifactSha256":"f1015057712fc9f0bb7b995ff762487c09ea1f862276eeb7e8f12eaec7a334ed","sourceSha256":"0c7e87425d578e2ffb6cb9b99a33d02a9d99492ddb9d19d921f9ff41b9fe219e","sourceText":"中文文字排版段落","status":"prepared","typography":{"firstLineIndentIc":0,"fontFamilies":["Dela Gothic One"],"fontFeatureSettings":"normal","fontSizePx":18,"fontVariantNumeric":"normal","fontVariationSettings":"normal","fontWeight":400,"italic":false,"letterSpacingPx":0,"lineHeightPx":27,"lineLengthGridEnabled":true,"locale":"zh-Hans"},"typographySha256":"3dbf954fd4061f87e45bb71481ad584474d51db8c9052f49b1fae99de8c76998"}"###;
const PLAIN_INPUT: &str = "{\"key\":\"p-1\",\"text\":\"中文文字排版段落\",\"maxWidthPx\":144}";
const SEMANTIC: &str = r###"{"fontEvidence":{"backendRevision":"tiqian-shared-harfbuzz-v5","faces":[{"axes":{},"coverageText":"中文字排版段落","faceIndex":0,"family":"Dela Gothic One","localNames":["Dela Gothic One","Dela Gothic One Regular","DelaGothicOne-Regular"],"probe":{"advancePx":18,"features":[],"fontSizePx":18,"fontWeight":400,"italic":false,"language":"zh-Hans","script":"Hani","text":"中"},"publicUrl":"/fonts/DelaGothicOne-Regular.ttf","sfntSha256":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e","sourceOrder":0,"sourceSha256":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e","style":"normal","unicodeRange":"","weight":[400,400]}],"harfbuzzVersion":"14.2.1","replay":{"metrics":[{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"中\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"文\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"字\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"排\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"版\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"段\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"落\"]","valuesEm":[1.16,0.288,0,0.88,0.12]}],"revision":"tiqian-server-shaping-replay-v1","shapes":[{"key":"[\"中\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"中\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.045,-0.772,0.955,-0.009],"id":687,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"文\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"文\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.002,-0.766,0.998,0.007],"id":3099,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"字\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"字\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.019,-0.761,0.981,0],"id":2006,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"排\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"排\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.01,-0.762,0.97,0.001],"id":2927,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"版\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"版\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[-0.011,-0.746,0.984,0.008],"id":4392,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"段\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"段\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[-0.012,-0.782,0.989,0.002],"id":3793,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"落\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"落\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[-0.007,-0.766,0.995,0.003],"id":6106,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}}]}},"html":"<span aria-hidden=\"true\" class=\"tq-line\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-line-baseline=\"20.34000015258789\" data-tq-line-bottom=\"27\" data-tq-line-empty=\"false\" data-tq-line-end=\"ParagraphEnd\" data-tq-line-flow-width=\"144\" data-tq-line-index=\"0\" data-tq-line-range=\"0-8\" data-tq-line-top=\"0\" data-tq-line-width=\"144\" data-tq-paragraph-height=\"27\" style=\"--tq-line-height:27px!important;--tq-line-baseline-offset:-6.66px!important\"></span>中文<a data-tq-source-semantic=\"true\" href=\"https://example.com\">文字</a>排版段落<span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-line-end-sentinel=\"0\"></span><span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-selection-end=\"true\">​</span>","inlineBoxes":[],"key":"p-2","layoutRevision":"tiqian-layout-v2","maxWidthPx":144,"plan":{"height":27,"layoutRevision":"tiqian-layout-v2","lines":[{"baseline":20.34000015258789,"bottom":27,"cells":[{"display":"中","drawX":0,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":1,"rangeStart":0,"source":"中"},{"display":"文","drawX":18,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":2,"rangeStart":1,"source":"文"},{"display":"文","drawX":36,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":3,"rangeStart":2,"source":"文"},{"display":"字","drawX":54,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":4,"rangeStart":3,"source":"字"},{"display":"排","drawX":72,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":5,"rangeStart":4,"source":"排"},{"display":"版","drawX":90,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":6,"rangeStart":5,"source":"版"},{"display":"段","drawX":108,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":7,"rangeStart":6,"source":"段"},{"display":"落","drawX":126,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":8,"rangeStart":7,"source":"落"}],"endReason":"ParagraphEnd","hyphenAdvance":0,"indent":0,"rangeEnd":8,"rangeStart":0,"top":0,"visualWidth":144}],"schema":1,"width":144},"renderArtifactSha256":"ba799f7b7024019a5b496c2948ed8a09ed7006afcafdab962ad085ed6077e232","renderFontFamilies":["Dela Gothic One"],"renderRevision":"prebroken-dom-v15","renderTextSpans":[],"schema":1,"semantics":[{"attributes":[["href","https://example.com"]],"end":4,"start":2,"tagName":"a"}],"sourceArtifactSha256":"82926fcb4bcfee3a27c6ce024cccca7810c935b7ab351bdc45788b5ac12cf6ca","sourceSha256":"0c7e87425d578e2ffb6cb9b99a33d02a9d99492ddb9d19d921f9ff41b9fe219e","sourceText":"中文文字排版段落","status":"prepared","typography":{"firstLineIndentIc":0,"fontFamilies":["Dela Gothic One"],"fontFeatureSettings":"normal","fontSizePx":18,"fontVariantNumeric":"normal","fontVariationSettings":"normal","fontWeight":400,"italic":false,"letterSpacingPx":0,"lineHeightPx":27,"lineLengthGridEnabled":true,"locale":"zh-Hans"},"typographySha256":"3dbf954fd4061f87e45bb71481ad584474d51db8c9052f49b1fae99de8c76998"}"###;
const SEMANTIC_INPUT: &str = "{\"key\":\"p-2\",\"text\":\"中文文字排版段落\",\"maxWidthPx\":144,\"semantics\":[{\"tagName\":\"a\",\"start\":2,\"end\":4,\"attributes\":{\"href\":\"https://example.com\"}}]}";
const CONTRACT: &str = r###"{"fontEvidence":{"backendRevision":"tiqian-shared-harfbuzz-v5","faces":[{"axes":{},"coverageText":"中文排版","faceIndex":0,"family":"Dela Gothic One","localNames":["Dela Gothic One","Dela Gothic One Regular","DelaGothicOne-Regular"],"probe":{"advancePx":16,"features":[],"fontSizePx":16,"fontWeight":400,"italic":false,"language":"zh-Hans","script":"Hani","text":"中"},"publicUrl":"/fonts/DelaGothicOne-Regular.ttf","sfntSha256":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e","sourceOrder":0,"sourceSha256":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e","style":"normal","unicodeRange":"","weight":[400,400]}],"harfbuzzVersion":"14.2.1","replay":{"metrics":[{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"中\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"文\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"排\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"版\"]","valuesEm":[1.16,0.288,0,0.88,0.12]}],"revision":"tiqian-server-shaping-replay-v1","shapes":[{"key":"[\"中\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"中\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.045,-0.772,0.955,-0.009],"id":687,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"文\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"文\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.002,-0.766,0.998,0.007],"id":3099,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"排\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"排\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.01,-0.762,0.97,0.001],"id":2927,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"版\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"版\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[-0.011,-0.746,0.984,0.008],"id":4392,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}}]}},"html":"<span aria-hidden=\"true\" class=\"tq-line\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-line-baseline=\"20.34000015258789\" data-tq-line-bottom=\"27\" data-tq-line-empty=\"false\" data-tq-line-end=\"ParagraphEnd\" data-tq-line-flow-width=\"74\" data-tq-line-index=\"0\" data-tq-line-range=\"0-4\" data-tq-line-top=\"0\" data-tq-line-width=\"74\" data-tq-paragraph-height=\"27\" style=\"--tq-line-height:27px!important;--tq-line-baseline-offset:-6.66px!important\"></span><code data-tq-source-semantic=\"true\">中文</code>排版<span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-line-end-sentinel=\"0\"></span><span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-selection-end=\"true\">​</span>","inlineBoxes":[{"end":2,"inlineEndPx":2,"inlineStartPx":4,"outerSpacing":"Source","start":0}],"key":"p-3","layoutRevision":"tiqian-layout-v2","maxWidthPx":120,"plan":{"height":27,"layoutRevision":"tiqian-layout-v2","lines":[{"baseline":20.34000015258789,"bottom":27,"cells":[{"display":"中","drawX":4,"leadingLayoutAdvance":4,"naturalWidth":16,"rangeEnd":1,"rangeStart":0,"source":"中"},{"display":"文","drawX":20,"leadingLayoutAdvance":0,"naturalWidth":16,"rangeEnd":2,"rangeStart":1,"source":"文"},{"display":"排","drawX":38,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":3,"rangeStart":2,"source":"排"},{"display":"版","drawX":56,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":4,"rangeStart":3,"source":"版"}],"endReason":"ParagraphEnd","hyphenAdvance":0,"indent":0,"rangeEnd":4,"rangeStart":0,"top":0,"visualWidth":74}],"schema":1,"width":120},"renderArtifactSha256":"2705e96865a7c93d2c91a1c65f1e8e08dde6b6423a3325c42bc3a7e8f57053d0","renderFontFamilies":["Dela Gothic One"],"renderRevision":"prebroken-dom-v15","renderTextSpans":[],"schema":1,"semantics":[{"attributes":[],"end":2,"start":0,"tagName":"code"}],"sourceArtifactSha256":"00ea8fb875a97f476808e684fd1ee150ecc750f61a272611401663e5326dd308","sourceSha256":"fa9dcc81c6f2f5098ebe7991079db161dbb13e78fbae4b8393a4b23c2b8aa6ec","sourceText":"中文排版","status":"prepared","typography":{"firstLineIndentIc":0,"fontFamilies":["Dela Gothic One"],"fontFeatureSettings":"normal","fontSizePx":18,"fontVariantNumeric":"normal","fontVariationSettings":"normal","fontWeight":400,"italic":false,"letterSpacingPx":0,"lineHeightPx":27,"lineLengthGridEnabled":true,"locale":"zh-Hans"},"typographySha256":"3dbf954fd4061f87e45bb71481ad584474d51db8c9052f49b1fae99de8c76998"}"###;
const CONTRACT_INPUT: &str = "{\"key\":\"p-3\",\"text\":\"中文排版\",\"maxWidthPx\":120,\"semantics\":[{\"tagName\":\"code\",\"start\":0,\"end\":2}],\"textSpans\":[{\"start\":0,\"end\":2,\"fontFamilies\":[\"Dela Gothic One\"],\"fontSizePx\":16,\"fontWeight\":400,\"italic\":false,\"baselineShiftPx\":0}],\"inlineBoxes\":[{\"start\":0,\"end\":2,\"inlineStartPx\":4,\"inlineEndPx\":2,\"outerSpacing\":\"Source\"}],\"sourceBoundaries\":[1]}";
const EMOJI: &str =
    r###"{"issue":"UnsupportedEmojiFallback","key":"p-4","status":"unsupported"}"###;
const EMOJI_INPUT: &str = "{\"key\":\"p-4\",\"text\":\"中🦀文\",\"maxWidthPx\":144}";
const BAD_SEMANTIC: &str = r###"{"detail":"UnsupportedSnapshotSemanticTag:ruby","issue":"UnsupportedSnapshotSemanticTag","key":"p-5","status":"unsupported"}"###;
const BAD_SEMANTIC_INPUT: &str = "{\"key\":\"p-5\",\"text\":\"中文\",\"maxWidthPx\":144,\"semantics\":[{\"tagName\":\"ruby\",\"start\":0,\"end\":2}]}";
const METRIC_ISSUE: &str =
    r###"{"issue":"InlineCodeFontContractUnavailable","key":"p-6","status":"unsupported"}"###;
const METRIC_ISSUE_INPUT: &str = "{\"key\":\"p-6\",\"text\":\"中文\",\"maxWidthPx\":144,\"semantics\":[{\"tagName\":\"code\",\"start\":0,\"end\":2}]}";
const BAD_MEASURE: &str = r###"ERROR:InvalidMaximumMeasure"###;
const BAD_MEASURE_INPUT: &str = "{\"key\":\"p-7\",\"text\":\"中文\",\"maxWidthPx\":0}";
const MISSING_KEY: &str = r###"ERROR:MissingSnapshotKey"###;
const MISSING_KEY_INPUT: &str = "{\"text\":\"中文\",\"maxWidthPx\":144}";
const FONT_CONTRACT: &str = r###"{"fontEvidence":{"backendRevision":"tiqian-shared-harfbuzz-v5","faces":[{"axes":{},"coverageText":"中文合同段落","faceIndex":0,"family":"Dela Gothic One","localNames":["Dela Gothic One","Dela Gothic One Regular","DelaGothicOne-Regular"],"probe":{"advancePx":18,"features":[],"fontSizePx":18,"fontWeight":400,"italic":false,"language":"zh-Hans","script":"Hani","text":"中"},"publicUrl":"/fonts/DelaGothicOne-Regular.ttf","sfntSha256":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e","sourceOrder":0,"sourceSha256":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e","style":"normal","unicodeRange":"","weight":[400,400]}],"harfbuzzVersion":"14.2.1","replay":{"metrics":[{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"中\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"文\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"合\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"同\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"段\"]","valuesEm":[1.16,0.288,0,0.88,0.12]},{"key":"[\"Dela Gothic One\",400,false,\"CjkText\",\"落\"]","valuesEm":[1.16,0.288,0,0.88,0.12]}],"revision":"tiqian-server-shaping-replay-v1","shapes":[{"key":"[\"中\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"中\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.045,-0.772,0.955,-0.009],"id":687,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"文\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"文\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.002,-0.766,0.998,0.007],"id":3099,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"合\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"合\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.012,-0.77,0.993,-0.001],"id":1382,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"同\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"同\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.052,-0.751,0.953,-0.001],"id":1386,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"段\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"段\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[-0.012,-0.782,0.989,0.002],"id":3793,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"落\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkText\",\"落\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[-0.007,-0.766,0.995,0.003],"id":6106,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}}]}},"html":"<span aria-hidden=\"true\" class=\"tq-line\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-line-baseline=\"20.34000015258789\" data-tq-line-bottom=\"27\" data-tq-line-empty=\"false\" data-tq-line-end=\"ParagraphEnd\" data-tq-line-flow-width=\"108\" data-tq-line-index=\"0\" data-tq-line-range=\"0-6\" data-tq-line-top=\"0\" data-tq-line-width=\"108\" data-tq-paragraph-height=\"27\" style=\"--tq-line-height:27px!important;--tq-line-baseline-offset:-6.66px!important\"></span>中文合同段落<span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-line-end-sentinel=\"0\"></span><span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-selection-end=\"true\">​</span>","inlineBoxes":[],"key":"fc-1","layoutRevision":"tiqian-layout-v2","maxWidthPx":216,"plan":{"height":27,"layoutRevision":"tiqian-layout-v2","lines":[{"baseline":20.34000015258789,"bottom":27,"cells":[{"display":"中","drawX":0,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":1,"rangeStart":0,"source":"中"},{"display":"文","drawX":18,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":2,"rangeStart":1,"source":"文"},{"display":"合","drawX":36,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":3,"rangeStart":2,"source":"合"},{"display":"同","drawX":54,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":4,"rangeStart":3,"source":"同"},{"display":"段","drawX":72,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":5,"rangeStart":4,"source":"段"},{"display":"落","drawX":90,"leadingLayoutAdvance":0,"naturalWidth":18,"rangeEnd":6,"rangeStart":5,"source":"落"}],"endReason":"ParagraphEnd","hyphenAdvance":0,"indent":0,"rangeEnd":6,"rangeStart":0,"top":0,"visualWidth":108}],"schema":1,"width":216},"renderArtifactSha256":"21ed94c2d5e89eb2bb21f45f57e992cdb6d79b83d49627d8d3c5bed419c3f0bf","renderFontFamilies":["Dela Gothic One"],"renderRevision":"prebroken-dom-v15","renderTextSpans":[],"schema":1,"semantics":[],"sourceArtifactSha256":"123c39680bafe39fcb6974d1225e38929edbeb183cecb8f94d0b6beda3e7860b","sourceSha256":"07a8bfcbfb6f30f684046f0e42a79ec76239d18504bba6aa05082d7d9cc4d90a","sourceText":"中文合同段落","status":"prepared","typography":{"firstLineIndentIc":0,"fontFamilies":["Dela Gothic One"],"fontFeatureSettings":"normal","fontSizePx":18,"fontVariantNumeric":"normal","fontVariationSettings":"normal","fontWeight":400,"italic":false,"letterSpacingPx":0,"lineHeightPx":27,"lineLengthGridEnabled":true,"locale":"zh-Hans"},"typographySha256":"3dbf954fd4061f87e45bb71481ad584474d51db8c9052f49b1fae99de8c76998"}"###;
const FONT_CONTRACT_INPUT: &str = "{\"key\":\"fc-1\",\"text\":\"中文合同段落\"}";
const FONT_CONTRACT_DASH_RETRY: &str = r###"{"fontEvidence":{"backendRevision":"tiqian-shared-harfbuzz-v5","faces":[{"axes":{},"coverageText":"—","faceIndex":0,"family":"Dela Gothic One","localNames":["Dela Gothic One","Dela Gothic One Regular","DelaGothicOne-Regular"],"probe":{"advancePx":25.595999999999997,"features":[],"fontSizePx":18,"fontWeight":400,"italic":false,"language":"zh-Hans","script":"Hani","text":"——"},"publicUrl":"/fonts/DelaGothicOne-Regular.ttf","sfntSha256":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e","sourceOrder":0,"sourceSha256":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e","style":"normal","unicodeRange":"","weight":[400,400]}],"harfbuzzVersion":"14.2.1","replay":{"metrics":[{"key":"[\"Dela Gothic One\",400,false,\"CjkPunctuation\",\"——\"]","valuesEm":[1.16,0.288,0,0.88,0.12]}],"revision":"tiqian-server-shaping-replay-v1","shapes":[{"key":"[\"⸺\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkPunctuation\",\"——\"]","result":{"advanceEm":1,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":1,"boundsEm":[0.027,-0.742,0.973,0],"id":0,"xEm":0,"yEm":0}],"script":"Hani","unsafeBreakCount":0}},{"key":"[\"——\",\"Dela Gothic One\",400,false,\"zh-Hans\",\"CjkPunctuation\",\"——\"]","result":{"advanceEm":1.422,"faceId":"Dela Gothic One|normal|400-400|57986ebf82ac5b53|0","features":[],"fontInstanceId":"57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e:0:default","glyphs":[{"advanceEm":0.711,"boundsEm":[0.03,-0.438,0.681,-0.243],"id":8896,"xEm":0,"yEm":0},{"advanceEm":0.711,"boundsEm":[0.03,-0.438,0.681,-0.243],"id":8896,"xEm":0.711,"yEm":0}],"script":"Hani","unsafeBreakCount":0}}]}},"html":"<span aria-hidden=\"true\" class=\"tq-line\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-line-baseline=\"20.34000015258789\" data-tq-line-bottom=\"27\" data-tq-line-empty=\"false\" data-tq-line-end=\"ParagraphEnd\" data-tq-line-flow-width=\"36\" data-tq-line-index=\"0\" data-tq-line-range=\"0-2\" data-tq-line-top=\"0\" data-tq-line-width=\"36\" data-tq-paragraph-height=\"27\" style=\"--tq-line-height:27px!important;--tq-line-baseline-offset:-6.66px!important\"></span><span data-tq-advance=\"36\" data-tq-geometry=\"true\" data-tq-shaping-boundary data-tq-x=\"0\">——<span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-spacing-carrier=\"true\" style=\"display:inline-block!important;inline-size:10.404px!important;height:0!important;line-height:0!important;letter-spacing:10.404px!important;overflow:hidden!important;vertical-align:baseline!important;white-space:pre!important\"> </span></span><span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-geometry=\"true\" data-tq-line-end-sentinel=\"0\"></span><span aria-hidden=\"true\" data-tq-copy-ignore=\"true\" data-tq-selection-end=\"true\">​</span>","inlineBoxes":[],"key":"fc-2","layoutRevision":"tiqian-layout-v2","maxWidthPx":72,"plan":{"height":27,"layoutRevision":"tiqian-layout-v2","lines":[{"baseline":20.34000015258789,"bottom":27,"cells":[{"display":"——","drawX":0,"leadingLayoutAdvance":0,"naturalWidth":25.59600067138672,"rangeEnd":2,"rangeStart":0,"shapingBoundary":true,"source":"——"}],"endReason":"ParagraphEnd","hyphenAdvance":0,"indent":0,"rangeEnd":2,"rangeStart":0,"top":0,"visualWidth":36}],"schema":1,"width":72},"renderArtifactSha256":"dd407a663a41b3667417cda6756c8ec5eba0577b08c38e0a5a794b891058c74e","renderFontFamilies":["Dela Gothic One"],"renderRevision":"prebroken-dom-v15","renderTextSpans":[],"schema":1,"semantics":[],"sourceArtifactSha256":"3a2f83383241bda69753faa134c66c1b44d6f09592533d3fba0904b63056d862","sourceSha256":"f3f3079e2ba8b15c942c7f54d01977d94ab8320118a62ace3a88d8c4eaf76bf8","sourceText":"——","status":"prepared","typography":{"firstLineIndentIc":0,"fontFamilies":["Dela Gothic One"],"fontFeatureSettings":"normal","fontSizePx":18,"fontVariantNumeric":"normal","fontVariationSettings":"normal","fontWeight":400,"italic":false,"letterSpacingPx":0,"lineHeightPx":27,"lineLengthGridEnabled":true,"locale":"zh-Hans"},"typographySha256":"3dbf954fd4061f87e45bb71481ad584474d51db8c9052f49b1fae99de8c76998"}"###;
const FONT_CONTRACT_DASH_RETRY_INPUT: &str = "{\"key\":\"fc-2\",\"text\":\"도——문\"}";
const FONT_CONTRACT_NO_DASH_RETRY: &str = r###"{"detail":"NoExactFontFace:families=Dela Gothic One;weight=400;italic=false;text=\"도\"","issue":"NoExactFontFace","key":"fc-3","status":"unsupported"}"###;
const FONT_CONTRACT_NO_DASH_RETRY_INPUT: &str = "{\"key\":\"fc-3\",\"text\":\"도문\"}";

const CASES: &[(&str, &str, bool, &str)] = &[
    ("plain", PLAIN_INPUT, false, PLAIN),
    ("semantic", SEMANTIC_INPUT, false, SEMANTIC),
    ("contract", CONTRACT_INPUT, false, CONTRACT),
    ("emoji", EMOJI_INPUT, false, EMOJI),
    ("bad_semantic", BAD_SEMANTIC_INPUT, false, BAD_SEMANTIC),
    ("metric_issue", METRIC_ISSUE_INPUT, false, METRIC_ISSUE),
    ("bad_measure", BAD_MEASURE_INPUT, false, BAD_MEASURE),
    ("missing_key", MISSING_KEY_INPUT, false, MISSING_KEY),
    ("font_contract", FONT_CONTRACT_INPUT, true, FONT_CONTRACT),
    (
        "font_contract_dash_retry",
        FONT_CONTRACT_DASH_RETRY_INPUT,
        true,
        FONT_CONTRACT_DASH_RETRY,
    ),
    (
        "font_contract_no_dash_retry",
        FONT_CONTRACT_NO_DASH_RETRY_INPUT,
        true,
        FONT_CONTRACT_NO_DASH_RETRY,
    ),
];

fn dela_gothic_path() -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let path = PathBuf::from(home).join(".local/share/fonts/DelaGothicOne-Regular.ttf");
    path.is_file().then_some(path)
}

fn fixture_precomputer() -> Option<Precomputer> {
    let font_path = dela_gothic_path()?;
    let bytes = std::fs::read(font_path).expect("fixture font reads");
    Some(
        create_precomputer(PrecomputerOptions::new(
            TypographyInput {
                font_families: Some(vec!["Dela Gothic One".to_string()]),
                font_size_px: Some(18.0),
                line_height_px: Some(27.0),
                ..Default::default()
            },
            vec![SessionFaceSpec {
                spec: FontFaceSpec {
                    family: "Dela Gothic One",
                    public_url: "/fonts/DelaGothicOne-Regular.ttf",
                    source: &bytes,
                    face_index: None,
                    weight: FontWeightSpec::Single(Some(400.0)),
                    style: "normal",
                    unicode_range: None,
                    source_order: 0,
                },
                source_order: Some(0.0),
            }],
        ))
        .expect("fixture precomputer builds"),
    )
}

fn run(
    precomputer: &mut Precomputer,
    input_json: &str,
    font_contract: bool,
) -> Result<Json, String> {
    let value = parse_json(input_json).expect("case input parses");
    let input = PrepareInput::from_json(&value);
    let result = if font_contract {
        precomputer.prepare_font_contract(&input)
    } else {
        precomputer.prepare_paragraph(&input)
    };
    result.map_err(|error| format!("ERROR:{}", error.0))
}

/// The js evidence reports the wasm HarfBuzz version; the Rust stack names
/// its own. Aligning the field keeps the comparison on the parity-relevant
/// bytes.
fn align_harfbuzz_version(entry: &mut Json, oracle: &Json) {
    let Json::Obj(oracle_fields) = oracle else {
        panic!("oracle entry object");
    };
    let Some((_, Json::Obj(oracle_evidence))) =
        oracle_fields.iter().find(|(key, _)| key == "fontEvidence")
    else {
        return;
    };
    let js_version = oracle_evidence
        .iter()
        .find(|(key, _)| key == "harfbuzzVersion")
        .map(|(_, value)| value.clone())
        .expect("oracle carries harfbuzzVersion");
    let Json::Obj(fields) = entry else {
        panic!("entry object");
    };
    for (name, inner) in fields.iter_mut() {
        if name != "fontEvidence" {
            continue;
        }
        let Json::Obj(evidence) = inner else {
            panic!("evidence object");
        };
        for (evidence_name, evidence_value) in evidence.iter_mut() {
            if evidence_name == "harfbuzzVersion" {
                *evidence_value = js_version.clone();
            }
        }
    }
}

#[test]
fn precomputer_entries_match_the_js_oracle() {
    let Some(mut precomputer) = fixture_precomputer() else {
        eprintln!(
            "skipped: DelaGothicOne-Regular.ttf absent at {}",
            dela_gothic_path()
                .map(|path| path.display().to_string())
                .unwrap_or_default()
        );
        return;
    };
    assert!(precomputer.session_id().starts_with("tq-build-font-"));
    assert_eq!(precomputer.render_font_families(), ["Dela Gothic One"]);

    for (name, input, font_contract, oracle) in CASES {
        let result = run(&mut precomputer, input, *font_contract);
        if let Some(_) = oracle.strip_prefix("ERROR:") {
            assert_eq!(result.err().expect(name), *oracle, "case {name}");
            continue;
        }
        let mut entry = result.expect(name);
        let oracle_value = parse_json(oracle).expect(name);
        align_harfbuzz_version(&mut entry, &oracle_value);
        assert_eq!(stable_stringify(&entry), *oracle, "case {name}");
    }

    precomputer.close();
    let closed = run(&mut precomputer, PLAIN_INPUT, false);
    assert_eq!(closed.unwrap_err(), "ERROR:PrecomputerClosed");
}

#[test]
fn close_is_idempotent() {
    let Some(mut precomputer) = fixture_precomputer() else {
        eprintln!("skipped: fixture font absent");
        return;
    };
    precomputer.close();
    precomputer.close();
    let result = run(&mut precomputer, PLAIN_INPUT, false);
    assert_eq!(result.unwrap_err(), "ERROR:PrecomputerClosed");
}

package org.tiqian.shared.html;

/**
 * The exception class carries the enum instance and its static describe is
 * the message function: the published name of a variant is the variant's own
 * name, matching the napi Error the Rust addon lane produces
 * (platforms/web/server/precompute/engine/src/precompute_calls.rs:
 * inject_html_attributes at L554-561 calls cx.throw_error). No consumer reads
 * the message for identity (features/06:397), so the string of every variant
 * is the published issue name. Mirrors ParagraphRequestException
 * (engine-haxe/src/org/tiqian/protocol/ParagraphRequestException.hx:13-45).
 */
class HtmlParseException extends haxe.Exception {
    public final error:HtmlError;

    public function new(error:HtmlError) {
        this.error = error;
        super(HtmlParseException.describe(error));
    }

    public static function describe(error:HtmlError):String {
        return switch (error) {
            case HtmlOffsetConversion: "HtmlOffsetConversion";
            case InvalidHtmlAttributeInsertionOffset: "InvalidHtmlAttributeInsertionOffset";
            case UnsupportedHtmlAncestorSelector: "UnsupportedHtmlAncestorSelector";
        };
    }
}

package org.tiqian.shared.prepared_dom;

/**
 * The exception renderRun throws for an open-type feature signature that has
 * no replay rule. Carries the failure identity in a final field, mirroring
 * the enum-carrying exception shape of std.UStringException so boring emits
 * an Error subclass with a stable .message built from describe.
 */
class PreparedDomException extends haxe.Exception {
    public final error:PreparedDomError;

    public function new(error:PreparedDomError) {
        this.error = error;
        super(PreparedDomException.describe(error));
    }

    public static function describe(error:PreparedDomError):String {
        return switch (error) {
            case UnsupportedOpenTypeFeatures(signature): "UnsupportedPreparedOpenTypeFeatures: " + signature;
            case InvalidPreparedOverlayGeometry: "InvalidPreparedOverlayGeometry";
            case SnapshotRenderFlowMismatch(detail): "SnapshotRenderFlowMismatch:" + detail;
            case ConflictingPreparedRenderTextSpan: "ConflictingPreparedRenderTextSpan";
        };
    }
}

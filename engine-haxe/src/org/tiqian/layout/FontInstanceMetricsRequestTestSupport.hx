package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.font.FontMetrics.FontMetricsRequest;
import org.tiqian.font.FontMetrics.FontMetricsResolver;
import org.tiqian.font.RawFontMetrics;
import org.tiqian.font.FontMetrics.StubFontMetricsResolver;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class FontInstanceMetricsRequestTestSupport {
    public static var recorded:Array<FontMetricsRequest> = [];

    public static function recordingEngine():ExplainableStubParagraphLayoutEngine {
        recorded = [];
        return new ExplainableStubParagraphLayoutEngine(null, null, null, new RecordingResolver(), null, null, null, null, null, null, null, null,
            null);
    }

    public static function baseStyle():TextStyle {
        return new TextStyle(["Fixture Sans"], 18.0, null, 400, false);
    }
}

class RecordingResolver implements FontMetricsResolver {
    final stub:StubFontMetricsResolver;

    public function new() {
        this.stub = new StubFontMetricsResolver();
    }

    public function resolve(request:FontMetricsRequest):RawFontMetrics {
        final result = stub.resolve(request);
        FontInstanceMetricsRequestTestSupport.recorded.push(request);
        return result;
    }
}

package org.tiqian.layout;

import org.tiqian.core.*;
import org.tiqian.font.FontMetrics.FontMetricsRequest;
import org.tiqian.font.FontMetrics.FontMetricsResolver;
import org.tiqian.font.RawFontMetrics;
import org.tiqian.font.FontMetrics.StubFontMetricsResolver;
import org.tiqian.layout.ParagraphLayoutEngine.ExplainableStubParagraphLayoutEngine;

class FontInstanceMetricsRequestTestSupport {
    public static function recordingEngine(requests:Array<FontMetricsRequest>):ExplainableStubParagraphLayoutEngine {
        return new ExplainableStubParagraphLayoutEngine(null, null, null, new RecordingResolver(requests), null, null, null, null, null, null, null, null,
            null);
    }

    public static function baseStyle():TextStyle {
        return new TextStyle(["Fixture Sans"], 18.0, null, 400, false);
    }
}

class RecordingResolver implements FontMetricsResolver {
    final requests:Array<FontMetricsRequest>;
    final stub:StubFontMetricsResolver;

    public function new(requests:Array<FontMetricsRequest>) {
        this.requests = requests;
        this.stub = new StubFontMetricsResolver();
    }

    public function resolve(request:FontMetricsRequest):RawFontMetrics {
        requests.push(request);
        return stub.resolve(request);
    }
}

package org.tiqian.shaping;

import org.tiqian.font.FontRole;
import org.tiqian.core.TiqianIllegalArgumentException;
import org.tiqian.core.TextRangeError;
import org.tiqian.shaping.ReplayableFontBackend.FontFaceId;
import org.tiqian.shaping.ReplayableFontBackend.ReplayableFontFaceDescriptor;
import org.tiqian.shaping.ReplayableFontBackend.ReplayableFontFaceRequest;
import org.tiqian.shaping.ReplayableFontBackend.FontBackendCapabilityIssue;
import org.tiqian.shaping.ReplayableFontBackend.FontBackendCapabilityReport;
import org.tiqian.shaping.ReplayableFontBackend.ReplayableFontCatalog;
import org.tiqian.test.trace.TestTraceRecorder;
import org.tiqian.test.trace.TracedAssertions;
import std.SortedMap;
import std.SortedSet;

class ReplayableFontBackendCoverageTestSupport {
    public static function strings(values:Array<String>):SortedSet<String> {
        var b = SortedSet.builder();
        for (value in values)
            b.put(value);
        return b.build();
    }

    public static function roles(values:Array<FontRole>):Array<FontRole>
        return values;

    public static function axes(key:String, value:Float):SortedMap<String, Float> {
        var b = SortedMap.builder();
        b.put(key, value);
        return b.build();
    }
}

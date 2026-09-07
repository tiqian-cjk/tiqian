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

class ReplayableFontBackendCoverageTest {
    static function strings(values:Array<String>):SortedSet<String> {
        var b = SortedSet.builder();
        for (value in values)
            b.put(value);
        return b.build();
    }

    static function roles(values:Array<FontRole>):Array<FontRole>
        return values;

    static function axes(key:String, value:Float):SortedMap<String, Float> {
        var b = SortedMap.builder();
        b.put(key, value);
        return b.build();
    }

    public static function fontFaceIdRejectsBlankAndKeepsValue():Void {
        new TestTraceRecorder("ReplayableFontBackendCoverageTest").section("fontFaceIdRejectsBlankAndKeepsValue");
        var id = FontFaceId.of("noto-cjk-1");
        TracedAssertions.assertEqualsString("noto-cjk-1", id.value);
        TracedAssertions.assertEqualsString("noto-cjk-1", id.toString());
        var blank = TracedAssertions.assertFailsWith(null, function() FontFaceId.of(" "));
        TracedAssertions.assertTrue(blank.message.indexOf("blank") >= 0, blank.message);
        TracedAssertions.assertFailsWith(null, function() FontFaceId.of(""));
    }

    public static function faceDescriptorDefaultsAreStable():Void {
        new TestTraceRecorder("ReplayableFontBackendCoverageTest").section("faceDescriptorDefaultsAreStable");
        var descriptor = new ReplayableFontFaceDescriptor(FontFaceId.of("face-a"), strings(["Serif"]), roles([FontRole.CjkText]), "bundled/noto.ttf");
        TracedAssertions.assertEquals(400, descriptor.weight);
        TracedAssertions.assertFalse(descriptor.italic);
        TracedAssertions.assertEquals(0, descriptor.collectionIndex);
        TracedAssertions.assertTrue(descriptor.variationAxes.size() == 0);
        TracedAssertions.assertEqualsRendered("face-a", descriptor.id.toString());
        var varied = new ReplayableFontFaceDescriptor(descriptor.id, descriptor.familyAliases, descriptor.roles, descriptor.sourceLabel, 700, true, 2,
            axes("wght", 700.0));
        TracedAssertions.assertEquals(700, varied.weight);
        TracedAssertions.assertTrue(varied.italic);
        TracedAssertions.assertEquals(2, varied.collectionIndex);
        TracedAssertions.assertEqualsFloat(700.0, varied.variationAxes.get("wght"));
    }

    public static function faceRequestRejectsNonPositiveAndNonFiniteFontSize():Void {
        new TestTraceRecorder("ReplayableFontBackendCoverageTest").section("faceRequestRejectsNonPositiveAndNonFiniteFontSize");
        var request = new ReplayableFontFaceRequest(FontRole.LatinText, ["Plex"], 15.0, 400, false, "zh-CN", "A");
        TracedAssertions.assertEqualsFontRole(FontRole.LatinText, request.role);
        TracedAssertions.assertEqualsFloat(15.0, request.fontSize);
        var error = TracedAssertions.assertFailsWith(null, function() new ReplayableFontFaceRequest(FontRole.LatinText, [], 0.0, 400, false, "", "A"));
        TracedAssertions.assertTrue(error.message.indexOf("positive and finite") >= 0, error.message);
        TracedAssertions.assertFailsWith(null, function() new ReplayableFontFaceRequest(FontRole.LatinText, [], -1.0, 400, false, "", "A"));
        TracedAssertions.assertFailsWith(null, function() new ReplayableFontFaceRequest(FontRole.LatinText, [], Math.NaN, 400, false, "", "A"));
        TracedAssertions.assertFailsWith(null, function() new ReplayableFontFaceRequest(FontRole.LatinText, [], Math.POSITIVE_INFINITY, 400, false, "", "A"));
    }

    public static function capabilityReportReplayFlagRequiresFacesAndNoMissingFaceIssue():Void {
        new TestTraceRecorder("ReplayableFontBackendCoverageTest").section("capabilityReportReplayFlagRequiresFacesAndNoMissingFaceIssue");
        var face = new ReplayableFontFaceDescriptor(FontFaceId.of("face-a"), strings(["Serif"]), roles([FontRole.CjkText]), "bytes");
        TracedAssertions.assertFalse(new FontBackendCapabilityReport("b", "k", []).canReplayFromControlledBytes);
        TracedAssertions.assertFalse(new FontBackendCapabilityReport("b", "k", [face],
            [new FontBackendCapabilityIssue("MissingControlledFontFace", "gone")]).canReplayFromControlledBytes);
        TracedAssertions.assertTrue(new FontBackendCapabilityReport("b", "k", [face],
            [new FontBackendCapabilityIssue("Other", "note")]).canReplayFromControlledBytes);
        TracedAssertions.assertTrue(new FontBackendCapabilityReport("b", "k", [face]).canReplayFromControlledBytes);
    }

    public static function catalogContractResolvesByRequest():Void {
        new TestTraceRecorder("ReplayableFontBackendCoverageTest").section("catalogContractResolvesByRequest");
        var cjkFace = new ReplayableFontFaceDescriptor(FontFaceId.of("face-cjk"), strings(["Noto Serif CJK"]), roles([FontRole.CjkText]), "bytes");
        var latinFace = new ReplayableFontFaceDescriptor(FontFaceId.of("face-latin"), strings(["Plex"]), roles([FontRole.LatinText]), "bytes");
        var catalog:ReplayableFontCatalog = new CatalogImpl([cjkFace, latinFace]);
        TracedAssertions.assertTrue(catalog.capabilityReport.canReplayFromControlledBytes);
        var hit = catalog.resolve(new ReplayableFontFaceRequest(FontRole.LatinText, ["Plex"], 12.0, 400, false, "zh-CN", "A"));
        TracedAssertions.assertEqualsRendered("face-latin", hit == null ? "-" : hit.id.toString());
        var miss = catalog.resolve(new ReplayableFontFaceRequest(FontRole.LatinText, ["Missing"], 12.0, 400, false, "zh-CN", "A"));
        TracedAssertions.assertNullRendered(miss == null, "-");
    }
}

private class CatalogImpl implements ReplayableFontCatalog {
    public var faces(get, never):Array<ReplayableFontFaceDescriptor>;
    public var capabilityReport(get, never):FontBackendCapabilityReport;

    var stored:Array<ReplayableFontFaceDescriptor>;

    public function new(faces:Array<ReplayableFontFaceDescriptor>)
        this.stored = faces;

    function get_faces()
        return stored;

    function get_capabilityReport()
        return new FontBackendCapabilityReport("test", "bytes", stored);

    public function resolve(request:ReplayableFontFaceRequest):Null<ReplayableFontFaceDescriptor> {
        for (face in stored) {
            if (face.roles.indexOf(request.role) >= 0)
                for (family in request.preferredFamilies)
                    if (face.familyAliases.has(family))
                        return face;
        }
        return null;
    }
}

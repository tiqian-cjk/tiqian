package org.tiqian.core;

import std.ReadOnlyArray;

@:dataClass
class LayoutInput {
    public final content:TiqianTextContent;
    public final textStyle:TextStyle;
    public final paragraphStyle:ParagraphStyle;
    public final constraints:LayoutConstraints;
    public final profileId:LayoutProfileId;
    public final decorations:ReadOnlyArray<DecorationSpan>;
    public final rubySpans:ReadOnlyArray<RubySpan>;
    public final inlineBoxes:ReadOnlyArray<InlineBoxSpan>;
    public final inlineObjects:ReadOnlyArray<InlineObjectSpan>;

    public function new(content:TiqianTextContent, ?textStyle:Null<TextStyle>, ?paragraphStyle:Null<ParagraphStyle>, constraints:LayoutConstraints,
            ?profileId:Null<LayoutProfileId>, ?decorations:ReadOnlyArray<DecorationSpan>, ?rubySpans:ReadOnlyArray<RubySpan>,
            ?inlineBoxes:ReadOnlyArray<InlineBoxSpan>, ?inlineObjects:ReadOnlyArray<InlineObjectSpan>) {
        this.content = content;
        this.textStyle = textStyle == null ? new TextStyle() : textStyle;
        this.paragraphStyle = paragraphStyle == null ? new ParagraphStyle() : paragraphStyle;
        this.constraints = constraints;
        this.profileId = profileId == null ? BuiltInLayoutProfiles.ClreqHorizontal : profileId;
        this.decorations = decorations == null ? [] : decorations;
        this.rubySpans = rubySpans == null ? [] : rubySpans;
        this.inlineBoxes = inlineBoxes == null ? [] : inlineBoxes;
        this.inlineObjects = inlineObjects == null ? [] : inlineObjects;
    }
}

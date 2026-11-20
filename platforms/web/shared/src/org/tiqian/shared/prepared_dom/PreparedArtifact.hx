package org.tiqian.shared.prepared_dom;

/**
 * Prepared paragraph artifact lowering (prepared-dom.ts:641-1024), the shared
 * web/TS-only surface behind the prepared DOM snapshot and the browser
 * renderer.
 *
 * Everything that needs the wire form stays in the glue: JSON parsing, schema
 * and revision checks, semantic normalization, live-element validation,
 * render-text-span validation and the final nested-array serialization. This
 * module consumes the already validated typed plan and returns typed markup
 * nodes, so its arithmetic and emitted strings are byte-identical to the TS
 * oracle.
 *
 * The merge pass compares three signature strings per cell. The oracle derives
 * them with JSON.stringify over the parsed wire object; those strings are
 * computed by the glue and carried on the typed cell (see PreparedPlanCell), so
 * no JSON writer is needed here and the comparison stays identical.
 */
@:mainOnly
class PreparedArtifact {

    /**
     * Lowers one prepared plan to the sparse DOM wire (prepared-dom.ts
     * renderPreparedParagraphArtifact, minus the glue-owned validation and
     * serialization).
     */
    public static function renderPreparedParagraphArtifact(plan:PreparedPlan, locale:String, options:PreparedArtifactOptions):PreparedArtifactResult {
        final semantics = options.semantics;
        final renderTextSpans = options.renderTextSpans;
        final emphasisRanges = plan.emphasisRanges;
        final inlineBoxes = inlineBoxesFor(plan.inlineEdges, options.inlineBoxes);
        final state = newArtifactState(options.cjkStrongSemantics, options.liveSource);
        final styleClassFor = options.styleClassFor;
        var inlineObjectCount = 0;
        var lineIndex = 0;
        while (lineIndex < plan.lines.length) {
            final line = plan.lines[lineIndex];
            final height = line.bottom - line.top;
            final first:Null<PreparedPlanCell> = line.cells.length > 0 ? line.cells[0] : null;
            final flowStart = first != null ? first.drawX - first.leadingLayoutAdvance : 0.0;
            final firstInlineStart = first != null ? inlineStartAt(inlineBoxes, first.rangeStart) : 0.0;
            if (first != null && Math.abs(first.leadingLayoutAdvance - firstInlineStart) > PreparedDom.RENDER_FLOW_EPSILON_PX) {
                throw new PreparedDomException(SnapshotRenderFlowMismatch("line=" + lineIndex + ";leading-layout-advance"));
            }
            final cells:Array<PreparedRunTyped> = [];
            var cellIndex = 0;
            while (cellIndex < line.cells.length) {
                final cell = line.cells[cellIndex];
                final next:Null<PreparedPlanCell> = cellIndex + 1 < line.cells.length ? line.cells[cellIndex + 1] : null;
                final trailingInlineEdge = inlineEndAt(inlineBoxes, cell.rangeEnd);
                final nextLeadingInlineEdge = next != null ? inlineStartAt(inlineBoxes, next.rangeStart) : 0.0;
                final rawTrailingGap = next != null
                    ? next.drawX - cell.drawX - cell.naturalWidth - trailingInlineEdge - nextLeadingInlineEdge
                    : line.hyphenAdvance > 0
                        ? 0.0
                        : line.indent + line.visualWidth - cell.drawX - cell.naturalWidth - trailingInlineEdge;
                final layoutTrailingGap = Math.abs(rawTrailingGap) < PreparedDom.SPACING_DUST_EPSILON ? 0.0 : rawTrailingGap;
                final bopomofoHere = bopomofoAt(plan.bopomofoDecisions, cell.rangeEnd);
                final hasBopomofo = bopomofoHere.length > 0;
                final naturalAdvance:Float = cell.advance != null ? cell.advance : cell.naturalWidth;
                final bopomofoAdvanceWidth = !hasBopomofo
                    ? 0.0
                    : next != null
                        ? Math.max(layoutTrailingGap, 0.0)
                        : Math.max(naturalAdvance - cell.naturalWidth - trailingInlineEdge, 0.0);
                final trailingGap = hasBopomofo ? 0.0 : layoutTrailingGap;
                final styleItalic = cell.style != null && cell.style.italic == true;
                final run:PreparedRunTyped = {
                    rangeStart: cell.rangeStart,
                    rangeEnd: cell.rangeEnd,
                    source: cell.source,
                    display: cell.display,
                    drawX: cell.drawX,
                    naturalWidth: cell.naturalWidth,
                    shapingBoundary: cell.shapingBoundary,
                    openTypeFeatures: cell.openTypeFeatures,
                    renderFontFamilies: renderFontFamiliesFor(renderTextSpans, cell.rangeStart, cell.rangeEnd),
                    trailingGap: trailingGap,
                    spacing: PreparedDom.preparedSpacing(cell.display, cell.naturalWidth, trailingGap),
                    semanticPath: semanticsFor(semantics, cell.rangeStart, cell.rangeEnd),
                    styleDelta: cell.style,
                    italicEffect: styleItalic || (cell.latin && rangeContains(emphasisRanges, cell.rangeStart)),
                    dashStrategy: cell.dashStrategy,
                    shapingLanguage: cell.shapingLanguage,
                    resolvedFace: cell.resolvedFace,
                    glyphIds: cell.glyphIds,
                    shapingEvidence: cell.shapingEvidence,
                    punctuationInkFloor: cell.punctuationInkFloor,
                    punctuationBodyWidth: cell.punctuationBodyWidth,
                    evidenceRenderFontFamily: cell.renderFontFamily,
                    inlineObjectAdvance: cell.inlineObject,
                    bopomofoAdvanceWidth: bopomofoAdvanceWidth,
                    styleSignature: cell.styleSignature,
                    punctuationSignature: cell.punctuationSignature,
                    semanticSignature: null
                };
                cells.push(run);
                cellIndex += 1;
            }
            var signatureIndex = 0;
            while (signatureIndex < cells.length) {
                cells[signatureIndex].semanticSignature = pathSignature(cells[signatureIndex].semanticPath);
                signatureIndex += 1;
            }
            final children:Array<PreparedLineChild> = [];
            var pending:Null<PreparedRunTyped> = null;
            var childIndex = 0;
            while (childIndex < cells.length) {
                final cell = cells[childIndex];
                if (cell.inlineObjectAdvance != null) {
                    if (pending != null) {
                        children.push(runChild(pending));
                        pending = null;
                    }
                    children.push(inlineObjectChild(cell));
                    inlineObjectCount += 1;
                    childIndex += 1;
                    continue;
                }
                if (pending != null && PreparedDom.canMergePreparedRun(pending, cell)) {
                    PreparedDom.mergePreparedRun(pending, cell);
                } else {
                    if (pending != null) {
                        children.push(runChild(pending));
                    }
                    pending = cell;
                }
                final rubyAtEnd = rubyAt(plan.rubyDecisions, cell.rangeEnd);
                final bopomofoAtEnd = bopomofoAt(plan.bopomofoDecisions, cell.rangeEnd);
                if (rubyAtEnd != null || bopomofoAtEnd.length > 0) {
                    if (pending != null) {
                        children.push(runChild(pending));
                        pending = null;
                    }
                }
                if (rubyAtEnd != null) {
                    final ruby:PlanRubyAnnotation = rubyAtEnd;
                    children.push(rubyChild(ruby, line.top, cell.semanticPath));
                }
                var zoneIndex = 0;
                while (zoneIndex < bopomofoAtEnd.length) {
                    final zone:PlanBopomofoZone = bopomofoAtEnd[zoneIndex];
                    children.push(bopomofoChild(zone, cell.bopomofoAdvanceWidth, line.top, line.bottom - line.top, cell.semanticPath));
                    zoneIndex += 1;
                }
                childIndex += 1;
            }
            if (pending != null) {
                children.push(runChild(pending));
                pending = null;
            }
            final last:Null<PreparedPlanCell> = line.cells.length > 0 ? line.cells[line.cells.length - 1] : null;
            final flowEnd = last != null ? last.drawX + last.naturalWidth + inlineEndAt(inlineBoxes, last.rangeEnd) : 0.0;
            final hyphenLeadingGap = line.hyphenAdvance > 0 ? line.indent + line.visualWidth - flowEnd : 0.0;
            var inlineEdgeWidth = 0.0;
            var edgeIndex = 0;
            while (edgeIndex < line.cells.length) {
                inlineEdgeWidth += inlineStartAt(inlineBoxes, line.cells[edgeIndex].rangeStart)
                    + inlineEndAt(inlineBoxes, line.cells[edgeIndex].rangeEnd);
                edgeIndex += 1;
            }
            var childFlow = 0.0;
            var flowIndex = 0;
            while (flowIndex < children.length) {
                final child = children[flowIndex];
                if (child.kind == "run") {
                    final run:PreparedRunTyped = child.run;
                    childFlow += run.naturalWidth + run.trailingGap;
                } else if (child.kind == "inlineObject") {
                    final cell:PreparedRunTyped = child.cell;
                    childFlow += cell.naturalWidth
                        + (Math.abs(child.carrierMargin) >= PreparedDom.SPACING_EPSILON ? child.carrierMargin : 0.0);
                } else if (child.kind == "bopomofo") {
                    childFlow += child.width;
                }
                flowIndex += 1;
            }
            final expectedFlowWidth = flowStart + inlineEdgeWidth + childFlow + hyphenLeadingGap + line.hyphenAdvance;
            final coreLineWidth = line.indent + line.visualWidth + line.hyphenAdvance;
            if (Math.abs(expectedFlowWidth - coreLineWidth) > PreparedDom.RENDER_FLOW_EPSILON_PX) {
                throw new PreparedDomException(SnapshotRenderFlowMismatch("line=" + lineIndex));
            }
            final markerStyles:Array<String> = [
                "--tq-line-height:" + Markup.px(height) + "!important",
                "--tq-line-baseline-offset:" + Markup.px(-(line.bottom - line.baseline)) + "!important"
            ];
            if (Math.abs(flowStart) >= PreparedDom.SPACING_EPSILON) {
                markerStyles.push("--tq-line-flow-start:" + Markup.px(flowStart) + "!important");
            }
            final markerAttributes:Array<AttributeEntry> = [];
            Markup.setAttribute(markerAttributes, "aria-hidden", "true");
            Markup.setAttribute(markerAttributes, "class", "tq-line");
            Markup.setAttribute(markerAttributes, "data-tq-copy-ignore", "true");
            Markup.setAttribute(markerAttributes, "data-tq-geometry", "true");
            Markup.setAttribute(markerAttributes, "data-tq-line-empty", "" + (line.cells.length == 0));
            Markup.setAttribute(markerAttributes, "data-tq-line-end", line.endReason);
            Markup.setAttribute(markerAttributes, "data-tq-line-top", "" + line.top);
            Markup.setAttribute(markerAttributes, "data-tq-line-bottom", "" + line.bottom);
            Markup.setAttribute(markerAttributes, "data-tq-line-baseline", "" + line.baseline);
            Markup.setAttribute(markerAttributes, "data-tq-line-flow-width", "" + expectedFlowWidth);
            Markup.setAttribute(markerAttributes, "data-tq-line-index", "" + lineIndex);
            Markup.setAttribute(markerAttributes, "data-tq-line-range", "" + line.rangeStart + "-" + line.rangeEnd);
            if (Math.abs(flowStart) >= PreparedDom.SPACING_EPSILON) {
                Markup.setAttribute(markerAttributes, "data-tq-line-shift", "true");
            }
            Markup.setAttribute(markerAttributes, "data-tq-line-width", "" + coreLineWidth);
            Markup.setAttribute(markerAttributes, "data-tq-paragraph-height", "" + plan.height);
            Markup.applyDynamicStyles(markerAttributes, markerStyles, styleClassFor);
            semanticContainerFor(state, state.activeSemantics).push(Markup.renderedElement("span", markerAttributes, null, false));

            var renderIndex = 0;
            while (renderIndex < children.length) {
                final child = children[renderIndex];
                final container = semanticContainerFor(state, child.semanticPath);
                if (child.kind == "run") {
                    final run:PreparedRunTyped = child.run;
                    container.push(PreparedDom.renderRun(run, styleClassFor));
                } else if (child.kind == "inlineObject") {
                    final cell:PreparedRunTyped = child.cell;
                    container.push(Evidence.inlineObjectPlaceholder(cell, child.carrierMargin, styleClassFor));
                } else if (child.kind == "ruby") {
                    final ruby:PlanRubyAnnotation = child.ruby;
                    container.push(Evidence.rubyAnnotationSpan(ruby, child.lineTop, styleClassFor));
                } else {
                    final zone:PlanBopomofoZone = child.zone;
                    container.push(Evidence.bopomofoAnnotationSpan(zone, child.width, child.lineTop, child.lineHeight, styleClassFor));
                }
                renderIndex += 1;
            }

            if (line.hyphenAdvance > 0) {
                final hyphenAttributes:Array<AttributeEntry> = [];
                Markup.setAttribute(hyphenAttributes, "aria-hidden", "true");
                Markup.setAttribute(hyphenAttributes, "data-tq-advance", "" + line.hyphenAdvance);
                Markup.setAttribute(hyphenAttributes, "data-tq-copy-ignore", "true");
                Markup.setAttribute(hyphenAttributes, "data-tq-engine-hyphen", "true");
                Markup.setAttribute(hyphenAttributes, "data-tq-geometry", "true");
                Markup.setAttribute(hyphenAttributes, "data-tq-x", "" + (line.indent + line.visualWidth));
                Markup.setAttribute(hyphenAttributes, "lang", locale);
                final hyphenStyles:Array<String> = [];
                if (Math.abs(hyphenLeadingGap) >= PreparedDom.SPACING_EPSILON) {
                    hyphenStyles.push("margin-left:" + Markup.px(hyphenLeadingGap) + "!important");
                }
                Markup.applyDynamicStyles(hyphenAttributes, hyphenStyles, styleClassFor);
                semanticContainerFor(state, state.activeSemantics).push(Markup.renderedElement("span", hyphenAttributes, "-", false));
            }
            final boundaryContainer = semanticContainerFor(state, crossingSpans(semantics, line.rangeEnd));
            final sentinelAttributes:Array<AttributeEntry> = [];
            Markup.setAttribute(sentinelAttributes, "aria-hidden", "true");
            Markup.setAttribute(sentinelAttributes, "data-tq-copy-ignore", "true");
            Markup.setAttribute(sentinelAttributes, "data-tq-geometry", "true");
            Markup.setAttribute(sentinelAttributes, "data-tq-line-end-sentinel", "" + lineIndex);
            boundaryContainer.push(Markup.renderedElement("span", sentinelAttributes, null, false));
            if (line.endReason == "MandatoryBreak") {
                final hardBreakAttributes:Array<AttributeEntry> = [];
                Markup.setAttribute(hardBreakAttributes, "data-tq-geometry", "true");
                Markup.setAttribute(hardBreakAttributes, "data-tq-hard-break", "true");
                Markup.setAttribute(hardBreakAttributes, "data-tq-src", "\n");
                boundaryContainer.push(Markup.renderedElement("span", hardBreakAttributes, null, false));
            }
            if (lineIndex < plan.lines.length - 1) {
                final breakAttributes:Array<AttributeEntry> = [];
                Markup.setAttribute(breakAttributes, "data-tq-engine-break", line.endReason);
                if (line.endReason != "MandatoryBreak") {
                    Markup.setAttribute(breakAttributes, "aria-hidden", "true");
                    Markup.setAttribute(breakAttributes, "data-tq-copy-ignore", "true");
                }
                boundaryContainer.push(Markup.renderedElement("br", breakAttributes, null, true));
            }
            lineIndex += 1;
        }
        semanticContainerFor(state, []);
        if (plan.lines.length > 0) {
            final endAttributes:Array<AttributeEntry> = [];
            Markup.setAttribute(endAttributes, "aria-hidden", "true");
            Markup.setAttribute(endAttributes, "data-tq-copy-ignore", "true");
            Markup.setAttribute(endAttributes, "data-tq-selection-end", "true");
            state.nodes.push(Markup.renderedElement("span", endAttributes, "\u200B", false));
        }
        final overlayPlan:EvidenceOverlayPlan = {
            decorationSegments: plan.decorationSegments,
            emphasisDots: plan.emphasisDots,
            fontSize: plan.fontSize,
            overlayWidth: plan.overlayWidth,
            height: plan.height
        };
        final overlayOptions:EvidenceOverlayOptions = { emphasisDotColor: options.emphasisDotColor };
        Evidence.appendEvidenceOverlays(state.nodes, overlayPlan, overlayOptions);
        final artifacts:Array<MarkupArtifact> = [];
        var htmlOut = "";
        var nodeIndex = 0;
        while (nodeIndex < state.nodes.length) {
            htmlOut += state.nodes[nodeIndex].html;
            artifacts.push(state.nodes[nodeIndex].artifact);
            nodeIndex += 1;
        }
        return {
            html: htmlOut,
            artifact: artifacts,
            liveSemanticCount: options.liveSource ? semantics.length : 0,
            inlineObjectCount: inlineObjectCount,
            markerCount: plan.lines.length
        };
    }

    /** Creates the traversal state with explicit element types for the emitter. */
    private static function newArtifactState(cjkStrong:Array<PreparedCjkStrongSemantic>, liveSource:Bool):PreparedArtifactState {
        return {
            nodes: [],
            activeSemantics: [],
            activeContainers: [],
            cjkStrong: cjkStrong,
            liveSource: liveSource
        };
    }

    /**
     * Opens the containers for one semantic path and returns the node list new
     * children go into (prepared-dom.ts:745). Paths are matched by span index,
     * which is the identity comparison the oracle performs on span objects.
     */
    private static function semanticContainerFor(state:PreparedArtifactState, path:Array<PreparedSemanticSpan>):Array<MarkupNode> {
        final active = state.activeSemantics;
        final limit = active.length < path.length ? active.length : path.length;
        var common = 0;
        while (common < limit && active[common].index == path[common].index) {
            common += 1;
        }
        final nextActive:Array<PreparedSemanticSpan> = [];
        var keepIndex = 0;
        while (keepIndex < common) {
            nextActive.push(active[keepIndex]);
            keepIndex += 1;
        }
        state.activeSemantics = nextActive;
        final nextContainers:Array<RenderedMarkupContainer> = [];
        var keepContainer = 0;
        while (keepContainer < common) {
            nextContainers.push(state.activeContainers[keepContainer]);
            keepContainer += 1;
        }
        state.activeContainers = nextContainers;
        var container:Array<MarkupNode> = state.nodes;
        if (state.activeContainers.length > 0) {
            container = state.activeContainers[state.activeContainers.length - 1].children;
        }
        var pathIndex = common;
        while (pathIndex < path.length) {
            final semantic = path[pathIndex];
            var cjkWeight:Null<Float> = null;
            var strongIndex = 0;
            while (strongIndex < state.cjkStrong.length) {
                final strong = state.cjkStrong[strongIndex];
                if (strong.start == semantic.start && strong.end == semantic.end) {
                    cjkWeight = strong.weight;
                    break;
                }
                strongIndex += 1;
            }
            final attributes:Array<AttributeEntry> = [];
            var wrapper:RenderedMarkupContainer;
            if (state.liveSource) {
                Markup.setAttribute(attributes, PreparedDom.LIVE_SEMANTIC_INDEX_ATTRIBUTE, "" + semantic.sourceIndex);
                wrapper = Markup.renderedContainer("span", attributes);
            } else {
                var attrIndex = 0;
                while (attrIndex < semantic.attributes.length) {
                    attributes.push({ name: semantic.attributes[attrIndex].name, value: semantic.attributes[attrIndex].value });
                    attrIndex += 1;
                }
                Markup.setAttribute(attributes, "data-tq-source-semantic", "true");
                if (cjkWeight != null) {
                    final weight:Float = cjkWeight;
                    Markup.setAttribute(attributes, "data-tq-cjk-emphasis", "true");
                    Markup.setAttribute(attributes, "style", "font-weight:" + weight + "!important");
                }
                wrapper = Markup.renderedContainer(semantic.tagName, attributes);
            }
            container.push(wrapper);
            state.activeSemantics.push(semantic);
            state.activeContainers.push(wrapper);
            container = wrapper.children;
            pathIndex += 1;
        }
        return container;
    }

    /** Plan inline edges win over caller boxes (prepared-dom.ts:708). */
    private static function inlineBoxesFor(edges:Array<InlineEdgeEntry>, optionBoxes:Array<InlineBoxEntry>):Array<InlineBoxEntry> {
        if (edges.length == 0) {
            return optionBoxes;
        }
        final entries:Array<InlineBoxEntry> = [];
        var index = 0;
        while (index < edges.length) {
            final edge = edges[index];
            if (edge.inlineStart != null) {
                final startPx:Float = edge.inlineStart;
                entries.push({ start: edge.offset, end: edge.offset, inlineStartPx: startPx, inlineEndPx: 0.0 });
            }
            if (edge.inlineEnd != null) {
                final endPx:Float = edge.inlineEnd;
                entries.push({ start: edge.offset, end: edge.offset, inlineStartPx: 0.0, inlineEndPx: endPx });
            }
            index += 1;
        }
        return entries;
    }

    /** Summed inline-start width at one offset (prepared-dom.ts:721). */
    private static function inlineStartAt(boxes:Array<InlineBoxEntry>, offset:Float):Float {
        var sum = 0.0;
        var index = 0;
        while (index < boxes.length) {
            if (boxes[index].start == offset) {
                sum += boxes[index].inlineStartPx;
            }
            index += 1;
        }
        return sum;
    }

    /** Summed inline-end width at one offset (prepared-dom.ts:722). */
    private static function inlineEndAt(boxes:Array<InlineBoxEntry>, offset:Float):Float {
        var sum = 0.0;
        var index = 0;
        while (index < boxes.length) {
            if (boxes[index].end == offset) {
                sum += boxes[index].inlineEndPx;
            }
            index += 1;
        }
        return sum;
    }

    /** First ruby decision whose base range ends here (Map first-write-wins). */
    private static function rubyAt(rubies:Array<PlanRubyAnnotation>, end:Float):Null<PlanRubyAnnotation> {
        var index = 0;
        while (index < rubies.length) {
            if (rubies[index].baseRangeEnd == end) {
                return rubies[index];
            }
            index += 1;
        }
        return null;
    }

    /** All bopomofo zones whose base range ends here, in plan order. */
    private static function bopomofoAt(zones:Array<PlanBopomofoZone>, end:Float):Array<PlanBopomofoZone> {
        final matches:Array<PlanBopomofoZone> = [];
        var index = 0;
        while (index < zones.length) {
            if (zones[index].baseRangeEnd == end) {
                matches.push(zones[index]);
            }
            index += 1;
        }
        return matches;
    }

    /** Semantics fully containing the cell range (prepared-dom.ts:727). */
    private static function semanticsFor(semantics:Array<PreparedSemanticSpan>, rangeStart:Float, rangeEnd:Float):Array<PreparedSemanticSpan> {
        final matches:Array<PreparedSemanticSpan> = [];
        var index = 0;
        while (index < semantics.length) {
            final span = semantics[index];
            if (rangeStart >= span.start && rangeEnd <= span.end) {
                matches.push(span);
            }
            index += 1;
        }
        return matches;
    }

    /** Semantics strictly crossing the line boundary (prepared-dom.ts:729). */
    private static function crossingSpans(semantics:Array<PreparedSemanticSpan>, offset:Float):Array<PreparedSemanticSpan> {
        final matches:Array<PreparedSemanticSpan> = [];
        var index = 0;
        while (index < semantics.length) {
            final span = semantics[index];
            if (offset > span.start && offset < span.end) {
                matches.push(span);
            }
            index += 1;
        }
        return matches;
    }

    /** Font families of the innermost render-text span owner (prepared-dom.ts:731). */
    private static function renderFontFamiliesFor(spans:Array<PreparedRenderTextSpan>, rangeStart:Float, rangeEnd:Float):Array<String> {
        final owners:Array<PreparedRenderTextSpan> = [];
        var index = 0;
        while (index < spans.length) {
            final span = spans[index];
            if (rangeStart >= span.start && rangeEnd <= span.end) {
                owners.push(span);
            }
            index += 1;
        }
        if (owners.length == 0) {
            return [];
        }
        final signature = owners[0].signature;
        var ownerIndex = 1;
        while (ownerIndex < owners.length) {
            if (owners[ownerIndex].signature != signature) {
                throw new PreparedDomException(ConflictingPreparedRenderTextSpan);
            }
            ownerIndex += 1;
        }
        return owners[0].fontFamilies;
    }

    /** Whether offset falls inside one emphasis range. */
    private static function rangeContains(ranges:Array<PreparedEmphasisRange>, offset:Float):Bool {
        var index = 0;
        while (index < ranges.length) {
            if (offset >= ranges[index].start && offset < ranges[index].end) {
                return true;
            }
            index += 1;
        }
        return false;
    }

    /** JSON.stringify over a semantic path (the merge key, prepared-dom.ts:843). */
    private static function pathSignature(path:Array<PreparedSemanticSpan>):String {
        var out = "[";
        var index = 0;
        while (index < path.length) {
            if (index > 0) {
                out += ",";
            }
            out += path[index].signature;
            index += 1;
        }
        return out + "]";
    }

    private static function runChild(run:PreparedRunTyped):PreparedLineChild {
        return {
            kind: "run",
            run: run,
            cell: null,
            carrierMargin: 0.0,
            ruby: null,
            zone: null,
            width: 0.0,
            lineTop: 0.0,
            lineHeight: 0.0,
            semanticPath: run.semanticPath
        };
    }

    private static function inlineObjectChild(cell:PreparedRunTyped):PreparedLineChild {
        return {
            kind: "inlineObject",
            run: null,
            cell: cell,
            carrierMargin: cell.trailingGap,
            ruby: null,
            zone: null,
            width: 0.0,
            lineTop: 0.0,
            lineHeight: 0.0,
            semanticPath: cell.semanticPath
        };
    }

    private static function rubyChild(ruby:PlanRubyAnnotation, lineTop:Float, semanticPath:Array<PreparedSemanticSpan>):PreparedLineChild {
        return {
            kind: "ruby",
            run: null,
            cell: null,
            carrierMargin: 0.0,
            ruby: ruby,
            zone: null,
            width: 0.0,
            lineTop: lineTop,
            lineHeight: 0.0,
            semanticPath: semanticPath
        };
    }

    private static function bopomofoChild(zone:PlanBopomofoZone, width:Float, lineTop:Float, lineHeight:Float, semanticPath:Array<PreparedSemanticSpan>):PreparedLineChild {
        return {
            kind: "bopomofo",
            run: null,
            cell: null,
            carrierMargin: 0.0,
            ruby: null,
            zone: zone,
            width: width,
            lineTop: lineTop,
            lineHeight: lineHeight,
            semanticPath: semanticPath
        };
    }
}

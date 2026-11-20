package org.tiqian.shared.html;

/**
 * The linkedom-backed DOM query API, the Haxe single-source migration of
 * platforms/web/server/precompute/engine/src/html_parse.rs: the query API at
 * L328-447 (tag_name, attributes, attribute_value, element_children, parent,
 * descendants_by_tag, closest).
 *
 * The Rust lane builds the tree with html5ever. This lane reads the tree
 * the consumer parses with linkedom; the node surface is DomNode, so the
 * lane reads only the fields the projection and selector walks need. The
 * consumer keeps the parse call and its binding, which also keeps this
 * generated lane free of a module import the server mount would have to
 * type-assert.
 *
 * to_dom_node (html_parse.rs L421-447) has no counterpart here: the
 * projection that consumes its DomNode output belongs to the prepare
 * pipeline (Html-B2), which walks the linkedom DOM directly.
 */
class DomParser {
    final document:DomNode;

    public function new(document:DomNode) {
        this.document = document;
    }

    public function documentNode():DomNode {
        return this.document;
    }

    public function isElement(node:DomNode):Bool {
        return node.nodeType == 1;
    }

    /**
     * The element's local name. html5ever's tokenizer lowercases HTML tag
     * names, so this lane lowercases linkedom's uppercase tagName with the
     * same ASCII-only mapping the Rust comparisons use.
     */
    public function tagName(node:DomNode):String {
        return HtmlNameCase.asciiLower(node.tagName);
    }

    /** Attribute pairs in source order. */
    public function attributes(node:DomNode):Array<DomAttribute> {
        return node.attributes;
    }

    /** First attribute whose name equals the given name, ASCII case insensitively. */
    public function attributeValue(node:DomNode, name:String):Null<String> {
        final target = HtmlNameCase.asciiLower(name);
        final attributes = this.attributes(node);
        for (attribute in attributes) {
            if (HtmlNameCase.asciiLower(attribute.name) == target) {
                return attribute.value;
            }
        }
        return null;
    }

    /**
     * Element children only, in tree order. linkedom keeps template contents
     * in the element's child list while html5ever keeps them out of the tree,
     * so the template guard restores the Rust reading.
     */
    public function elementChildren(node:DomNode):Array<DomNode> {
        if (this.isElement(node) && this.tagName(node) == "template") {
            return [];
        }
        return node.children;
    }

    public function parent(node:DomNode):Null<DomNode> {
        return node.parentElement;
    }

    /**
     * Descendant elements with a matching tag, pre-order like
     * querySelectorAll. The root itself never matches, matching the Rust
     * arena walk; template subtrees stay outside the document tree.
     */
    public function descendantsByTag(root:DomNode, names:Array<String>):Array<DomNode> {
        final lowered:Array<String> = [];
        for (name in names) {
            lowered.push(HtmlNameCase.asciiLower(name));
        }
        final matched:Array<DomNode> = [];
        final stack:Array<DomNode> = [];
        stack.push(root);
        var first = true;
        while (stack.length > 0) {
            final node = stack.pop();
            final element = this.isElement(node);
            if (!first && element && lowered.indexOf(HtmlNameCase.asciiLower(node.tagName)) >= 0) {
                matched.push(node);
            }
            first = false;
            if (element && HtmlNameCase.asciiLower(node.tagName) == "template") {
                continue;
            }
            final children = node.childNodes;
            var index = children.length - 1;
            while (index >= 0) {
                stack.push(children[index]);
                index -= 1;
            }
        }
        return matched;
    }

    /** element.closest(selectorList): the element itself or an ancestor matches one compound. */
    public function closest(element:DomNode, selectors:Array<CompoundSelector>):Bool {
        var current:Null<DomNode> = element;
        while (current != null) {
            if (this.isElement(current)) {
                for (selector in selectors) {
                    if (selector.matches(this, current)) {
                        return true;
                    }
                }
            }
            current = current.parentElement;
        }
        return false;
    }
}

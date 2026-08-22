//! HTML parsing for the `precompute-html.js` port (ADR 0050 parity oracle):
//! html5ever builds the document, tag queries and `closest` walks read it,
//! and chosen elements convert to the `DomNode` tree the projection walks.
//!
//! linkedom keeps `scripting_enabled` off, so `noscript` children are real
//! elements on both sides. Template contents stay unreachable from the
//! document tree, so queries never descend into them. Two markup shapes sit
//! outside this parity: linkedom parses `iframe` interior as markup while
//! the spec reads it as raw text, and linkedom keeps parsing after
//! `plaintext`. Prose paragraphs never contain either form.

use std::borrow::Cow;
use std::cell::RefCell;

use html5ever::interface::tree_builder::{ElementFlags, NodeOrText, QuirksMode, TreeSink};
use html5ever::interface::ElemName;
use html5ever::tendril::{StrTendril, TendrilSink};
use html5ever::tree_builder::TreeBuilderOpts;
use html5ever::{parse_document, Attribute, LocalName, Namespace, ParseOpts, QualName};
use tiqian::NamedError;

use crate::snapshot_source::DomNode;

/// One arena slot; comments, processing instructions and the doctype never
/// enter the projected tree.
enum Slot {
    Document,
    Doctype,
    Element {
        name: QualName,
        attributes: Vec<Attribute>,
        template_contents: Option<usize>,
    },
    Text(RefCell<String>),
    Dropped,
}

struct ArenaNode {
    slot: Slot,
    parent: Option<usize>,
    children: RefCell<Vec<usize>>,
}

/// The `ElemName` the tree builder reads; atom copies because the arena
/// cannot lend a reference through the `RefCell`.
#[derive(Debug)]
pub struct OwnedElemName {
    ns: Namespace,
    local: LocalName,
}

impl ElemName for OwnedElemName {
    fn ns(&self) -> &Namespace {
        &self.ns
    }

    fn local_name(&self) -> &LocalName {
        &self.local
    }
}

/// A parsed document plus the queries `precompute-html` needs. Handles are
/// arena indices; the parent links stay alive for `closest` walks above the
/// prepare root.
pub struct DomParser {
    nodes: RefCell<Vec<ArenaNode>>,
    document: usize,
}

impl DomParser {
    fn new() -> DomParser {
        let nodes = vec![ArenaNode {
            slot: Slot::Document,
            parent: None,
            children: RefCell::new(Vec::new()),
        }];
        DomParser {
            nodes: RefCell::new(nodes),
            document: 0,
        }
    }

    fn push(&self, slot: Slot) -> usize {
        let mut nodes = self.nodes.borrow_mut();
        nodes.push(ArenaNode {
            slot,
            parent: None,
            children: RefCell::new(Vec::new()),
        });
        nodes.len() - 1
    }

    fn slot_is_text(&self, index: usize) -> bool {
        matches!(self.nodes.borrow()[index].slot, Slot::Text(_))
    }

    fn detach(&self, index: usize) {
        let parent = self.nodes.borrow()[index].parent;
        if let Some(parent) = parent {
            self.nodes.borrow_mut()[parent]
                .children
                .borrow_mut()
                .retain(|child| *child != index);
        }
    }

    fn set_parent(&self, index: usize, parent: usize) {
        self.nodes.borrow_mut()[index].parent = Some(parent);
    }

    fn last_child(&self, index: usize) -> Option<usize> {
        self.nodes.borrow()[index].children.borrow().last().copied()
    }

    fn previous_sibling(&self, index: usize) -> Option<usize> {
        let nodes = self.nodes.borrow();
        let parent = nodes[index].parent?;
        let children = nodes[parent].children.borrow();
        let position = children.iter().position(|child| *child == index)?;
        if position == 0 {
            return None;
        }
        Some(children[position - 1])
    }

    fn append_common(
        &self,
        child: NodeOrText<usize>,
        merge_target: impl FnOnce() -> Option<usize>,
        attach: impl FnOnce(usize),
    ) {
        match child {
            NodeOrText::AppendText(text) => {
                if let Some(target) = merge_target().filter(|target| self.slot_is_text(*target)) {
                    if let Slot::Text(contents) = &self.nodes.borrow()[target].slot {
                        contents.borrow_mut().push_str(text.as_ref());
                        return;
                    }
                    unreachable!("slot_is_text checked the same node");
                }
                let node = self.push(Slot::Text(RefCell::new(text.as_ref().to_string())));
                attach(node);
            }
            NodeOrText::AppendNode(node) => {
                self.detach(node);
                attach(node);
            }
        }
    }
}

impl TreeSink for DomParser {
    type Handle = usize;
    type Output = DomParser;
    type ElemName<'a> = OwnedElemName;

    fn finish(self) -> Self::Output {
        self
    }

    fn parse_error(&self, _message: Cow<'static, str>) {}

    fn get_document(&self) -> usize {
        self.document
    }

    fn elem_name(&self, target: &usize) -> OwnedElemName {
        let nodes = self.nodes.borrow();
        match &nodes[*target].slot {
            Slot::Element { name, .. } => OwnedElemName {
                ns: name.ns.clone(),
                local: name.local.clone(),
            },
            _ => panic!("elem_name on a non-element node"),
        }
    }

    fn create_element(&self, name: QualName, attrs: Vec<Attribute>, flags: ElementFlags) -> usize {
        let template_contents = if flags.template {
            Some(self.push(Slot::Document))
        } else {
            None
        };
        self.push(Slot::Element {
            name,
            attributes: attrs,
            template_contents,
        })
    }

    fn create_comment(&self, _text: StrTendril) -> usize {
        self.push(Slot::Dropped)
    }

    fn create_pi(&self, _target: StrTendril, _data: StrTendril) -> usize {
        self.push(Slot::Dropped)
    }

    fn append(&self, parent: &usize, child: NodeOrText<usize>) {
        let parent = *parent;
        self.append_common(
            child,
            || self.last_child(parent),
            |node| {
                self.set_parent(node, parent);
                self.nodes.borrow_mut()[parent]
                    .children
                    .borrow_mut()
                    .push(node);
            },
        );
    }

    fn append_before_sibling(&self, sibling: &usize, child: NodeOrText<usize>) {
        let sibling = *sibling;
        self.append_common(
            child,
            || self.previous_sibling(sibling),
            |node| {
                let parent = self.nodes.borrow()[sibling].parent;
                let Some(parent) = parent else { return };
                self.set_parent(node, parent);
                let nodes = self.nodes.borrow_mut();
                let position = nodes[parent]
                    .children
                    .borrow()
                    .iter()
                    .position(|candidate| *candidate == sibling);
                match position {
                    Some(position) => nodes[parent].children.borrow_mut().insert(position, node),
                    None => nodes[parent].children.borrow_mut().push(node),
                }
            },
        );
    }

    fn append_based_on_parent_node(
        &self,
        element: &usize,
        prev_element: &usize,
        child: NodeOrText<usize>,
    ) {
        let has_parent = self.nodes.borrow()[*element].parent.is_some();
        if has_parent {
            self.append_before_sibling(element, child);
        } else {
            self.append(prev_element, child);
        }
    }

    fn append_doctype_to_document(
        &self,
        _name: StrTendril,
        _public_id: StrTendril,
        _system_id: StrTendril,
    ) {
        let doctype = self.push(Slot::Doctype);
        self.append(&self.document, NodeOrText::AppendNode(doctype));
    }

    fn add_attrs_if_missing(&self, target: &usize, attrs: Vec<Attribute>) {
        let mut nodes = self.nodes.borrow_mut();
        let Slot::Element { attributes, .. } = &mut nodes[*target].slot else {
            panic!("add_attrs_if_missing on a non-element node");
        };
        for attr in attrs {
            let present = attributes.iter().any(|existing| existing.name == attr.name);
            if !present {
                attributes.push(attr);
            }
        }
    }

    fn get_template_contents(&self, target: &usize) -> usize {
        let nodes = self.nodes.borrow();
        match &nodes[*target].slot {
            Slot::Element {
                template_contents: Some(contents),
                ..
            } => *contents,
            _ => panic!("get_template_contents on a non-template node"),
        }
    }

    fn same_node(&self, left: &usize, right: &usize) -> bool {
        left == right
    }

    fn set_quirks_mode(&self, _mode: QuirksMode) {}

    fn remove_from_parent(&self, target: &usize) {
        self.detach(*target);
        self.nodes.borrow_mut()[*target].parent = None;
    }

    fn reparent_children(&self, node: &usize, new_parent: &usize) {
        let moved: Vec<usize> = {
            let nodes = self.nodes.borrow_mut();
            let moved = std::mem::take(&mut *nodes[*node].children.borrow_mut());
            drop(nodes);
            moved
        };
        for child in moved {
            self.set_parent(child, *new_parent);
            self.nodes.borrow_mut()[*new_parent]
                .children
                .borrow_mut()
                .push(child);
        }
    }
}

/// Parses a document the way `parseHTML` does.
pub fn parse_html_document(markup: &str) -> DomParser {
    let sink = DomParser::new();
    let options = ParseOpts {
        tree_builder: TreeBuilderOpts {
            scripting_enabled: false,
            ..Default::default()
        },
        ..Default::default()
    };
    parse_document(sink, options)
        .from_utf8()
        .one(markup.as_bytes())
}

impl DomParser {
    pub fn document(&self) -> usize {
        self.document
    }

    fn is_element(&self, index: usize) -> bool {
        matches!(self.nodes.borrow()[index].slot, Slot::Element { .. })
    }

    /// The element's local name; the tokenizer lowercases HTML tag names.
    pub fn tag_name(&self, index: usize) -> String {
        let nodes = self.nodes.borrow();
        match &nodes[index].slot {
            Slot::Element { name, .. } => name.local.to_string(),
            _ => panic!("tag_name on a non-element node"),
        }
    }

    /// Attribute pairs in source order.
    pub fn attributes(&self, index: usize) -> Vec<(String, String)> {
        let nodes = self.nodes.borrow();
        match &nodes[index].slot {
            Slot::Element { attributes, .. } => attributes
                .iter()
                .map(|attr| (attr.name.local.to_string(), attr.value.to_string()))
                .collect(),
            _ => panic!("attributes on a non-element node"),
        }
    }

    fn attribute_value(&self, index: usize, name: &str) -> Option<String> {
        self.attributes(index)
            .into_iter()
            .find(|(existing, _)| existing.eq_ignore_ascii_case(name))
            .map(|(_, value)| value)
    }

    /// Element children only, in tree order.
    pub fn element_children(&self, index: usize) -> Vec<usize> {
        self.nodes.borrow()[index]
            .children
            .borrow()
            .iter()
            .copied()
            .filter(|child| self.is_element(*child))
            .collect()
    }

    pub fn parent(&self, index: usize) -> Option<usize> {
        self.nodes.borrow()[index].parent
    }

    /// Descendant elements with a matching tag, pre-order like
    /// `querySelectorAll`. Template contents never appear because the tree
    /// builder keeps them out of the element's child list.
    pub fn descendants_by_tag(&self, root: usize, names: &[String]) -> Vec<usize> {
        let mut matched = Vec::new();
        let mut stack = vec![root];
        while let Some(node) = stack.pop() {
            if node != root
                && self.is_element(node)
                && names
                    .iter()
                    .any(|name| name.eq_ignore_ascii_case(&self.tag_name(node)))
            {
                matched.push(node);
            }
            let children: Vec<usize> = self.nodes.borrow()[node].children.borrow().clone();
            for child in children.iter().rev() {
                stack.push(*child);
            }
        }
        matched
    }

    /// `element.closest(selectorList)`: the element itself or an ancestor
    /// matches one compound of the list.
    pub fn closest(&self, element: usize, selectors: &[CompoundSelector]) -> bool {
        let mut current = Some(element);
        while let Some(node) = current {
            if self.is_element(node)
                && selectors
                    .iter()
                    .any(|selector| selector.matches(self, node))
            {
                return true;
            }
            current = self.parent(node);
        }
        false
    }

    /// The element subtree as the `DomNode` tree the projection walks.
    pub fn to_dom_node(&self, index: usize) -> DomNode {
        let children: Vec<DomNode> = self.nodes.borrow()[index]
            .children
            .borrow()
            .iter()
            .copied()
            .filter_map(|child| match &self.nodes.borrow()[child].slot {
                Slot::Text(contents) => Some(DomNode::Text(contents.borrow().clone())),
                Slot::Element { .. } => Some(self.to_dom_node(child)),
                _ => None,
            })
            .collect();
        let nodes = self.nodes.borrow();
        match &nodes[index].slot {
            Slot::Element {
                name, attributes, ..
            } => DomNode::Element {
                tag_name: name.local.to_string(),
                attributes: attributes
                    .iter()
                    .map(|attr| (attr.name.local.to_string(), attr.value.to_string()))
                    .collect(),
                children,
            },
            _ => panic!("to_dom_node on a non-element node"),
        }
    }
}

/// One compound selector of an `element.closest(...)` list. The accepted
/// forms cover the package defaults and prose hosts: a type selector, `*`,
/// `#id`, `.class`, `[attr]`, and `[attr=value]` with a bare or quoted
/// value. Anything else reports `UnsupportedHtmlAncestorSelector` instead
/// of guessing.
#[derive(Debug, Clone)]
pub struct CompoundSelector {
    tag: Option<String>,
    id: Option<String>,
    classes: Vec<String>,
    attributes: Vec<(String, Option<String>)>,
}

impl CompoundSelector {
    fn matches(&self, parser: &DomParser, element: usize) -> bool {
        let tag_ok = self.tag.as_ref().map_or(true, |tag| {
            tag.eq_ignore_ascii_case(&parser.tag_name(element))
        });
        if !tag_ok {
            return false;
        }
        if let Some(id) = &self.id {
            if parser.attribute_value(element, "id").as_deref() != Some(id.as_str()) {
                return false;
            }
        }
        if !self.classes.is_empty() {
            let class_attribute = parser.attribute_value(element, "class").unwrap_or_default();
            let present: Vec<&str> = class_attribute.split_ascii_whitespace().collect();
            if self
                .classes
                .iter()
                .any(|class| !present.contains(&class.as_str()))
            {
                return false;
            }
        }
        for (name, expected) in &self.attributes {
            let value = parser
                .attributes(element)
                .into_iter()
                .find(|(existing, _)| existing.eq_ignore_ascii_case(name))
                .map(|(_, value)| value);
            match (value, expected) {
                (Some(_), None) => {}
                (Some(actual), Some(expected)) if &actual == expected => {}
                _ => return false,
            }
        }
        true
    }
}

/// Parses a comma separated selector list for `closest`.
pub fn parse_compound_selector_list(selector: &str) -> Result<Vec<CompoundSelector>, NamedError> {
    let mut compounds = Vec::new();
    for part in selector.split(',') {
        let trimmed = js_selector_trim(part);
        if trimmed.is_empty() {
            return Err(NamedError("UnsupportedHtmlAncestorSelector".to_string()));
        }
        compounds.push(parse_compound_selector(trimmed)?);
    }
    Ok(compounds)
}

fn js_selector_trim(value: &str) -> &str {
    value.trim_matches(|character: char| {
        matches!(character, '\u{9}' | '\u{a}' | '\u{c}' | '\u{d}' | '\u{20}')
    })
}

fn parse_compound_selector(input: &str) -> Result<CompoundSelector, NamedError> {
    let unsupported = || NamedError("UnsupportedHtmlAncestorSelector".to_string());
    let mut selector = CompoundSelector {
        tag: None,
        id: None,
        classes: Vec::new(),
        attributes: Vec::new(),
    };
    let characters: Vec<char> = input.chars().collect();
    let mut position = 0;
    while position < characters.len() {
        match characters[position] {
            '*' if position == 0 && selector.tag.is_none() => {
                position += 1;
            }
            '.' => {
                position += 1;
                let (name, next) = read_selector_word(&characters, position, false)?;
                selector.classes.push(name);
                position = next;
            }
            '#' => {
                position += 1;
                if selector.id.is_some() {
                    return Err(unsupported());
                }
                let (name, next) = read_selector_word(&characters, position, false)?;
                selector.id = Some(name);
                position = next;
            }
            '[' => {
                position += 1;
                let (name, next) = read_selector_word(&characters, position, true)?;
                position = next;
                if position >= characters.len() {
                    return Err(unsupported());
                }
                if characters[position] == ']' {
                    position += 1;
                    selector.attributes.push((name, None));
                    continue;
                }
                if characters[position] != '=' {
                    return Err(unsupported());
                }
                position += 1;
                let mut value = String::new();
                if position < characters.len()
                    && (characters[position] == '"' || characters[position] == '\'')
                {
                    let quote = characters[position];
                    position += 1;
                    loop {
                        if position >= characters.len() {
                            return Err(unsupported());
                        }
                        if characters[position] == quote {
                            position += 1;
                            break;
                        }
                        value.push(characters[position]);
                        position += 1;
                    }
                } else {
                    loop {
                        if position >= characters.len() {
                            return Err(unsupported());
                        }
                        if characters[position] == ']' {
                            break;
                        }
                        if !is_selector_word_character(characters[position], false) {
                            return Err(unsupported());
                        }
                        value.push(characters[position]);
                        position += 1;
                    }
                }
                if position >= characters.len() || characters[position] != ']' {
                    return Err(unsupported());
                }
                position += 1;
                selector.attributes.push((name, Some(value)));
            }
            first if is_selector_word_start(first) => {
                if selector.tag.is_some() || position != 0 {
                    return Err(unsupported());
                }
                let (name, next) = read_selector_word(&characters, position, false)?;
                selector.tag = Some(name.to_ascii_lowercase());
                position = next;
            }
            _ => return Err(unsupported()),
        }
    }
    Ok(selector)
}

fn is_selector_word_start(character: char) -> bool {
    character.is_ascii_alphabetic() || character == '_' || character == '-'
}

fn is_selector_word_character(character: char, attribute_name: bool) -> bool {
    if character.is_ascii_alphanumeric() || character == '_' || character == '-' {
        return true;
    }
    attribute_name && character == ':'
}

/// Reads one identifier; a bare attribute value accepts the wider word set.
fn read_selector_word(
    characters: &[char],
    position: usize,
    attribute_name: bool,
) -> Result<(String, usize), NamedError> {
    let unsupported = || NamedError("UnsupportedHtmlAncestorSelector".to_string());
    if position >= characters.len() || !is_selector_word_start(characters[position]) {
        return Err(unsupported());
    }
    let mut word = String::new();
    let mut index = position;
    while index < characters.len() && is_selector_word_character(characters[index], attribute_name)
    {
        word.push(characters[index]);
        index += 1;
    }
    Ok((word, index))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tags(parser: &DomParser, indices: &[usize]) -> Vec<String> {
        indices
            .iter()
            .map(|index| parser.tag_name(*index))
            .collect()
    }

    #[test]
    fn parse_follows_the_html_tree_construction() {
        let parser = parse_html_document(
            "<main data-tq-html-prepare-root><p>a &amp; b<p>two<ul><li>x</UL><P>upper</main>",
        );
        let mains = parser.descendants_by_tag(parser.document(), &["main".to_string()]);
        assert_eq!(mains.len(), 1);
        let matched = parser.descendants_by_tag(mains[0], &["p".to_string(), "li".to_string()]);
        assert_eq!(tags(&parser, &matched), ["p", "p", "li", "p"]);
        assert_eq!(
            parser.to_dom_node(matched[0]),
            DomNode::Element {
                tag_name: "p".to_string(),
                attributes: Vec::new(),
                children: vec![DomNode::Text("a & b".to_string()),],
            }
        );
    }

    #[test]
    fn template_contents_stay_outside_the_tree() {
        let parser =
            parse_html_document("<main><template><p>inert</p></template><p>live</p></main>");
        let mains = parser.descendants_by_tag(parser.document(), &["main".to_string()]);
        let matched = parser.descendants_by_tag(mains[0], &["p".to_string()]);
        assert_eq!(matched.len(), 1);
        let templates = parser.descendants_by_tag(mains[0], &["template".to_string()]);
        match parser.to_dom_node(templates[0]) {
            DomNode::Element { children, .. } => assert!(children.is_empty()),
            other => panic!("template stays an element: {other:?}"),
        }
    }

    #[test]
    fn noscript_children_are_real_elements() {
        let parser = parse_html_document("<main><noscript><p>a</p></noscript></main>");
        let mains = parser.descendants_by_tag(parser.document(), &["main".to_string()]);
        let matched = parser.descendants_by_tag(mains[0], &["p".to_string()]);
        assert_eq!(matched.len(), 1);
    }

    #[test]
    fn attributes_keep_source_order_and_first_duplicate_wins() {
        let parser = parse_html_document(
            "<main><p title='a&quot;b' data-x=1 class=\"z w\" class=\"q\">t</p></main>",
        );
        let mains = parser.descendants_by_tag(parser.document(), &["main".to_string()]);
        let paragraph = parser.descendants_by_tag(mains[0], &["p".to_string()])[0];
        assert_eq!(
            parser.attributes(paragraph),
            [
                ("title".to_string(), "a\"b".to_string()),
                ("data-x".to_string(), "1".to_string()),
                ("class".to_string(), "z w".to_string()),
            ]
        );
    }

    #[test]
    fn closest_matches_self_ancestors_and_the_default_kinds() {
        let parser = parse_html_document(
            "<main><div class=\"not-prose katex\"><p data-tqian-skip=\"1\" id=\"px\">t</p></div></main>",
        );
        let mains = parser.descendants_by_tag(parser.document(), &["main".to_string()]);
        let paragraph = parser.descendants_by_tag(mains[0], &["p".to_string()])[0];
        let skip = parse_compound_selector_list(
            "[data-tiqian-skip], pre, table, .not-prose, .katex, .katex-display, .expressive-code",
        )
        .expect("default selector parses");
        assert!(parser.closest(paragraph, &skip));
        let host = parse_compound_selector_list("section, #px, p[q], p[data-x=\"1\"]")
            .expect("host selector parses");
        assert!(parser.closest(paragraph, &host));
        let none = parse_compound_selector_list("pre, table").expect("parses");
        assert!(!parser.closest(paragraph, &none));
    }

    #[test]
    fn unsupported_selector_forms_are_named_errors() {
        for selector in [
            "",
            " ",
            "a b",
            "a>b",
            "li:hover",
            "li:nth-child(2)",
            "[data-x^=\"y\"]",
            "[data-x~=y]",
            "a..b",
            "*p",
            "[unclosed",
        ] {
            assert!(
                parse_compound_selector_list(selector).is_err(),
                "{selector:?} must not parse"
            );
        }
    }
}

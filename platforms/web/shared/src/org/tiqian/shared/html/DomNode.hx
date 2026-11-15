package org.tiqian.shared.html;

/**
 * The linkedom node surface the shared HTML query API reads. linkedom hands
 * out NodeList, HTMLCollection and NamedNodeMap values for `children`,
 * `childNodes` and `attributes`; the generated lane only reads `length` and
 * indices, so the array-like surface below is what it needs. The tree links
 * stay owned by linkedom and the lane only reads them.
 */
typedef DomNode = {
    var nodeType:Int;
    var tagName:String;
    var attributes:Array<DomAttribute>;
    var children:Array<DomNode>;
    var childNodes:Array<DomNode>;
    var parentElement:Null<DomNode>;
    var nodeValue:Null<String>;
}

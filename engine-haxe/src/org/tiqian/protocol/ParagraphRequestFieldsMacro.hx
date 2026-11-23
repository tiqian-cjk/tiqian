package org.tiqian.protocol;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

class ParagraphRequestFieldsMacro {
    public static function build():Array<Field> {
        final fields = Context.getBuildFields();
        final type = Context.getType("org.tiqian.protocol.ParagraphRequest");
        final declared:Array<ClassField> = switch (type) {
            case TType(definition, _):
                switch (definition.get().type) {
                    case TAnonymous(anonymous): anonymous.get().fields;
                    case _: Context.error("ParagraphRequest must resolve to an anonymous type", Context.currentPos());
                }
            case _: Context.error("ParagraphRequest must be a typedef", Context.currentPos());
        };
        // AnonType.fields is alphabetically sorted; the source position restores
        // the typedef's declaration order.
        final ordered = declared.copy();
        ordered.sort((left, right) -> Context.getPosInfos(left.pos).min - Context.getPosInfos(right.pos).min);
        final values:Array<Expr> = [for (field in ordered) macro $v{field.name}];
        fields.push({
            name: "NAMES",
            access: [APublic, AStatic, AFinal],
            kind: FVar(macro :Array<String>, macro $a{values}),
            pos: Context.currentPos(),
        });
        return fields;
    }
}
#end

package org.tiqian.core;

class IllegalStateException extends TiqianIllegalArgumentException {
    public function new(message:String) {
        super(Message(message));
    }
}

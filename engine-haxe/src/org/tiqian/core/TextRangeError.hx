package org.tiqian.core;

enum TextRangeError {
    StartGreaterThanEnd;
    NegativeStart;
    Message(text:String);
}

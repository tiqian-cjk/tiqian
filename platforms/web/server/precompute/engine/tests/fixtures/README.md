# Precompute font fixture

`DelaGothicOne-Regular.ttf` is the file the js oracle dump in
`../precomputer_parity.rs` was generated over. The dump pins the SHA-256
`57986ebf82ac5b5383155483b541d7433121bf395c5621df59b48196a8a99c2e` of that
file, so a synthesized face cannot replace it.

The file is Dela Gothic One Regular, version 1.005, from the Dela Gothic
project at https://github.com/syakuzen/DelaGothic. The copyright line is
`Copyright 2020 The Dela Gothic Project Authors`. The file is licensed under
the SIL Open Font License, Version 1.1; the license text is `OFL.txt`.

The session-layout, precomputer-parity and submission-parity tests read the
file through `include_bytes!` in `../support/font_fixture.rs`, which fails the
test build when the file is absent. No test resolves a font from `$HOME` or
from the system font directory.

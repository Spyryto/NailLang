# Macro audit after 0.24

**Keep `unless` as optional surface sugar.** Its two branches stay lazy.
The example puts a division by zero in each discarded branch in turn.
An ordinary eager function would need callers to wrap both branches in
closures to obtain the same behavior. In short expressions, plain
`if ... then ... else ...` is still easy to read.

**Keep the shared `timedDrill` template if the wording is a project
convention.** It builds two fields from the exercise inputs, and both lessons
reuse it. A one-to-one wrapper around `Drill` adds a declaration and an
`expand` at each call. Ordinary pure data assembly, including `timedDrill`
itself, can also be implemented as a function. Its role here is to exercise
macro scope and reuse with a realistic example.

**Leave the parser guards explicit.** The audit script finds 29 instances
of `if parseFailed result then result else …` in the Nail parser. A hygienic
template can preserve lazy continuation evaluation. With the parentheses
normally needed around a continuation, the representative call takes
6 whitespace tokens versus 7 for the original form. After including the
21-token macro declaration, the rough saving over all 29 sites is 8 tokens.
That estimate does not include indentation or a module import. The script
checks the proposed template on both success and error branches. The
repeated error propagation in `coreRead` would need binding-aware syntax
to replace it cleanly. A fixed expression template cannot introduce a named
binding for arbitrary caller code while preserving hygiene.

The lesson comparison was executed against the generated data and HTML.
It has not been tried with a pupil.

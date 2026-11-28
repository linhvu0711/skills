# A sourced shell helper sets no trap

`shared/gh.sh` is sourced into the script that calls it (#336). It removes its temp file by hand on each return path and sets no `EXIT` trap. A script has one `EXIT` trap, so a trap set in a sourced helper would replace the caller's own trap, and the caller's cleanup would not run.

A helper that a script sources cleans up its own files before it returns. A trap belongs to the script that owns the process.

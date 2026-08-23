---
description: Preserve Flyology RDF's project-specific repository rules and verification workflow.
---

# Repository agent instructions

- Use `gh` outside the sandbox; it does not work inside the sandbox.
- Commit messages follow `Problem:` / `Solution:`.
- Do not add `Co-Authored-By` trailers, or any other tool or assistant
  attribution, to commit messages.

## Naming

- The top-level package is `Flyology_RDF`, with child units such as
  `Flyology_RDF.Terms` and `Flyology_RDF.Turtle_Parsers`.
- Never introduce a `Flyology` parent unit in this crate. A parent package
  here collides when the crate is used alongside the Flyology runtime, which
  is why every standalone crate in this ecosystem uses a single underscored
  root.

## Compatibility

- This crate has no released format or API to preserve. Until `v0.1.0` is
  tagged, prefer the correct design over the compatible one, and change wire
  formats, package boundaries, and signatures freely.
- After `v0.1.0`, the binary term format is still explicitly experimental. Do
  not describe it as stable in documentation or commit messages until the
  golden-vector corpus is in the pull-request gate and this paragraph is
  replaced with a stability statement.

## Correctness posture

- Constructor-enforced invariants are the design: an invalid term must be
  unrepresentable rather than detected later. Position constraints belong in
  the type system, not in runtime checks.
- The parser rejects everything outside the accepted grammar with a typed
  diagnostic. No extension syntax is silently accepted, and no input is
  silently repaired.
- A false accept is a more serious defect than a false reject. Both are bugs.

## Testing

- Every external dependency of a test — conformance corpus, foreign oracle,
  container — is provisioned by a repo-local script, pinned by digest or
  checksum, installed under a gitignored directory, and never assumed to be
  present on the host. `scripts/provision-oracles.sh` owns that.
- Differential results carry provenance: which oracle, at which pin, over
  which corpus commit, on which host. A conformance number without provenance
  does not go in the README.
- Conformance harnesses report evidence — entries examined, positive,
  negative, evaluation, skipped-by-reason — not a bare pass or fail. A
  shrinking count fails the build.

## Documentation

- Every public declaration carries a GNATdoc leading comment.
  `./scripts/docs.sh` must produce `docs/api/index.html` without warnings.
- Prose is modest. The crate is experimental until continuous integration
  says otherwise; do not make production-qualification claims.

## Releases

- Publish `flyology_rdf` through an immutable annotated tag named
  `flyology_rdf/v<version>`, for example `flyology_rdf/v0.1.0`.
- Before tagging, set the root `alire.toml` to the exact stable version,
  replace inappropriate `-dev` dependency constraints with stable
  constraints, and run the required checks plus `alr show`. The manifest must
  declare `name = "flyology_rdf"` and the same version as the tag.
- Create and push the tag only after committing the release-ready manifest:

  ```sh
  git tag -a flyology_rdf/v<version> -m "Release flyology_rdf <version>"
  git push origin refs/tags/flyology_rdf/v<version>
  ```

- Never move, replace, or reuse a published release tag. Put the next
  development-version change in a later commit.

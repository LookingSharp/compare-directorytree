# AGENTS.md

Canonical operational instructions for coding agents working in this
repository. Read this file before making any changes.

## Authority and project structure

- This repository is implementation-language-neutral.
- The authoritative behavioral specification is
  `specs/Compare-DirectoryTree-Spec.md`. All implementations and tests must
  conform to it.
- The PowerShell implementation lives under `powershell/`.
- Do not add speculative directory structure, frameworks, packaging,
  abstractions, or infrastructure without a concrete, immediate need.

## Standards

Agents MUST adhere to:

- Keep a Changelog 1.1.0: https://keepachangelog.com/en/1.1.0/
- Semantic Versioning 2.0.0: https://semver.org/spec/v2.0.0.html

These external standards are authoritative and must not be redefined
locally. If the project later requires an exception or extension, document
only that exception or extension here, in `AGENTS.md`, and continue to
follow the referenced standard for everything else.

## Design and specification review

`TEAM.md` defines the review team: Maya (design), Alex (product), Priya
(engineering), Marcus (security), and Dave (engineering executive). "the
team" and "theTeam" both refer to that group.

Apply it as follows:

- Required for any change to `specs/Compare-DirectoryTree-Spec.md` or to a
  speclet in `specs/speclets/`. Work through each perspective before
  proposing the change.
- Advisory for everything else. Routine and mechanical changes do not
  require a five-perspective review.
- Apply it on request. "Have the team review this" means evaluate the
  work from each perspective, converge, and incorporate the feedback.
- Converge before presenting. If disagreement remains, present at most
  two options, the material tradeoff, a recommendation, and only the
  decision that genuinely requires Dave's judgment.
- Dave is the human owner of this repository. An agent must not decide on
  his behalf. Raise such decisions to the user and leave them open.

## Specification lifecycle

- `specs/Compare-DirectoryTree-Spec.md` is the single authoritative current
  specification.
- Normal accepted changes update that specification in place.
- Git history is the detailed historical record; do not keep duplicate
  archived specification copies merely to preserve history.
- `specs/speclets/` contains focused design changes while they are being
  developed or reviewed.
- Once a speclet is accepted and incorporated into the authoritative
  specification, normally delete the speclet. Git history preserves it.
- Significant historical release states are preserved naturally by release
  tags and Git history.
- Only introduce parallel version-specific specifications if the project
  actually needs to maintain multiple behavioral contracts simultaneously.

## Behavioral-change workflow

Before making a behavioral change, determine whether it affects externally
observable or documented behavior.

If it does:

1. Update the authoritative specification, or create/update a speclet while
   the design is still being worked through.
2. Once the design is accepted, ensure the authoritative specification
   reflects it.
3. Update implementation and tests to conform to the accepted specification.
4. Add the notable user-visible change to the `Unreleased` section of
   `CHANGELOG.md` when required by Keep a Changelog.
5. Assess the release impact according to Semantic Versioning.

Do not create a released-version changelog section or bump a released
version merely because a change was made. Release/version assignment
occurs as part of the release process.

Do not silently reinterpret ambiguous requirements. Surface ambiguity rather
than inventing behavior.

## Mandatory completion check

Every coding-agent completion report must include:

```text
Change compliance:
- Spec: <updated | no change required - reason>
- Changelog: <updated | no entry required - reason>
- SemVer impact: <major | minor | patch | none>
- Tests: <updated/run/not run/etc.>
```

Perform these checks explicitly even when the user's request does not
mention specifications, changelog, versioning, or tests.

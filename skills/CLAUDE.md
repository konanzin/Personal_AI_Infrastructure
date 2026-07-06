# skills/CLAUDE.md

Skill structure conventions (canonical layout, frontmatter contract, workflow
format) live in the **CreateSkill** skill — prefer invoking `Skill("CreateSkill")`
for creating or restructuring skills so the conventions are applied once, from
one source.

**Hard requirement (irreversible action):** promoting a skill from private to
public REQUIRES running CreateSkill's Public Release Readiness audit first.

Everything else — edits, gotchas, references, validation — is normal judgment:
use CreateSkill when its workflows help, edit directly when they don't.

<!-- Drift register W1.7: the previous MANDATORY/STOP enforcement ceremony was
     inherited from upstream and cited an incident file
     (feedback_invoke_blogging_skill_never_handroll.md) that was never vendored
     into this repo. Re-add hard enforcement only from a reproduced, recorded
     failure — with a register row and a remove-by trigger. -->

# Sentinel Review Agents

These role cards define the stable Taption Encoder support agents used by Dex.

They are local workflow profiles, not autonomous background processes. Dex owns
all final patches, validation, release, commit, push, and owner-facing closeout.

## Agents

- [한결](hangyeol.md): codec architecture, rollback, ownership, resource lifetime.
- [서린](seorin.md): QA skepticism, false-confidence control, fixture truth.
- [유진](yujin.md): encoder import/queue/export workflow and interaction clarity.

## Invocation Rule

When a task needs one of these viewpoints, Dex may send a bounded packet through
`docs/agent_communication/scripts/jammini_delegate.sh` or create a physical handoff under
`docs/agent_communication/sentinel/handoffs/`. The role card is the stable prompt source.

## Output Rule

Each agent reports in Korean honorific style and keeps results short. The
default output is review/support only unless Dex explicitly assigns a code
change and the owner has approved the affected behavior.

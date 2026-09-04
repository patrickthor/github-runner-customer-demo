# Steering documents for the two module repos

These are written to be **copied**, not referenced. They live here so this repo has
one place to keep them in sync; they do nothing while they sit in `docs/`.

| File | Paste into | As |
|---|---|---|
| `identity-governance-contract.md` | **both** module repos | `.kiro/steering/identity-governance-contract.md` |
| `access-vending-module.md` | `terraform-azuread-access-vending-development` | `.kiro/steering/access-vending-module.md` |
| `access-packages-module.md` | `terraform-azuread-access-packages-development` | `.kiro/steering/access-packages-module.md` |

`identity-governance-contract.md` must be **byte-identical in both repos**. It is the
shared goal and the interface between them. When it changes, it changes in both, in the
same PR pair, and `contract_version` moves.

The two repo-specific files may diverge freely. They describe what each side owns and
what it must not do.

## Why the split

A single combined document would mean repo 1 carries prose about catalogs it never
creates, and repo 2 carries prose about PIM policies it never writes. Each repo's agent
would then have to work out which half applies to it. The shared file holds only what
both sides must agree on; everything else is local.

## Keeping them in sync

```bash
# from this repo, after editing the shared doc
diff docs/steering/identity-governance-contract.md \
     ../terraform-azuread-access-vending-development/.kiro/steering/identity-governance-contract.md
diff docs/steering/identity-governance-contract.md \
     ../terraform-azuread-access-packages-development/.kiro/steering/identity-governance-contract.md
```

A `validate.yml` step in each module repo that fails when its copy differs from the
version in the other repo is worth adding once both are tagged.

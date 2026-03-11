# Data Model: Portable Worktree Skill Extraction

## Entity: PortableRepository

- `name` (string, required): canonical standalone repo name, default `worktree-skill`
- `versioning_policy` (string, required): semantic versioning and compatibility contract
- `layout_version` (string, required): version of canonical directory layout
- `supports_copy_install` (boolean, required)
- `supports_bootstrap_install` (boolean, required)
- `supports_register_step` (boolean, required)

## Entity: PortableCoreArtifact

- `artifact_id` (string, required): stable identifier for a reusable core asset
- `source_origin` (string, required): current repo source path from which the artifact is extracted
- `target_path` (string, required): destination path inside the standalone repo
- `artifact_type` (enum, required): `instruction` | `command_prompt` | `script` | `template` | `doc` | `verification`
- `portability_state` (enum, required): `portable_as_is` | `needs_templating` | `needs_rename` | `conflicted`
- `required_for_mvp` (boolean, required)

## Entity: AdapterSurface

- `adapter_id` (string, required): `claude-code` | `codex-cli` | `opencode`
- `install_path` (string, required)
- `registration_mode` (enum, required): `none` | `manual` | `scripted`
- `discovery_contract` (string, required)
- `core_behavior_override_allowed` (boolean, required, default `false`)
- `support_level` (enum, required): `supported` | `partial` | `planned`

## Entity: SpeckitBridgeLayer

- `bridge_id` (string, required): stable identifier for Speckit compatibility assets
- `coexists_with_spec_artifacts` (boolean, required)
- `preserves_speckit_commands` (boolean, required)
- `supports_branch_spec_alignment` (boolean, required)
- `supports_worktree_handoff` (boolean, required)
- `notes` (string, optional)

## Entity: InstallProfile

- `profile_id` (string, required): `copy-only` | `copy-bootstrap` | `copy-register`
- `required_steps` (array[string], required)
- `optional_steps` (array[string], optional)
- `verification_steps` (array[string], required)
- `supported_surfaces` (array[string], required)

## Entity: VerificationProbe

- `probe_id` (string, required)
- `scope` (enum, required): `core` | `adapter` | `bridge` | `migration`
- `command_or_check` (string, required)
- `expected_signal` (string, required)
- `failure_signal` (string, required)
- `recovery_action` (string, required)

## Entity: InventoryRecord

- `source_path` (string, required)
- `current_role` (string, required)
- `classification` (enum, required): `portable_core` | `adapter_only` | `bridge_only` | `host_only` | `needs_templating` | `conflict`
- `action` (string, required): extraction or retention decision
- `notes` (string, optional)

## Entity: MigrationRecipe

- `recipe_id` (string, required)
- `source_mode` (enum, required): `in_repo_skill` | `partial_vendor_copy`
- `target_mode` (enum, required): `standalone_repo`
- `steps` (array[string], required)
- `rollback_steps` (array[string], optional)
- `verification_probe_ids` (array[string], required)

## Entity: ExampleProject

- `example_id` (string, required): `greenfield` | `existing-project`
- `host_characteristics` (array[string], required)
- `selected_install_profile` (string, required)
- `selected_adapters` (array[string], required)
- `selected_bridge_layers` (array[string], optional)

## Entity: ReleaseReadinessChecklist

- `check_id` (string, required)
- `category` (enum, required): `layout` | `install` | `adapter` | `bridge` | `migration` | `release`
- `description` (string, required)
- `required_for_portable_repo_ready` (boolean, required)
- `evidence_location` (string, optional)

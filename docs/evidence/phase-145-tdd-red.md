# Phase 145 TDD RED evidence

## 145.1 runtime helper cache closure

Before adding the three review helpers to the explicit critical-files list, run:

    bash tests/test-sync-plugin-cache.sh

The fixture failed because the versioned cache did not contain:

    sync-plugin-cache did not restore current executable helper:
    .../scripts/harness-pr-review-gate.sh

## 145.2 active-install diagnosis

Before the active registry field and classifier existed, the focused Go test
failed to compile with:

    unknown field ClaudePluginRegistry in struct literal of type migrationReportEnv

The review follow-up first made an active install helper differ from its source
and then ran:

    go test ./go/cmd/harness -run TestBuildExistingUserMigrationReportClassifiesOnlyActiveClaudePlugin -count=1

The pre-fix result was:

    Claude plugin cache status = "ok", want "warn"

The green test fixes that false-green and also covers unreadable source version.

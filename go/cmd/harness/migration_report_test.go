package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestBuildExistingUserMigrationReportDetectsRisks(t *testing.T) {
	projectRoot := t.TempDir()
	home := t.TempDir()
	codexHome := filepath.Join(home, ".codex")
	claudeCache := filepath.Join(home, ".claude", "plugins", "cache")
	harnessMemHome := filepath.Join(home, ".harness-mem")

	writeTestFile(t, filepath.Join(projectRoot, ".claude-plugin", "plugin.json"), `{"name":"claude-code-harness","version":"4.11.3","skills":["./skills/"]}`)

	cachedPlugin := filepath.Join(claudeCache, "claude-code-harness-old")
	writeTestFile(t, filepath.Join(cachedPlugin, "plugin.json"), `{"name":"claude-code-harness","version":"4.0.0","skills":["./skills/"]}`)
	writeSkill(t, filepath.Join(cachedPlugin, "skills", "harness-plan"), "harness-plan")

	writeSkill(t, filepath.Join(codexHome, "skills", "harness-plan"), "harness-plan")
	writeSkill(t, filepath.Join(codexHome, "skills", "old-plan-alias"), "harness-plan")
	makeBrokenSymlink(t, filepath.Join(codexHome, "skills", "old-symlink"), "/missing/claude-code-harness/harness-skill")

	if err := os.MkdirAll(filepath.Join(projectRoot, ".opencode", "skills"), 0o755); err != nil {
		t.Fatalf("mkdir opencode skills: %v", err)
	}
	makeBrokenSymlink(t, filepath.Join(projectRoot, ".opencode", "skills", "harness-plan"), "/missing/claude-code-harness/opencode-skill")

	writeTestFile(t, filepath.Join(projectRoot, ".harness-mem", "state", "continuity.json"), `{}`)
	writeTestFile(t, filepath.Join(harnessMemHome, "harness-mem.db"), ``)

	report := buildExistingUserMigrationReport(projectRoot, migrationReportEnv{
		Home:              home,
		CodexHome:         codexHome,
		ClaudePluginCache: claudeCache,
		HarnessMemHome:    harnessMemHome,
	})

	assertReportEntry(t, report, "Claude plugin cache", "not_observed", "registry was missing or unreadable")
	assertReportEntry(t, report, "Claude slash entries", "not_observed", "No cached Harness plugin skills")
	assertReportEntry(t, report, "Codex duplicate local skills", "warn", "harness-plan")
	assertReportEntry(t, report, "Codex old symlinks", "warn", "broken symlink")
	assertReportEntry(t, report, "Codex backup path", "ok", "backups/setup-codex")
	assertReportEntry(t, report, "OpenCode old symlinks", "warn", "broken symlink")
	assertReportEntry(t, report, "OpenCode backup path", "ok", ".opencode/skills.backup.<timestamp>")
	assertReportEntry(t, report, "harness-mem state", "observed", "harness-mem.db")
	assertReportEntry(t, report, "Destructive cleanup gate", "ok", "report never deletes")
}

func TestPrintExistingUserMigrationReportDocumentsRollbackBoundary(t *testing.T) {
	report := existingUserMigrationReport{
		ProjectRoot:        "/repo",
		DestructiveCleanup: "disabled: report only",
		Entries: []migrationReportEntry{
			{
				Area:             "harness-mem state",
				Status:           "observed",
				Path:             "/home/.harness-mem",
				Evidence:         "harness-mem.db",
				Impact:           "preserve memory",
				BackupLocation:   "/home/.harness-mem",
				RollbackProposal: "use harness mem doctor; purge only with explicit confirmation",
				SupportBoundary:  "The report does not read or delete the memory DB contents.",
			},
		},
	}

	var buf bytes.Buffer
	stdout := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	os.Stdout = w
	printExistingUserMigrationReport(report)
	_ = w.Close()
	os.Stdout = stdout
	if _, err := buf.ReadFrom(r); err != nil {
		t.Fatalf("read pipe: %v", err)
	}
	out := buf.String()
	for _, want := range []string{
		"Existing User Migration Report",
		"Destructive cleanup: disabled",
		"rollback:",
		"purge only with explicit confirmation",
		"does not read or delete the memory DB contents",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("expected output to contain %q, got:\n%s", want, out)
		}
	}
}

func TestBuildExistingUserMigrationReportClassifiesOnlyActiveClaudePlugin(t *testing.T) {
	projectRoot := t.TempDir()
	home := t.TempDir()
	cacheRoot := filepath.Join(home, ".claude", "plugins", "cache")
	registryPath := filepath.Join(home, ".claude", "plugins", "installed_plugins.json")
	current := filepath.Join(cacheRoot, "claude-code-harness-current")
	historical := filepath.Join(cacheRoot, "claude-code-harness-historical")

	writeTestFile(t, filepath.Join(projectRoot, ".claude-plugin", "plugin.json"), `{"name":"claude-code-harness","version":"5.9.1","skills":["./skills/"]}`)
	writeTestFile(t, filepath.Join(current, "plugin.json"), `{"name":"claude-code-harness","version":"5.9.1","skills":["./skills/"]}`)
	writeTestFile(t, filepath.Join(historical, "plugin.json"), `{"name":"claude-code-harness","version":"5.8.0","skills":["./skills/"]}`)
	for _, skill := range migrationRequiredSkills {
		writeSkill(t, filepath.Join(current, "skills", skill), skill)
	}
	for _, helper := range []string{"harness-pr-review-gate.sh", "write-review-result.sh", "harness-pr-closeout.sh"} {
		writeTestFile(t, filepath.Join(current, "scripts", helper), "#!/bin/sh\n")
	}
	writeTestFile(t, registryPath, `{"plugins":{"claude-code-harness@claude-code-harness-marketplace":[{"version":"5.9.1","installPath":"`+current+`"}]}}`)

	env := migrationReportEnv{
		Home:                 home,
		CodexHome:            filepath.Join(home, ".codex"),
		ClaudePluginCache:    cacheRoot,
		ClaudePluginRegistry: registryPath,
		HarnessMemHome:       filepath.Join(home, ".harness-mem"),
	}
	report := buildExistingUserMigrationReport(projectRoot, env)
	assertReportEntry(t, report, "Claude plugin cache", "ok", "active plugin")

	writeTestFile(t, registryPath, `{"plugins":{"claude-code-harness@claude-code-harness-marketplace":[{"version":"5.8.0","installPath":"`+historical+`"}]}}`)
	report = buildExistingUserMigrationReport(projectRoot, env)
	assertReportEntry(t, report, "Claude plugin cache", "warn", "claude plugin update claude-code-harness@claude-code-harness-marketplace")

	writeTestFile(t, registryPath, `{"plugins":{}}`)
	report = buildExistingUserMigrationReport(projectRoot, env)
	assertReportEntry(t, report, "Claude plugin cache", "observed", "historical cache only")
}

func writeSkill(t *testing.T, dir, name string) {
	t.Helper()
	writeTestFile(t, filepath.Join(dir, "SKILL.md"), "---\nname: "+name+"\n---\n")
}

func writeTestFile(t *testing.T, path, contents string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
	}
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func makeBrokenSymlink(t *testing.T, path, target string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir %s: %v", filepath.Dir(path), err)
	}
	if err := os.Symlink(target, path); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
}

func assertReportEntry(t *testing.T, report existingUserMigrationReport, area, status, evidenceContains string) {
	t.Helper()
	for _, entry := range report.Entries {
		if entry.Area != area {
			continue
		}
		if entry.Status != status {
			t.Fatalf("%s status = %q, want %q", area, entry.Status, status)
		}
		combined := strings.Join([]string{entry.Evidence, entry.Impact, entry.BackupLocation, entry.RollbackProposal, entry.SupportBoundary}, "\n")
		if !strings.Contains(combined, evidenceContains) {
			t.Fatalf("%s evidence does not contain %q:\n%s", area, evidenceContains, combined)
		}
		return
	}
	t.Fatalf("missing report entry %q", area)
}

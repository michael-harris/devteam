# DevTeam Database Initialization (PowerShell)
# Creates and initializes the SQLite database if it doesn't exist

$ErrorActionPreference = "Stop"

# Configuration
$DEVTEAM_DIR = if ($env:DEVTEAM_DIR) { $env:DEVTEAM_DIR } else { ".devteam" }
$DB_FILE = Join-Path $DEVTEAM_DIR "devteam.db"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$SCHEMA_FILE = Join-Path $SCRIPT_DIR "schema.sql"
$SCHEMA_V2_FILE = Join-Path $SCRIPT_DIR "schema-v2.sql"
$SCHEMA_V3_FILE = Join-Path $SCRIPT_DIR "schema-v3.sql"
$SCHEMA_V4_FILE = Join-Path $SCRIPT_DIR "schema-v4.sql"
$SCHEMA_V5_FILE = Join-Path $SCRIPT_DIR "schema-v5.sql"

# Current schema version - increment when schema changes
$SCHEMA_VERSION = 5

function Write-DevTeamInfo {
    param([string]$Message)
    Write-Host "[devteam] $Message" -ForegroundColor Green
}

function Write-DevTeamWarn {
    param([string]$Message)
    Write-Host "[devteam] $Message" -ForegroundColor Yellow
}

function Write-DevTeamError {
    param([string]$Message)
    Write-Host "[devteam] $Message" -ForegroundColor Red
}

# Check for sqlite3
function Test-SQLite {
    try {
        $null = & sqlite3 --version 2>&1
        return $true
    } catch {
        Write-DevTeamError "sqlite3 is not installed. Please install it:"
        Write-DevTeamError "  Windows: Download from https://sqlite.org/download.html"
        Write-DevTeamError "  Or use: choco install sqlite"
        Write-DevTeamError "  Or use: winget install SQLite.SQLite"
        return $false
    }
}

# Create .devteam directory if needed
function Initialize-DevTeamDir {
    if (-not (Test-Path $DEVTEAM_DIR)) {
        New-Item -ItemType Directory -Path $DEVTEAM_DIR -Force | Out-Null
        Write-DevTeamInfo "Created $DEVTEAM_DIR directory"
    }
}

# Execute SQL with foreign keys enabled
function Invoke-SqlExec {
    param([string]$Sql)
    & sqlite3 $DB_FILE "PRAGMA foreign_keys = ON; $Sql"
}

# Get current schema version from database
function Get-DbSchemaVersion {
    if (-not (Test-Path $DB_FILE)) {
        return 0
    }

    # Check if schema_version table exists
    $tableExists = & sqlite3 $DB_FILE "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='schema_version';" 2>$null
    if (-not $tableExists -or $tableExists -eq "0") {
        return 0
    }

    # Get the version
    # Order by version DESC (not just applied_at DESC): CURRENT_TIMESTAMP has only
    # second-level resolution, so two migrations applied in the same second tie on
    # applied_at and SQLite's tie-break order is unspecified without this.
    $version = & sqlite3 $DB_FILE "SELECT version FROM schema_version ORDER BY version DESC, applied_at DESC LIMIT 1;" 2>$null
    if (-not $version) { return 0 }
    return [int]$version
}

# Run migrations from current version to target version
function Invoke-Migrations {
    param([int]$FromVersion)

    # Migration v1 -> v2: Add acceptance criteria, features, context management
    if ($FromVersion -lt 2) {
        Write-DevTeamInfo "Running migration v1 -> v2..."
        if (Test-Path $SCHEMA_V2_FILE) {
            $v2Content = Get-Content $SCHEMA_V2_FILE -Raw
            try {
                & sqlite3 $DB_FILE "BEGIN TRANSACTION; $v2Content COMMIT;"
            } catch {
                & sqlite3 $DB_FILE "ROLLBACK;" 2>$null
                Write-DevTeamError "Failed to apply schema v2 migration"
                exit 1
            }
            Write-DevTeamInfo "Applied schema v2: acceptance_criteria, features, context_snapshots, context_budgets, progress_summaries, session_phases"
        }
    }

    # Migration v2 -> v3: Add tasks table for hook integration
    if ($FromVersion -lt 3) {
        Write-DevTeamInfo "Running migration v2 -> v3..."
        if (Test-Path $SCHEMA_V3_FILE) {
            $v3Content = Get-Content $SCHEMA_V3_FILE -Raw
            try {
                & sqlite3 $DB_FILE "BEGIN TRANSACTION; $v3Content COMMIT;"
            } catch {
                & sqlite3 $DB_FILE "ROLLBACK;" 2>$null
                Write-DevTeamError "Failed to apply schema v3 migration"
                exit 1
            }
            Write-DevTeamInfo "Applied schema v3: tasks, task_attempts, task_files tables"
        }
    }

    # Migration v3 -> v4: Fix plans.research_session_id foreign key
    if ($FromVersion -lt 4) {
        Write-DevTeamInfo "Running migration v3 -> v4..."
        if (Test-Path $SCHEMA_V4_FILE) {
            $v4Content = Get-Content $SCHEMA_V4_FILE -Raw
            try {
                & sqlite3 $DB_FILE "BEGIN TRANSACTION; $v4Content COMMIT;"
            } catch {
                & sqlite3 $DB_FILE "ROLLBACK;" 2>$null
                Write-DevTeamError "Failed to apply schema v4 migration"
                exit 1
            }
            Write-DevTeamInfo "Applied schema v4: plans.research_session_id ON DELETE SET NULL"
        }
    }

    # Migration v4 -> v5: Add agent_runs call-hierarchy columns
    if ($FromVersion -lt 5) {
        Write-DevTeamInfo "Running migration v4 -> v5..."
        if (Test-Path $SCHEMA_V5_FILE) {
            $v5Content = Get-Content $SCHEMA_V5_FILE -Raw
            try {
                & sqlite3 $DB_FILE "BEGIN TRANSACTION; $v5Content COMMIT;"
            } catch {
                & sqlite3 $DB_FILE "ROLLBACK;" 2>$null
                Write-DevTeamError "Failed to apply schema v5 migration"
                exit 1
            }
            Write-DevTeamInfo "Applied schema v5: agent_runs.invoked_by_agent / invoked_by_run_id"
        }
    }

    # Update schema version
    Invoke-SqlExec "INSERT OR IGNORE INTO schema_version (version) VALUES ($SCHEMA_VERSION);"
    Write-DevTeamInfo "Migrations complete, now at v$SCHEMA_VERSION"
}

# Validate schema version and critical tables after migration
function Test-SchemaValid {
    $actualVersion = Get-DbSchemaVersion

    if ($actualVersion -ne $SCHEMA_VERSION) {
        Write-DevTeamError "Schema validation failed: expected v$SCHEMA_VERSION, got v$actualVersion"
        exit 1
    }

    # Verify critical tables exist
    $criticalTables = @("sessions", "events", "agent_runs", "plans", "tasks", "schema_version")
    foreach ($table in $criticalTables) {
        $exists = & sqlite3 $DB_FILE "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$table';" 2>$null
        if (-not $exists -or $exists -eq "0") {
            Write-DevTeamError "Schema validation failed: missing critical table '$table'"
            exit 1
        }
    }

    Write-DevTeamInfo "Schema validation passed (v$SCHEMA_VERSION)"
}

# Initialize database
function Initialize-Database {
    $currentVersion = Get-DbSchemaVersion

    if (-not (Test-Path $DB_FILE)) {
        Write-DevTeamInfo "Initializing DevTeam database..."

        if (-not (Test-Path $SCHEMA_FILE)) {
            Write-DevTeamError "Schema file not found: $SCHEMA_FILE"
            exit 1
        }

        # Create database with schema
        $schemaContent = Get-Content $SCHEMA_FILE -Raw
        & sqlite3 $DB_FILE $schemaContent

        # Create schema_version table before migrations
        Invoke-SqlExec "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);"

        # Apply schema v2
        if (Test-Path $SCHEMA_V2_FILE) {
            $v2Content = Get-Content $SCHEMA_V2_FILE -Raw
            try {
                & sqlite3 $DB_FILE $v2Content
            } catch {
                Write-DevTeamError "Failed to apply schema v2"
                exit 1
            }
            Write-DevTeamInfo "Applied schema v2 (acceptance criteria, features, context management)"
        }

        # Apply schema v3
        if (Test-Path $SCHEMA_V3_FILE) {
            $v3Content = Get-Content $SCHEMA_V3_FILE -Raw
            try {
                & sqlite3 $DB_FILE $v3Content
            } catch {
                Write-DevTeamError "Failed to apply schema v3"
                exit 1
            }
            Write-DevTeamInfo "Applied schema v3 (tasks table for hook integration)"
        }

        # Apply schema v4
        if (Test-Path $SCHEMA_V4_FILE) {
            $v4Content = Get-Content $SCHEMA_V4_FILE -Raw
            try {
                & sqlite3 $DB_FILE $v4Content
            } catch {
                Write-DevTeamError "Failed to apply schema v4"
                exit 1
            }
            Write-DevTeamInfo "Applied schema v4 (plans.research_session_id ON DELETE SET NULL)"
        }

        # Apply schema v5
        if (Test-Path $SCHEMA_V5_FILE) {
            $v5Content = Get-Content $SCHEMA_V5_FILE -Raw
            try {
                & sqlite3 $DB_FILE $v5Content
            } catch {
                Write-DevTeamError "Failed to apply schema v5"
                exit 1
            }
            Write-DevTeamInfo "Applied schema v5 (agent_runs call-hierarchy columns)"
        }

        # Record schema version
        Invoke-SqlExec "INSERT INTO schema_version (version) VALUES ($SCHEMA_VERSION);"

        Write-DevTeamInfo "Database created: $DB_FILE (schema v$SCHEMA_VERSION)"
    } elseif ($currentVersion -eq 0) {
        Write-DevTeamInfo "Database exists but no schema version, updating..."

        # Create schema version table
        Invoke-SqlExec "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);"

        # Re-run base schema to add any missing tables (IF NOT EXISTS handles this safely)
        $schemaContent = Get-Content $SCHEMA_FILE -Raw
        try {
            & sqlite3 $DB_FILE $schemaContent 2>$null
        } catch {
            # Ignore errors from IF NOT EXISTS
        }

        # Record v1 as the base version from schema.sql
        Invoke-SqlExec "INSERT OR IGNORE INTO schema_version (version) VALUES (1);"

        # Apply remaining migrations (v2, v3, v4) that the base schema doesn't include
        Invoke-Migrations -FromVersion 1

        # Validate schema after migrations
        Test-SchemaValid
        Write-DevTeamInfo "Schema updated to v$SCHEMA_VERSION"
    } elseif ($currentVersion -lt $SCHEMA_VERSION) {
        Write-DevTeamInfo "Database schema upgrade needed: v$currentVersion -> v$SCHEMA_VERSION"
        Invoke-Migrations -FromVersion $currentVersion

        # Validate schema version after migration
        Test-SchemaValid
    } else {
        Write-DevTeamInfo "Database schema is current (v$currentVersion)"
    }
}

# Verify database integrity
function Test-DatabaseIntegrity {
    $integrity = & sqlite3 $DB_FILE "PRAGMA integrity_check;"

    if ($integrity -ne "ok") {
        Write-DevTeamError "Database integrity check failed!"
        Write-DevTeamError "Consider backing up and reinitializing: Move-Item $DB_FILE ${DB_FILE}.bak"
        exit 1
    }
}

# Clean up old state files (migration from YAML to SQLite)
# IMPORTANT: state.yaml is DEPRECATED. SQLite (.devteam/devteam.db) is the source of truth.
function Remove-OldStateFiles {
    $oldFiles = @(
        (Join-Path $DEVTEAM_DIR "state.yaml"),
        (Join-Path $DEVTEAM_DIR "circuit-breaker.json"),
        (Join-Path $DEVTEAM_DIR "rate-limit-state.json"),
        (Join-Path $DEVTEAM_DIR "abandonment-attempts.log")
    )

    foreach ($file in $oldFiles) {
        if (Test-Path $file) {
            Write-DevTeamWarn "DEPRECATED state file found: $file"
            Write-DevTeamWarn "  SQLite is now the sole source of truth for all state management."
            Write-DevTeamWarn "  The file '$file' is no longer read by any DevTeam component."
            Write-DevTeamWarn "  Remove it: Remove-Item $file"
        }
    }

    # Also check for old project-state YAML files in docs/planning/
    $planningDir = "docs/planning"
    if (Test-Path $planningDir) {
        $stateYamlFiles = Get-ChildItem -Path $planningDir -Filter "*-state.yaml" -ErrorAction SilentlyContinue
        if ($stateYamlFiles) {
            Write-DevTeamWarn "DEPRECATED planning state YAML files found:"
            foreach ($f in $stateYamlFiles) {
                Write-DevTeamWarn "  $($f.FullName)"
            }
            Write-DevTeamWarn "  State is now managed in SQLite ($DB_FILE). These files are no longer used."
            Write-DevTeamWarn "  Remove them after verifying your project state has been migrated."
        }
    }
}

# Main
function Main {
    if (-not (Test-SQLite)) {
        exit 1
    }

    Initialize-DevTeamDir
    Initialize-Database
    Test-DatabaseIntegrity
    Remove-OldStateFiles

    Write-DevTeamInfo "Database ready: $DB_FILE"
}

# Run if executed directly
if ($MyInvocation.InvocationName -ne '.') {
    Main
}

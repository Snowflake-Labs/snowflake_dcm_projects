# DCM Project Structure Reference

This document describes the structure of DCM (Database Change Management) projects, including the manifest file, definition patterns, and configuration management.

> **Note for Cortex Agents**: This document covers project structure only. For DCM definition syntax (`DEFINE` statements, grants, data quality, etc.), see `reference/syntax.md`.

---

## Project Overview

A DCM project is a directory containing:

1. **`manifest.yml`** — The project manifest (required)
2. **Definition files** — SQL files with `DEFINE` statements (`.sql` files) in `sources/definitions/`

### Recommended Structure

The project layout uses a fixed `sources/definitions/` folder:

```
my_project/
├── manifest.yml
└── sources/
    ├── definitions/
    │   ├── <definition_name>.sql
    │   ├── <definition_name>.sql
    │   └── <definition_name>.sql
    └── macros/
        └── <macro_name>.sql
```

> **Macros directory**: Place global Jinja macro files in `sources/macros/`. Unlike macros defined inline in definition files, macros in `sources/macros/` are accessible from all definition files.

> **Important**: In manifest v2, definition files must be placed in `sources/definitions/`. This path is fixed and auto-discovered. Nest files logically within `sources/definitions/`, for example by purpose ('raw', 'analytics') or areas ('product', 'sales', 'marketing'). In simple cases, prefer a flat structure.

### Alternative Structures

More complex structures are possible (nested folders within `sources/definitions/`), they add complexity without significant benefit for most use cases:

```
# More complex example — works but not recommended for most simple projects
project/
├── manifest.yml
└── sources/
    └── definitions/
        ├── expectations.sql
        ├── grants.sql
        ├── high_level_objects.sql
        ├── TPCDI_ODS/
        │   └── DYNAMIC_TABLES.sql
        ├── TPCDI_STG/
        │   ├── DYNAMIC_TABLES.sql
        │   └── TABLES.sql
        └── TPCDI_WH/
            ├── DYNAMIC_TABLES.sql
            └── VIEWS.sql
```

---

## The Manifest File (`manifest.yml`)

The manifest file is the heart of a DCM project. It defines deployment targets, templating configurations, and project metadata.

### Complete Schema

```yaml
# Required: Manifest version
manifest_version: 2

# Required: Project type identifier, must match exactly
type: DCM_PROJECT

# Optional: Default target used when --target is not specified
default_target: 'DEV'

# Required: Deployment targets
targets:
  DEV:
    account_identifier: MY_DEV_ACCOUNT
    project_name: 'MY_DB.MY_SCHEMA.MY_PROJECT_DEV'
    project_owner: DCM_DEVELOPER
    templating_config: 'DEV'
  PROD:
    account_identifier: MY_PROD_ACCOUNT
    project_name: 'MY_DB.MY_SCHEMA.MY_PROJECT'
    project_owner: DCM_PROD_DEPLOYER
    templating_config: 'PROD'

# Optional: Jinja templating variables
templating:
  defaults:
    suffix: '_DEV'
    wh_size: 'XSMALL'
  configurations:
    DEV:
      wh_size: 'XSMALL'
    PROD:
      wh_size: 'LARGE'
      suffix: ''
```

### Required Fields

> **Manifest Schema:** Only the fields documented below are valid. Any other fields will cause "is not defined in the schema" errors.

#### `manifest_version`

**Type**: `number`

The manifest schema version. Use version `2`.

```yaml
manifest_version: 2
```

#### `type`

**Type**: `string` (case-insensitive, must match `DCM_PROJECT`)

Identifies this as a DCM project. MUST always be set to `DCM_PROJECT`.

```yaml
type: DCM_PROJECT
```

#### `default_target`

**Type**: `string`, Optional

The name of the target to use when `--target` is not specified on the CLI. Must match a key in the `targets` section.

```yaml
default_target: 'DEV'
```

#### `targets`

**Type**: `object` (Record of target names to target configurations)

Defines named deployment targets. Each target specifies:

- `account_identifier` (optional): The Snowflake account identifier for this target (run `SELECT CURRENT_ACCOUNT()` to find yours)
- `project_name` (required): The fully qualified DCM project identifier (`DATABASE.SCHEMA.PROJECT_NAME`)
- `project_owner` (optional): The role with OWNERSHIP on the DCM project object (run `DESCRIBE DCM PROJECT` to find the owner)
- `templating_config` (optional): Which templating configuration to use for this target

```yaml
targets:
  DEV:
    account_identifier: MY_DEV_ACCOUNT
    project_name: 'MY_DB.MY_SCHEMA.MY_PROJECT_DEV'
    project_owner: DCM_DEVELOPER
    templating_config: 'DEV'
  PROD:
    account_identifier: MY_PROD_ACCOUNT
    project_name: 'MY_DB.MY_SCHEMA.MY_PROJECT'
    project_owner: DCM_PROD_DEPLOYER
    templating_config: 'PROD'
```

> **Best Practice**: Embed the project identifier in the manifest targets rather than passing it as a CLI argument. This makes the project self-describing and eliminates the need to remember fully qualified identifiers.

> **Note**: The `--target` CLI flag refers to target names defined here (e.g., `--target DEV`). Each target can point to a different DCM project and a different templating configuration.

### Optional Fields

#### `templating`

**Type**: `object` with `defaults` and `configurations` sub-keys

Defines Jinja template variables available in definition files. This section is entirely optional and only needed when definitions use Jinja templating.

- `defaults`: Variables shared across all configurations. These are used as-is when a configuration does not override them.
- `configurations`: Named sets of variable overrides. Each configuration can override any default value.

```yaml
templating:
  defaults:
    retention: '14 days'
    units: 'metric'
    suffix: '_DEV'
  configurations:
    DEV:
      wh_size: 'XSMALL'
    STAGE:
      wh_size: 'SMALL'
      suffix: '_STG'
    PROD:
      wh_size: 'LARGE'
      suffix: ''
```

When a target specifies `templating_config: 'PROD'`, the template variables are resolved by merging `defaults` with the `PROD` configuration (configuration values take precedence over defaults).

## Targets and Environments

Targets are the primary mechanism for managing environment-specific deployments. Each target bundles a project identifier with a templating configuration.

### Basic Target Structure

```yaml
targets:
  TARGET_NAME:
    account_identifier: MY_ACCOUNT
    project_name: 'DATABASE.SCHEMA.PROJECT_NAME'
    project_owner: DCM_ROLE
    templating_config: 'CONFIGURATION_NAME'
```

### Multi-Target Patterns

#### Separate Projects Per Environment

```yaml
targets:
  DEV:
    account_identifier: DEV_ACCOUNT
    project_name: 'DEV_DB.PROJECTS.MY_PROJECT_DEV'
    project_owner: DCM_DEVELOPER
    templating_config: 'DEV'
  PROD:
    account_identifier: PROD_ACCOUNT
    project_name: 'PROD_DB.PROJECTS.MY_PROJECT'
    project_owner: DCM_PROD_DEPLOYER
    templating_config: 'PROD'
```

#### Same Project, Different Configurations

```yaml
targets:
  DEV:
    account_identifier: MY_ACCOUNT
    project_name: 'MY_DB.PROJECTS.MY_PROJECT'
    project_owner: DCM_DEVELOPER
    templating_config: 'DEV'
  PROD:
    account_identifier: MY_ACCOUNT
    project_name: 'MY_DB.PROJECTS.MY_PROJECT'
    project_owner: DCM_PROD_DEPLOYER
    templating_config: 'PROD'
```

#### Multi-Region Deployments

```yaml
targets:
  DEV:
    account_identifier: DEV_ACCOUNT
    project_name: 'DEV_DB.PROJECTS.MY_PROJECT_DEV'
    project_owner: DCM_DEVELOPER
    templating_config: 'DEV'
  PROD_EU:
    account_identifier: PROD_EU_ACCOUNT
    project_name: 'PROD_DB.PROJECTS.MY_PROJECT'
    project_owner: DCM_PROD_DEPLOYER
    templating_config: 'PROD'
  PROD_US:
    account_identifier: PROD_US_ACCOUNT
    project_name: 'PROD_DB.PROJECTS.MY_PROJECT'
    project_owner: DCM_PROD_DEPLOYER
    templating_config: 'PROD'
```

> **Many-to-many**: Multiple targets can share the same `templating_config`. In this example, both PROD_EU and PROD_US use the PROD configuration but deploy to different accounts.

## Templating Configuration

The `templating` section provides Jinja template variables to definition files. It has two sub-keys:

- **`defaults`**: Base values shared by all configurations
- **`configurations`**: Named overrides that selectively replace default values

### How Variable Resolution Works

When a target specifies `templating_config: 'PROD'`, the effective variables are computed by merging `defaults` with the `PROD` configuration. Configuration values take precedence.

### Variable Resolution Hierarchy

Variables are resolved in a three-tier hierarchy where later tiers override earlier ones:

1. **`templating.defaults`** -- Base values shared by all configurations
2. **`templating.configurations.<name>`** -- Configuration-specific overrides
3. **Runtime `--variable` flag** -- CLI execution-time overrides

Example: If `defaults` sets `wh_size: 'XSMALL'` and the PROD configuration sets `wh_size: 'LARGE'`, the effective value for PROD targets is `'LARGE'`. A runtime `--variable "wh_size='MEDIUM'"` would override both.

```yaml
templating:
  defaults:
    wh_size: 'XSMALL'
    suffix: '_DEV'
    retention: '14 days'
  configurations:
    DEV:
      wh_size: 'XSMALL'
    PROD:
      wh_size: 'LARGE'
      suffix: ''
```

**Effective variables for DEV**: `wh_size='XSMALL'`, `suffix='_DEV'`, `retention='14 days'`
**Effective variables for PROD**: `wh_size='LARGE'`, `suffix=''`, `retention='14 days'`

### Supported Value Types

| Type    | Example             | Usage in Jinja         |
| ------- | ------------------- | ---------------------- |
| String  | `db: "PROD"`        | `{{db}}`               |
| Number  | `timeout: 300`      | `{{timeout}}`          |
| Boolean | `enabled: true`     | `{% if enabled %}`     |
| Array   | `users: ["A", "B"]` | `{% for u in users %}` |
| Dict    | `teams: [{name: "HR", wh_size: "LARGE"}]` | `{% for team in teams %}{{ team.name }}{% endfor %}` |

### Common Templating Patterns

#### Environment-Based Sizing

```yaml
templating:
  defaults:
    wh_size: 'XSMALL'
  configurations:
    DEV:
      wh_size: 'XSMALL'
    TEST:
      wh_size: 'SMALL'
    PROD:
      wh_size: 'LARGE'
```

**Usage in definitions**:

```sql
DEFINE WAREHOUSE PROJECT_WH
WITH
    WAREHOUSE_SIZE = '{{wh_size}}'
    AUTO_SUSPEND = 300;
```

**Result for DEV**: Creates `PROJECT_WH` with size `XSMALL`
**Result for PROD**: Creates `PROJECT_WH` with size `LARGE`

#### Environment Suffixes

Use suffixes to create distinct object names per environment:

```yaml
templating:
  defaults:
    env_suffix: '_DEV'
  configurations:
    DEV:
      env_suffix: '_DEV'
    PROD:
      env_suffix: ''
```

**Usage in definitions**:

```sql
DEFINE DATABASE MY_PROJECT{{env_suffix}};
DEFINE SCHEMA MY_PROJECT{{env_suffix}}.RAW;
```

**Result for DEV**: Creates `MY_PROJECT_DEV.RAW`
**Result for PROD**: Creates `MY_PROJECT.RAW`

#### User and Role Management

```yaml
templating:
  defaults:
    project_owner_role: 'DCM_DEVELOPER'
    users:
      - 'DEV_USER'
  configurations:
    DEV:
      project_owner_role: 'DCM_DEVELOPER'
      users:
        - 'DEV_USER'
    PROD:
      project_owner_role: 'DCM_PROD_DEPLOYER'
      users:
        - 'GITHUB_ACTIONS_SERVICE_USER'
        - 'ADMIN_USER'
```

**Usage in definitions**:

```sql
{% for user_name in users %}
    GRANT ROLE PROJECT_READ TO USER {{user_name}};
{% endfor %}
```

#### Team-Based Schemas

```yaml
templating:
  defaults:
    teams:
      - 'DEV_TEAM'
  configurations:
    DEV:
      teams:
        - 'DEV_TEAM'
    PROD:
      teams:
        - 'Marketing'
        - 'Finance'
        - 'HR'
        - 'Sales'
```

**Usage in definitions**:

```sql
{% for team in teams %}
    DEFINE SCHEMA MY_DB.{{ team | upper }};
{% endfor %}
```

### Complete Configuration Example

```yaml
manifest_version: 2

type: DCM_PROJECT

default_target: 'DEV'

targets:
  DEV:
    account_identifier: DEV_ACCOUNT
    project_name: 'MY_DB.PROJECTS.MY_PROJECT_DEV'
    project_owner: DCM_DEVELOPER
    templating_config: 'DEV'
  TEST:
    account_identifier: TEST_ACCOUNT
    project_name: 'MY_DB.PROJECTS.MY_PROJECT_TEST'
    project_owner: DCM_DEVELOPER
    templating_config: 'TEST'
  PROD:
    account_identifier: PROD_ACCOUNT
    project_name: 'MY_DB.PROJECTS.MY_PROJECT'
    project_owner: DCM_PROD_DEPLOYER
    templating_config: 'PROD'

templating:
  defaults:
    wh_size: 'XSMALL'
    project_owner_role: 'DCM_DEVELOPER'
    sample_size: '5'
    users:
      - 'DEV_USER'
    teams:
      - 'DEV_TEAM'

  configurations:
    DEV:
      wh_size: 'XSMALL'
      project_owner_role: 'DCM_DEVELOPER'
      sample_size: '5'
      users:
        - 'DEV_USER'
      teams:
        - 'DEV_TEAM'

    TEST:
      wh_size: 'SMALL'
      project_owner_role: 'DCM_DEVELOPER'
      sample_size: '10'
      users:
        - 'DEV_USER'
        - 'QA_USER'
      teams:
        - 'TEST_TEAM'

    PROD:
      wh_size: 'LARGE'
      project_owner_role: 'DCM_PROD_DEPLOYER'
      sample_size: '100'
      users:
        - 'GITHUB_ACTIONS_SERVICE_USER'
      teams:
        - 'Marketing'
        - 'Finance'
        - 'HR'
        - 'IT'
        - 'Sales'
```

---

## Jinja Templating in Definitions

Templating variables (from `templating.defaults` merged with the active `templating.configurations` entry) are exposed to definition files as Jinja template variables. While DCM supports the full Jinja2 templating language, keeping templates simple is strongly recommended.

### Simple Variable Substitution (Preferred)

```sql
DEFINE DATABASE MY_PROJECT_{{env_suffix}};

DEFINE WAREHOUSE MY_WH
WITH
    WAREHOUSE_SIZE = '{{wh_size}}';
```

### Loops for Lists

```sql
{% for user_name in users %}
    GRANT ROLE PROJECT_READ TO USER {{user_name}};
{% endfor %}
```

### Conditionals (Use Sparingly)

```sql
{% for team in teams %}
    DEFINE SCHEMA MY_DB.{{ team | upper }};

    {% if team == 'HR' %}
        DEFINE TABLE MY_DB.{{ team | upper }}.EMPLOYEES (
            NAME VARCHAR,
            ID INT
        );
    {% endif %}
{% endfor %}
```

### Jinja Best Practices

| Do                                     | Don't                              |
| -------------------------------------- | ---------------------------------- |
| Use simple `{{variable}}` substitution | Create deeply nested logic         |
| Keep loops straightforward             | Chain multiple conditionals        |
| Use macros for repeated patterns       | Over-engineer with complex filters |
| Make definitions readable              | Sacrifice clarity for DRY          |

> **Warning**: While Jinja is powerful, excessive templating makes definitions hard to read and debug. If you find yourself writing complex Jinja logic, consider whether simpler approaches (like separate definition files per environment) might be clearer.

---

## Definition Files

Definition files are SQL files containing DCM `DEFINE` statements. They describe the desired state of Snowflake objects. All definition files must be placed in `sources/definitions/` (or subdirectories within it).

### File Organization

Organize definition files by logical grouping:

| File                        | Contents                                   |
| --------------------------- | ------------------------------------------ |
| `database.sql` or `raw.sql` | Databases, schemas, base tables            |
| `analytics.sql`             | Dynamic tables, analytical transformations |
| `serve.sql`                 | Views for consumption                      |
| `access.sql`                | Roles, grants, permissions                 |
| `expectations.sql`          | Data metric functions, data quality rules  |

### Example: Simple Project

**`sources/definitions/database.sql`**:

```sql
DEFINE DATABASE MY_PROJECT_{{env_suffix}};
DEFINE SCHEMA MY_PROJECT_{{env_suffix}}.RAW;
DEFINE SCHEMA MY_PROJECT_{{env_suffix}}.ANALYTICS;
```

**`sources/definitions/tables.sql`**:

```sql
DEFINE TABLE MY_PROJECT_{{env_suffix}}.RAW.CUSTOMERS (
    CUSTOMER_ID NUMBER,
    NAME VARCHAR,
    EMAIL VARCHAR
)
CHANGE_TRACKING = TRUE;

DEFINE TABLE MY_PROJECT_{{env_suffix}}.RAW.ORDERS (
    ORDER_ID NUMBER,
    CUSTOMER_ID NUMBER,
    ORDER_DATE DATE,
    AMOUNT NUMBER(10,2)
)
CHANGE_TRACKING = TRUE;
```

**`sources/definitions/access.sql`**:

```sql
DEFINE WAREHOUSE MY_PROJECT_WH
WITH
    WAREHOUSE_SIZE = '{{wh_size}}'
    AUTO_SUSPEND = 300;

DEFINE ROLE MY_PROJECT_READ;

{% for user_name in users %}
    GRANT ROLE MY_PROJECT_READ TO USER {{user_name}};
{% endfor %}

GRANT USAGE ON DATABASE MY_PROJECT_{{env_suffix}} TO ROLE MY_PROJECT_READ;
GRANT USAGE ON SCHEMA MY_PROJECT_{{env_suffix}}.RAW TO ROLE MY_PROJECT_READ;
GRANT SELECT ON ALL TABLES IN DATABASE MY_PROJECT_{{env_suffix}} TO ROLE MY_PROJECT_READ;
```

## Project Structure Best Practices

### For New Projects

1. **Start with the standard structure**:

   ```
   project/
   ├── manifest.yml
   └── sources/
       └── definitions/
           └── (all .sql files here)
   ```

2. **Define targets for your environments** (at minimum: DEV and PROD)

3. **Use the `templating` section** for environment-specific variables with sensible defaults

4. **Keep Jinja simple** — prefer explicit over clever

### Naming Conventions

| Convention                      | Example                            | Purpose                             |
| ------------------------------- | ---------------------------------- | ----------------------------------- |
| Environment suffix in names     | `MY_DB_{{env_suffix}}`             | Distinguish objects per environment |
| Uppercase for Snowflake objects | `DEFINE TABLE MY_DB.RAW.CUSTOMERS` | Match Snowflake conventions         |
| Descriptive file names          | `access.sql`, `expectations.sql`   | Easy navigation                     |

### Templating Variable Naming

| Variable             | Description            | Example Values         |
| -------------------- | ---------------------- | ---------------------- |
| `env_suffix`         | Object name suffix     | `"_DEV"`, `""`         |
| `wh_size`            | Warehouse size         | `"XSMALL"`, `"LARGE"`  |
| `users`              | User list for grants   | `["USER1", "USER2"]`   |
| `teams`              | Team/schema list       | `["Finance", "HR"]`    |
| `project_owner_role` | Top-level role         | `"DCM_DEVELOPER"`      |

---

## Summary

| Component                 | Required         | Purpose                               |
| ------------------------- | ---------------- | ------------------------------------- |
| `manifest.yml`            | Yes              | Project configuration and metadata    |
| `targets`                 | Yes              | Deployment target definitions         |
| `default_target`          | Yes              | Default target when CLI omits it      |
| `templating`              | No (recommended) | Environment-specific variables        |
| `sources/definitions/`    | Yes              | SQL files with DEFINE statements      |

**The simplest valid project**:

```yaml
# manifest.yml
manifest_version: 2
type: DCM_PROJECT
default_target: 'DEV'

targets:
  DEV:
    account_identifier: MY_ACCOUNT
    project_name: 'MY_DB.MY_SCHEMA.MY_PROJECT'
    project_owner: DCM_DEVELOPER
```

```sql
-- sources/definitions/main.sql
DEFINE DATABASE MY_PROJECT;
DEFINE SCHEMA MY_PROJECT.RAW;
```

For syntax details on `DEFINE` statements, grants, and data quality rules, see `reference/syntax.md`.

# DCM Definition Syntax Reference

This document describes the syntax for defining database objects in DCM (Database Change Management) projects. DCM uses a **declarative** approach where objects are defined using the `DEFINE` keyword rather than `CREATE`, transforming imperative DDL into idempotent declarations.

> **Note for Cortex Agents**: Snowflake's standard documentation contains comprehensive DDL syntax for `CREATE` statements. DCM syntax mirrors this exactly, substituting `DEFINE` for `CREATE`. When looking up detailed property options, column types, or object-specific clauses, consult the Snowflake SQL reference documentation for the corresponding `CREATE` statement. The bundled docs **do not** contain DCM-specific syntax.

---


---

## Core Syntax Principle: DEFINE vs CREATE

### Named Objects Use DEFINE

For "true" named Snowflake objects (objects with identities that can be referenced by name), DCM uses the `DEFINE` keyword. The syntax is **identical** to the corresponding `CREATE` statement, with only the keyword changed:

```sql
-- Standard Snowflake DDL (imperative)
CREATE TABLE my_db.my_schema.my_table (
    id NUMBER,
    name VARCHAR
);

-- DCM Definition (declarative)
DEFINE TABLE my_db.my_schema.my_table (
    id NUMBER,
    name VARCHAR
);
```

This declarative approach means:

- Running the same definition multiple times is idempotent
- DCM determines whether to create, alter, or leave the object unchanged
- Object dependencies are resolved automatically

> **⚠️ CRITICAL CONSTRAINT**: A DCM project CANNOT define its parent database or schema. If your project identifier is `DATABASE.SCHEMA.PROJECT_NAME`, you cannot use `DEFINE DATABASE DATABASE` or `DEFINE SCHEMA DATABASE.SCHEMA` in your definitions. These parent containers must already exist before you create the DCM project. You can only define objects *inside* the project's schema (e.g., tables, views, roles within that schema).

### Imperative Syntax Remains for Non-Objects

Certain operations that don't create named objects retain their standard imperative syntax, even though they are still declarative:

- **GRANT statements** - Privileges and role assignments
- **ATTACH DATA METRIC FUNCTION** - Expectations/data quality bindings. **NOTE**: the syntax for data metric functions in DCM doesn't match the imperative syntax for attaching DMFs to tables/views.

```sql
ALTER TABLE MY_DB.RAW.INVENTORY
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.MIN
    ON (IN_STOCK)
    EXPECTATION MIN_10_ITEMS (value > 10);
```

```sql
ATTACH DATA METRIC FUNCTION MY_DB.RAW.INVENTORY_SPREAD
    TO TABLE MY_DB.RAW.INVENTORY
    ON (IN_STOCK)
    EXPECTATION EVEN_INVENTORY (value < 50);
```

---


---

## Jinja Templating

DCM definitions support Jinja2 templating, enabling dynamic generation of SQL based on variables, loops, conditionals, and macros. This allows for DRY (Don't Repeat Yourself) definitions and environment-specific configurations.

> **Note**: The examples below demonstrate Jinja patterns. Variable values come from the `templating` section in `manifest.yml` — resolved by merging `templating.defaults` with the active `templating.configurations` entry selected by the target's `templating_config`. See `reference/project_structure.md` for details.

### Variable Substitution

Use `{{ variable_name }}` for simple value substitution:

```sql
DEFINE DATABASE MY_PROJECT_{{env}}
    COMMENT = 'Environment: {{env}}';

DEFINE SCHEMA MY_PROJECT_{{env}}.RAW;

DEFINE WAREHOUSE MY_PROJECT_WH_{{env}}
WITH
    WAREHOUSE_SIZE = '{{wh_size}}'
    AUTO_SUSPEND = 300
;
```

### Loops

Use `{% for %}...{% endfor %}` to iterate over collections:

```sql
-- Grant role to multiple users
{% for user_name in users %}
    GRANT ROLE PROJECT_READ TO USER {{user_name}};
{% endfor %}

-- Create schemas for each team
{% for team in teams %}
    DEFINE SCHEMA MY_DB.{{ team | upper }};
{% endfor %}
```

### Conditionals

Use `{% if %}...{% endif %}` for conditional logic:

```sql
{% for team in teams %}
    DEFINE SCHEMA MY_DB.{{ team | upper }};

    {% if team == 'HR' %}
        DEFINE TABLE MY_DB.{{ team | upper }}.EMPLOYEES (
            NAME VARCHAR,
            ID INT
        )
        COMMENT = 'This table is only created for HR'
        ;
    {% endif %}
{% endfor %}
```

### Jinja Filters

Apply filters to transform values:

```sql
-- Convert to uppercase
DEFINE SCHEMA MY_DB.{{ team | upper }};

-- Common filters: upper, lower, title, trim, default
DEFINE ROLE {{ role_name | upper }}_ADMIN;
```

### Macros

> **⚠️ Inline Macro Scope**: Macros defined inline within a definition file are **only accessible within that same file**. They cannot be imported or referenced from other definition files. For macros that need to be shared across multiple files, place them in `sources/macros/` — macros in that directory are accessible from all definition files. See `reference/project_structure.md` for details on the macros directory.

Define reusable template blocks with `{% macro %}...{% endmacro %}`:

```sql
{% macro create_team_roles(team) %}

    DEFINE ROLE {{ team }}_OWNERSHIP;
    DEFINE ROLE {{ team }}_DEVELOPER;
    DEFINE ROLE {{ team }}_USAGE;

    GRANT USAGE ON DATABASE MY_DB TO ROLE {{ team }}_USAGE;
    GRANT USAGE ON SCHEMA MY_DB.{{ team | upper }} TO ROLE {{ team }}_USAGE;
    GRANT OWNERSHIP ON SCHEMA MY_DB.{{ team | upper }} TO ROLE {{ team }}_OWNERSHIP;

    GRANT CREATE DYNAMIC TABLE, CREATE TABLE, CREATE VIEW
        ON SCHEMA MY_DB.{{ team | upper }} TO ROLE {{ team }}_DEVELOPER;

    GRANT ROLE {{ team }}_USAGE TO ROLE {{ team }}_DEVELOPER;
    GRANT ROLE {{ team }}_DEVELOPER TO ROLE {{ team }}_OWNERSHIP;
    GRANT ROLE {{ team }}_OWNERSHIP TO ROLE {{ project_owner_role }};

{% endmacro %}


-- Invoke macro for each team
{% for team in teams %}

    DEFINE SCHEMA MY_DB.{{ team | upper }}
        COMMENT = 'Team schema';

    {{ create_team_roles(team) }}

{% endfor %}
```

### Jinja Dictionaries

DCM's Jinja templating engine supports dictionaries, enabling granular control over per-resource configuration without repetitive hard-coded scripts.

#### Defining Dictionaries in manifest.yml

Dictionaries are defined as list items with named properties in `templating.configurations`:

```yaml
templating:
  defaults:
    user: "GITHUB_ACTIONS_SERVICE_USER"
    wh_size: "X-SMALL"
  configurations:
    PROD:
      env_suffix: ""
      project_owner_role: "DCM_PROD_DEPLOYER"
      teams:
        - name: "Marketing"
          wh_size: "MEDIUM"
          data_retention_days: 14
          needs_sandbox_schema: true
        - name: "Finance"
          wh_size: "X-LARGE"
          data_retention_days: 90
          needs_sandbox_schema: false
        - name: "HR"
          data_retention_days: 30
          needs_sandbox_schema: false
```

#### Using Dictionaries in SQL Templates

Loop through dictionary items and access their properties:

```sql
{% for team in teams %}
{% set team_name = team.name | upper %}

DEFINE SCHEMA MY_DB{{env_suffix}}.{{team_name}}
    COMMENT = 'Team schema'
    DATA_RETENTION_TIME_IN_DAYS = {{ team.data_retention_days }};

DEFINE TABLE MY_DB{{env_suffix}}.{{team_name}}.PRODUCTS(
    ITEM_NAME VARCHAR,
    ITEM_ID VARCHAR
);

{% if team.needs_sandbox_schema | default(false) %}
DEFINE SCHEMA MY_DB{{env_suffix}}.{{team_name}}_SANDBOX
    COMMENT = 'Sandbox schema'
    DATA_RETENTION_TIME_IN_DAYS = 1;
{% endif %}

{% endfor %}
```

#### Dictionary Limitations

- Dictionaries can be defined in `manifest.yml` but **cannot be overridden at runtime** via `--variable`
- Individual scalar values within dictionaries cannot be selectively overridden

### Complete Jinja Example

```sql
-- Macro definition
{% macro create_team_roles(team) %}
    DEFINE ROLE {{team}}_ADMIN;
    DEFINE ROLE {{team}}_DEVELOPER;
    DEFINE ROLE {{team}}_USAGE;

    GRANT CREATE SCHEMA ON DATABASE {{team}}{{env_suffix}} TO ROLE {{team}}_DEVELOPER;
    GRANT USAGE ON DATABASE {{team}}{{env_suffix}} TO ROLE {{team}}_USAGE;

    GRANT ROLE {{team}}_USAGE TO ROLE {{team}}_DEVELOPER;
    GRANT ROLE {{team}}_DEVELOPER TO ROLE {{team}}_ADMIN;
    GRANT ROLE {{team}}_ADMIN TO ROLE {{project_owner_role}};

    {% for user_name in users %}
        GRANT ROLE {{team}}_USAGE TO USER {{user_name}};
    {% endfor %}
{% endmacro %}


-- Main definitions
{% for team in teams %}
    DEFINE WAREHOUSE {{team}}_WH{{env_suffix}}
        WITH WAREHOUSE_SIZE='{{wh_size}}';

    DEFINE DATABASE {{team}}{{env_suffix}};
    DEFINE SCHEMA {{team}}{{env_suffix}}.PROJECTS;

    {{ create_team_roles(team) }}

    {% if team == 'Finance' %}
        GRANT USAGE ON DATABASE INGEST TO ROLE {{team}}_DEVELOPER;
        GRANT USAGE ON SCHEMA INGEST.RAW TO ROLE {{team}}_DEVELOPER;
        GRANT SELECT ON ALL TABLES IN SCHEMA INGEST.RAW TO ROLE {{team}}_DEVELOPER;
    {% endif %}

{% endfor %}
```

---


---

## Tasks

DCM supports tasks for scheduled operations and ETL orchestration. During deployment, DCM automatically suspends and resumes tasks as needed—no manual intervention required.

### Task Definition Syntax

Tasks use the `DEFINE TASK` keyword and follow standard Snowflake task syntax:

```sql
DEFINE TASK database_name.schema_name.task_name
WAREHOUSE = 'warehouse_name'
SCHEDULE = 'schedule_expression'
AS
BEGIN
    -- Task SQL statements
END;
```

### Key Features

**Automatic Suspend/Resume During Deployment:**

When deploying changes to an existing task:

1. DCM automatically **suspends the root task** (and its entire task graph)
2. Applies all changes to the task definition
3. Automatically **resumes the root task** after deployment completes

This means you can run `snow dcm plan` and `snow dcm deploy` regardless of whether tasks are currently running or suspended.

### Task Properties

| Property | Description | Example |
|----------|-------------|---------|
| `WAREHOUSE` | Compute warehouse for task execution | `WAREHOUSE = 'MY_WH'` |
| `SCHEDULE` | When the task runs (cron expression or time interval) | `SCHEDULE = 'USING CRON 0 4 * * * UTC'` |
| `USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE` | For serverless tasks (alternative to WAREHOUSE) | `USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'` |
| `WHEN` | Optional condition to run task | `WHEN SYSTEM$STREAM_HAS_DATA('MY_STREAM')` |
| `AFTER` | Predecessor task(s) for task DAGs | `AFTER MY_DB.SCHEMA.PARENT_TASK` |
| `COMMENT` | Task description | `COMMENT = 'Daily order ingestion'` |

### Schedule Expressions

Tasks support both cron schedules and interval-based schedules:

**Cron Schedule:**
```sql
SCHEDULE = 'USING CRON 0 4 * * * UTC'  -- Daily at 4:00 AM UTC
SCHEDULE = 'USING CRON 0 */2 * * * America/New_York'  -- Every 2 hours ET
```

**Interval Schedule:**
```sql
SCHEDULE = '60 MINUTE'  -- Every 60 minutes
SCHEDULE = '5 MINUTE'   -- Every 5 minutes
```

### Task Examples

**Simple Scheduled Task:**

```sql
DEFINE TASK DCM_PROJECT_{{db}}.ANALYTICS.TSK_INGEST_DAILY_ORDERS
WAREHOUSE = 'DCM_PROJECT_WH_{{db}}'
SCHEDULE = 'USING CRON 0 4 * * * UTC'
AS
BEGIN
    INSERT INTO DCM_PROJECT_{{db}}.RAW.ORDERS
    SELECT * FROM EXTERNAL_SOURCE.ORDERS
    WHERE ORDER_DATE >= CURRENT_DATE - INTERVAL '1 DAY';
END;
```

**Serverless Task with Condition:**

```sql
DEFINE TASK MY_DB.ANALYTICS.TSK_PROCESS_STREAM
USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
SCHEDULE = '5 MINUTE'
WHEN SYSTEM$STREAM_HAS_DATA('MY_DB.RAW.ORDER_STREAM')
AS
BEGIN
    MERGE INTO MY_DB.ANALYTICS.ORDERS_SUMMARY target
    USING MY_DB.RAW.ORDER_STREAM source
    ON target.ORDER_ID = source.ORDER_ID
    WHEN MATCHED THEN UPDATE SET target.STATUS = source.STATUS
    WHEN NOT MATCHED THEN INSERT VALUES (source.ORDER_ID, source.STATUS);
END;
```

**Task DAG (Dependent Tasks):**

```sql
-- Root task
DEFINE TASK MY_DB.ETL.TSK_ROOT
WAREHOUSE = 'ETL_WH'
SCHEDULE = 'USING CRON 0 2 * * * UTC'
AS
BEGIN
    CALL MY_DB.ETL.INIT_DAILY_LOAD();
END;

-- Child task 1
DEFINE TASK MY_DB.ETL.TSK_STAGE_ORDERS
WAREHOUSE = 'ETL_WH'
AFTER MY_DB.ETL.TSK_ROOT
AS
BEGIN
    INSERT INTO MY_DB.STAGING.ORDERS
    SELECT * FROM MY_DB.RAW.ORDERS WHERE LOADED = FALSE;
END;

-- Child task 2
DEFINE TASK MY_DB.ETL.TSK_STAGE_CUSTOMERS
WAREHOUSE = 'ETL_WH'
AFTER MY_DB.ETL.TSK_ROOT
AS
BEGIN
    INSERT INTO MY_DB.STAGING.CUSTOMERS
    SELECT * FROM MY_DB.RAW.CUSTOMERS WHERE LOADED = FALSE;
END;

-- Final task (depends on both child tasks)
DEFINE TASK MY_DB.ETL.TSK_AGGREGATE
WAREHOUSE = 'ETL_WH'
AFTER MY_DB.ETL.TSK_STAGE_ORDERS, MY_DB.ETL.TSK_STAGE_CUSTOMERS
AS
BEGIN
    INSERT INTO MY_DB.ANALYTICS.DAILY_SUMMARY
    SELECT /* aggregation logic */;
END;
```

### Task Body Syntax

The task body (after `AS`) can be:

1. **Single SQL statement:**
   ```sql
   AS
   INSERT INTO target_table SELECT * FROM source_table;
   ```

2. **BEGIN...END block with multiple statements:**
   ```sql
   AS
   BEGIN
       DELETE FROM staging_table WHERE processed = TRUE;
       INSERT INTO target_table SELECT * FROM staging_table;
       UPDATE staging_table SET processed = TRUE;
   END;
   ```

3. **Stored procedure call:**
   ```sql
   AS
   CALL my_procedure();
   ```

### Deployment Behavior

**When you modify a task definition and run `snow dcm deploy`:**

- If the task is currently **suspended**: DCM applies changes immediately
- If the task is currently **active/running**: 
  1. DCM suspends the root task automatically
  2. Applies all definition changes
  3. Resumes the root task automatically

**This applies to task graphs:**
- Suspending the root task suspends the entire DAG
- Resuming the root task resumes the entire DAG

**No manual intervention required** - you can safely run plan and deploy operations on active task graphs.

### Best Practices for Tasks in DCM

1. **Use fully qualified names** for all task definitions
2. **Define task DAGs in dependency order** (root task first, then children)
3. **Use `WHEN` conditions** to prevent unnecessary task executions
4. **Consider serverless tasks** (`USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE`) for variable workloads
5. **Add comments** to document task purposes and dependencies
6. **Test task logic** independently before deploying as scheduled tasks

### Limitations

Tasks in DCM follow standard Snowflake task limitations:

- Maximum task DAG depth: 1000 tasks
- Maximum predecessors per task: 100 tasks
- Tasks must have appropriate privileges to access referenced objects

---


---

## Stages

DCM supports internal stages for file storage. External stages (S3, Azure, GCS) are not supported.

### Stage Definition Syntax

```sql
DEFINE STAGE database_name.schema_name.stage_name
    [DIRECTORY = (ENABLE = TRUE)]
    [FILE_FORMAT = (TYPE = 'CSV' ...)]
    [ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')]
    [COMMENT = 'description'];
```

### ✅ Supported Changes vs ⚠️ Immutable Attributes

| Property | Modifiable | Notes |
|----------|------------|-------|
| Directory table | ✅ Supported | Enable/disable file metadata tracking |
| Comment | ✅ Supported | Update description |
| Encryption type | ⚠️ **Immutable** | Cannot change after creation—must recreate stage |

### Examples

```sql
-- Basic stage
DEFINE STAGE FINANCE_DB.RAW.TASTY_BYTES_ORDERS
    COMMENT = 'Internal stage for uploading files';

-- With directory table and file format
DEFINE STAGE MY_DB.RAW.CSV_STAGE
    DIRECTORY = (ENABLE = TRUE)
    FILE_FORMAT = (TYPE = 'CSV' FIELD_DELIMITER = '|' SKIP_HEADER = 1)
    COMMENT = 'Stage with directory tracking';

-- With encryption
DEFINE STAGE MY_DB.SECURE.ENCRYPTED_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT = 'Stage with Snowflake-managed encryption';
```

### Key Properties

| Property | Description |
|----------|-------------|
| `DIRECTORY` | Enable directory table for file metadata queries |
| `FILE_FORMAT` | Default file format (TYPE, FIELD_DELIMITER, etc.) |
| `ENCRYPTION` | Encryption type—**immutable after creation** |
| `COPY_OPTIONS` | Default COPY INTO behavior (ON_ERROR, etc.) |
| `COMMENT` | Stage description |

> **Note:** After defining a stage, use standard Snowflake commands for file operations: `PUT`, `LIST`, `COPY INTO`, etc.

---


---

## SQL Functions

DCM supports user-defined functions (UDFs) for reusable SQL logic.

### Function Definition Syntax

```sql
DEFINE FUNCTION database_name.schema_name.function_name(param_name data_type, ...)
RETURNS return_type
[COMMENT = 'description']
AS
$$
    function_body
$$;
```

### ⚠️ Current Limitation: Dependency Ordering

**DCM does not yet automatically sort SQL functions based on dependencies.** If a view or other object references a function, DCM may attempt to create the view before the function, causing deployment to fail.

**Workaround:**
1. Deploy functions first in a separate deployment
2. Then deploy objects that reference those functions

**Example of the problem:**
```sql
-- If this view is processed before the function below, deployment fails
DEFINE VIEW MY_DB.ANALYTICS.PROFIT_SUMMARY AS
SELECT CALCULATE_PROFIT_MARGIN(REVENUE, COST) FROM ...;

-- Function needs to exist first
DEFINE FUNCTION MY_DB.ANALYTICS.CALCULATE_PROFIT_MARGIN(...) ...
```

### Examples

```sql
-- Simple scalar function
DEFINE FUNCTION DCM_PROJECT_{{env_suffix}}.ANALYTICS.CALCULATE_PROFIT_MARGIN(REVENUE NUMBER, COST NUMBER)
RETURNS NUMBER(10,2)
AS
$$
    CASE 
        WHEN REVENUE = 0 THEN 0
        ELSE ROUND(((REVENUE - COST) / REVENUE) * 100, 2)
    END
$$;

-- Function with comment
DEFINE FUNCTION MY_DB.UTILS.CLEAN_PHONE_NUMBER(PHONE_NUMBER VARCHAR)
RETURNS VARCHAR
COMMENT = 'Removes non-numeric characters from phone numbers'
AS
$$
    REGEXP_REPLACE(PHONE_NUMBER, '[^0-9]', '')
$$;

-- Function with multiple parameters
DEFINE FUNCTION MY_DB.ANALYTICS.CALCULATE_DISCOUNT(PRICE NUMBER, DISCOUNT_PCT NUMBER, MAX_DISCOUNT NUMBER)
RETURNS NUMBER(10,2)
AS
$$
    LEAST(PRICE * (DISCOUNT_PCT / 100), MAX_DISCOUNT)
$$;
```

### Key Properties

| Property | Description |
|----------|-------------|
| Parameters | `(param_name data_type, ...)` - Input parameters with types |
| `RETURNS` | Return data type |
| `COMMENT` | Function description |
| Function body | SQL expression between `$$` delimiters |

> **Note:** For table functions (UDTFs) and more complex function types, consult Snowflake's CREATE FUNCTION documentation—DCM syntax mirrors it exactly.

---


---

## Grants (Imperative Syntax)

> **💡 IMPORTANT:** For role and grant best practices, recommended patterns, warehouse constraint workarounds, and troubleshooting, **load the dcm-roles-and-grants skill** before designing roles/grants for a DCM project.

Grant statements use standard Snowflake syntax without modification. They are **not** declarative and use imperative keywords.

### Account Roles vs Database Roles

DCM supports both account roles and database roles. Choose appropriately:

| Role Type | Syntax | Scope | Best For |
|-----------|--------|-------|----------|
| Account Role | `DEFINE ROLE role_name` | Account-wide | Warehouse access, cross-database access |
| Database Role | `DEFINE DATABASE ROLE db.role_name` | Single database | Database-scoped access (preferred for most cases) |

### ⚠️ Critical Constraint: Database Roles and Warehouses

**Database roles CANNOT be granted warehouse privileges.** Warehouses are account-level objects, while database roles are scoped to a specific database. This is a Snowflake architectural constraint.

**Solution Pattern:**
```sql
-- Create account role for warehouse access
DEFINE ROLE PROJECT_WAREHOUSE_USER
COMMENT = 'Warehouse access for project users';

-- Grant warehouse to account role (NOT database role)
GRANT USAGE ON WAREHOUSE project_wh TO ROLE PROJECT_WAREHOUSE_USER;

-- Users get warehouse access via this account role
-- Database roles handle data access separately
```

### Grant Syntax Examples

```sql
-- Grant privileges on objects
GRANT USAGE ON DATABASE database_name TO ROLE role_name;
GRANT USAGE ON SCHEMA database_name.schema_name TO ROLE role_name;
GRANT SELECT ON ALL TABLES IN DATABASE database_name TO ROLE role_name;
GRANT SELECT ON ALL DYNAMIC TABLES IN DATABASE database_name TO ROLE role_name;
GRANT SELECT ON ALL VIEWS IN DATABASE database_name TO ROLE role_name;

-- Grant warehouse usage (ONLY to account roles, NOT database roles)
GRANT USAGE ON WAREHOUSE warehouse_name TO ROLE role_name;

-- Grant role to user
GRANT ROLE role_name TO USER user_name;

-- Grant role hierarchy
GRANT ROLE child_role TO ROLE parent_role;
GRANT DATABASE ROLE db.child_role TO DATABASE ROLE db.parent_role;

-- Schema privileges
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA database_name.schema_name TO ROLE role_name;
GRANT CREATE DYNAMIC TABLE ON SCHEMA database_name.schema_name TO ROLE role_name;
```

### What DCM Does NOT Support for Grants

Some grant patterns are not supported in DCM and must be applied manually after deployment:

| Grant Pattern | DCM Support | Workaround |
|--------------|-------------|------------|
| `GRANT ... ON ACCOUNT` | ❌ Not supported | Apply manually post-deployment |
| `GRANT IMPORTED PRIVILEGES` | ❌ Not supported | Apply manually post-deployment |
| `GRANT ALL ON ALL SCHEMAS IN DATABASE` | ❌ Not supported | Grant to each schema explicitly |
| `GRANT ... ON FUTURE FUNCTIONS/PROCEDURES` | ⚠️ Limited | Use explicit grants when objects created |
| Warehouse grants to database roles | ❌ Not allowed | Use account role for warehouse access |

**⚠️ Action Required:** If your project has unsupported grants, document them in a `post_deployment_grants.sql` file for manual application after DCM deployment.

> **Tip:** For role and grant best practices in DCM, see the **dcm-roles-and-grants** skill which provides recommended patterns and troubleshooting guidance.

---


---

## Data Quality: Expectations and Data Metric Functions

DCM supports Snowflake's Data Metric Functions (DMFs) for data quality monitoring. This involves two distinct syntaxes:

### Custom Data Metric Functions (DEFINE)

Custom DMFs are true named objects and use the `DEFINE` keyword:

```sql
DEFINE DATA METRIC FUNCTION database.schema.function_name(
    TABLE_NAME TABLE(
        COLUMN_VALUE data_type
    )
)
RETURNS return_type
AS
$$
    SELECT expression
    FROM TABLE_NAME
    WHERE conditions
$$
;
```

**Example - Custom spread calculation:**

```sql
DEFINE DATA METRIC FUNCTION MY_DB.RAW.INVENTORY_SPREAD(
    TABLE_NAME TABLE(COLUMN_VALUE NUMBER)
)
RETURNS NUMBER
AS
$$
    SELECT
        MAX(COLUMN_VALUE) - MIN(COLUMN_VALUE)
    FROM
        TABLE_NAME
    WHERE
        COLUMN_VALUE IS NOT NULL
$$
;
```

The table parameter signature `TABLE_NAME TABLE(COLUMN_VALUE data_type)` defines:

- `TABLE_NAME` - A reference to the table being evaluated
- `COLUMN_VALUE` - The column(s) being measured, with their data types

For more details on custom DMF syntax, consult Snowflake's documentation on [Custom DMFs](https://docs.snowflake.com/en/user-guide/data-quality-custom-dmfs).

### Attaching DMFs with Expectations (Imperative)

Attaching DMFs to tables/views uses the `ATTACH DATA METRIC FUNCTION` statement (imperative, not `DEFINE`):

```sql
ATTACH DATA METRIC FUNCTION dmf_reference
    TO object_type fully_qualified_object_name
    ON (column_name)
    [EXPECTATION expectation_name (condition)];
```

**Components:**

- `dmf_reference` - Either a system DMF (`SNOWFLAKE.CORE.*`) or custom DMF
- `object_type` - `TABLE`, `DYNAMIC TABLE`, or `VIEW`
- `ON (column_name)` - The column(s) to evaluate
- `EXPECTATION` - Named condition that defines pass/fail criteria

### System DMFs

Snowflake provides built-in system DMFs in `SNOWFLAKE.CORE`:

| Category       | DMF                         | Description                               |
| -------------- | --------------------------- | ----------------------------------------- |
| **Accuracy**   | `BLANK_COUNT`               | Count of blank values in a column         |
|                | `BLANK_PERCENT`             | Percentage of blank values                |
|                | `NULL_COUNT`                | Count of NULL values                      |
|                | `NULL_PERCENT`              | Percentage of NULL values                 |
| **Freshness**  | `FRESHNESS`                 | Data freshness based on timestamp column  |
|                | `DATA_METRIC_SCHEDULE_TIME` | For custom freshness metrics              |
| **Statistics** | `AVG`                       | Average value of a column                 |
|                | `MAX`                       | Maximum value                             |
|                | `MIN`                       | Minimum value                             |
|                | `STDDEV`                    | Standard deviation                        |
| **Uniqueness** | `ACCEPTED_VALUES`           | Whether values match a Boolean expression |
|                | `DUPLICATE_COUNT`           | Number of duplicate values                |
|                | `UNIQUE_COUNT`              | Number of unique non-NULL values          |
| **Volume**     | `ROW_COUNT`                 | Total rows in table/view                  |

For the complete reference, see [System DMFs](https://docs.snowflake.com/en/user-guide/data-quality-system-dmfs).

### Attaching System DMFs

```sql
-- Attach MIN check to table column
ATTACH DATA METRIC FUNCTION SNOWFLAKE.CORE.MIN
    TO TABLE MY_DB.RAW.INVENTORY
    ON (IN_STOCK)
    EXPECTATION MIN_10_ITEMS (value > 10);

-- Attach NULL_COUNT to dynamic table
ATTACH DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT
    TO DYNAMIC TABLE MY_DB.ANALYTICS.ENRICHED_ORDERS
    ON (CUSTOMER_CITY)
    EXPECTATION NO_MISSING_CITIES (value = 0);

-- Attach to view
ATTACH DATA METRIC FUNCTION SNOWFLAKE.CORE.MIN
    TO VIEW MY_DB.SERVE.V_DAILY_SALES
    ON (DAILY_ORDERS)
    EXPECTATION ORDERS_POSITIVE (value >= 0);
```

### Attaching Custom DMFs

```sql
ATTACH DATA METRIC FUNCTION MY_DB.RAW.INVENTORY_SPREAD
    TO TABLE MY_DB.RAW.INVENTORY
    ON (IN_STOCK)
    EXPECTATION EVEN_INVENTORY (value < 50);
```

### Data Metric Schedule

Objects that have DMFs attached must specify when metrics are computed using `DATA_METRIC_SCHEDULE`:

```sql
-- Trigger on data changes
DEFINE TABLE MY_DB.RAW.INVENTORY (...)
DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES'
;

-- Cron schedule
DEFINE VIEW MY_DB.SERVE.V_DASHBOARD (...)
DATA_METRIC_SCHEDULE = 'USING CRON 0 8 * * * UTC'
AS ...
;
```

**Schedule Options:**

- `'TRIGGER_ON_CHANGES'` - Evaluate when data changes
- `'USING CRON <expr>'` - Cron-based schedule (e.g., `'USING CRON 0 8 * * * UTC'`)

### Complete Data Quality Example

```sql
-- 1. Define the table with metric schedule
DEFINE TABLE MY_DB.RAW.FINANCIAL_DATA (
    TRANSACTION_ID NUMBER,
    AMOUNT NUMBER(15,2),
    STATUS VARCHAR,
    PROCESSED_AT TIMESTAMP_NTZ
)
CHANGE_TRACKING = TRUE
DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES'
;

-- 2. Define a custom DMF
DEFINE DATA METRIC FUNCTION MY_DB.RAW.AMOUNT_SPREAD(
    TABLE_NAME TABLE(COLUMN_VALUE NUMBER)
)
RETURNS NUMBER
AS
$$
    SELECT MAX(COLUMN_VALUE) - MIN(COLUMN_VALUE)
    FROM TABLE_NAME
    WHERE COLUMN_VALUE IS NOT NULL
$$
;

-- 3. Attach system DMFs with expectations
ATTACH DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT
    TO TABLE MY_DB.RAW.FINANCIAL_DATA
    ON (AMOUNT)
    EXPECTATION NO_NULL_AMOUNTS (value = 0);

ATTACH DATA METRIC FUNCTION SNOWFLAKE.CORE.MIN
    TO TABLE MY_DB.RAW.FINANCIAL_DATA
    ON (AMOUNT)
    EXPECTATION AMOUNTS_POSITIVE (value >= 0);

-- 4. Attach custom DMF with expectation
ATTACH DATA METRIC FUNCTION MY_DB.RAW.AMOUNT_SPREAD
    TO TABLE MY_DB.RAW.FINANCIAL_DATA
    ON (AMOUNT)
    EXPECTATION REASONABLE_SPREAD (value < 1000000);
```

For comprehensive information on data quality monitoring, see the [Introduction to DMFs](https://docs.snowflake.com/en/user-guide/data-quality-intro).

---


---

## DATA_METRIC_SCHEDULE: Triggering Expectation Evaluations

> **⚠️ DCM-SPECIFIC SYNTAX**: The `DATA_METRIC_SCHEDULE` property as shown here is **not documented in Snowflake's standard documentation**. This is a DCM-specific declarative syntax for setting the schedule on object definitions. In standard Snowflake, schedules are set via `ALTER TABLE ... SET DATA_METRIC_SCHEDULE`. In DCM, you declare the schedule directly on the object definition.

### Why DATA_METRIC_SCHEDULE Matters

The `DATA_METRIC_SCHEDULE` property is **essential** for data quality monitoring in DCM. It controls **when** attached Data Metric Functions (DMFs) and their expectations are evaluated. Without this property set on an object, **no expectations will be evaluated**, even if DMFs are attached.

**Key Points:**

1. **Required for expectations to run** - Attaching a DMF to an object is not enough; the object must have a `DATA_METRIC_SCHEDULE` to trigger evaluation
2. **Set on the object, not the DMF** - The schedule is a property of the table/view/dynamic table, not the individual DMF attachment
3. **All DMFs share the schedule** - When the schedule triggers, ALL DMFs attached to that object are evaluated together
4. **Affects billing** - DMF evaluations consume serverless compute credits; schedule appropriately

### Schedule Options

| Schedule Type          | Syntax                           | Use Case                                                                                                |
| ---------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------- |
| **Trigger on changes** | `'TRIGGER_ON_CHANGES'`           | Evaluate whenever data in the object changes. Best for operational tables with streaming/CDC ingestion. |
| **Cron schedule**      | `'USING CRON <expr> <timezone>'` | Evaluate on a fixed schedule. Best for reporting views or batch-loaded tables.                          |
| **Interval**           | `'<N> MINUTE'` or `'<N> HOUR'`   | Evaluate at regular intervals. Alternative to cron for simple recurring checks.                         |

### Cron Expression Format

```
'USING CRON <minute> <hour> <day-of-month> <month> <day-of-week> <timezone>'
```

**Common Examples:**

| Expression                                 | Description                      |
| ------------------------------------------ | -------------------------------- |
| `'USING CRON 0 8 * * * UTC'`               | Daily at 8:00 AM UTC             |
| `'USING CRON 0 */4 * * * UTC'`             | Every 4 hours                    |
| `'USING CRON 0 0 * * 1 UTC'`               | Weekly on Monday at midnight UTC |
| `'USING CRON 30 6 1 * * America/New_York'` | Monthly on the 1st at 6:30 AM ET |

### Object-Specific Syntax

#### Tables

For tables, `DATA_METRIC_SCHEDULE` is set as a table property. Typically combined with `CHANGE_TRACKING = TRUE` for change-based evaluation:

```sql
DEFINE TABLE database_name.schema_name.table_name (
    column_definitions...
)
CHANGE_TRACKING = TRUE
DATA_METRIC_SCHEDULE = 'schedule_expression'
;
```

**Example - Trigger on changes (recommended for CDC/streaming):**

```sql
DEFINE TABLE MY_DB.RAW.INVENTORY (
    ITEM_ID NUMBER,
    REGION_ID NUMBER,
    IN_STOCK NUMBER,
    COUNTED_ON DATE
)
CHANGE_TRACKING = TRUE
DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES'
;
```

**Example - Cron schedule (for batch-loaded tables):**

```sql
DEFINE TABLE MY_DB.RAW.DAILY_IMPORT (
    RECORD_ID NUMBER,
    IMPORT_DATE DATE,
    VALUE NUMBER
)
DATA_METRIC_SCHEDULE = 'USING CRON 0 6 * * * UTC'
;
```

#### Views

Views support `DATA_METRIC_SCHEDULE` for evaluating expectations on derived data. Since views don't have change tracking, cron schedules are typical:

```sql
DEFINE VIEW database_name.schema_name.view_name
DATA_METRIC_SCHEDULE = 'schedule_expression'
AS
SELECT ...
;
```

**Example:**

```sql
DEFINE VIEW MY_DB.SERVE.V_DAILY_SALES
DATA_METRIC_SCHEDULE = 'USING CRON 0 8 * * * UTC'
AS
SELECT
    DATE_TRUNC('DAY', ORDER_TS) AS SALE_DATE,
    COUNT(DISTINCT ORDER_ID) AS DAILY_ORDERS,
    SUM(LINE_ITEM_REVENUE) AS DAILY_REVENUE
FROM
    MY_DB.ANALYTICS.ORDER_DETAILS
GROUP BY SALE_DATE
;
```

#### Dynamic Tables

Dynamic tables can use either `TRIGGER_ON_CHANGES` (evaluates after refresh) or cron schedules:

```sql
DEFINE DYNAMIC TABLE database_name.schema_name.dt_name
WAREHOUSE = warehouse_name
TARGET_LAG = 'lag_specification'
[INITIALIZE = 'ON_SCHEDULE' | 'ON_CREATE']
DATA_METRIC_SCHEDULE = 'schedule_expression'
AS
SELECT ...
;
```

**Example - Trigger after refresh:**

```sql
DEFINE DYNAMIC TABLE MY_DB.ANALYTICS.ENRICHED_ORDERS
WAREHOUSE = MY_WH
TARGET_LAG = 'DOWNSTREAM'
INITIALIZE = 'ON_SCHEDULE'
DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES'
AS
SELECT
    o.ORDER_ID,
    o.ORDER_TS,
    c.CUSTOMER_NAME
FROM MY_DB.RAW.ORDERS o
JOIN MY_DB.RAW.CUSTOMERS c ON o.CUSTOMER_ID = c.ID
;
```

### Relationship Between Schedule and Expectations

The workflow for data quality in DCM:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. DEFINE object with DATA_METRIC_SCHEDULE                              │
│    (Sets WHEN expectations are evaluated)                               │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 2. ATTACH DATA METRIC FUNCTION with EXPECTATION                         │
│    (Defines WHAT is measured and pass/fail criteria)                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 3. Schedule triggers → DMFs evaluate → Results recorded                 │
│    (Results available in Snowflake's DMF event table)                   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Best Practices for Scheduling

| Scenario                             | Recommended Schedule       | Rationale                                          |
| ------------------------------------ | -------------------------- | -------------------------------------------------- |
| Streaming/CDC tables                 | `'TRIGGER_ON_CHANGES'`     | Evaluate as data arrives for real-time quality     |
| Batch ETL tables                     | Cron after ETL window      | Avoid evaluating during load; check after complete |
| Reporting views                      | Cron before business hours | Ensure quality before users access dashboards      |
| Dynamic tables with `DOWNSTREAM` lag | `'TRIGGER_ON_CHANGES'`     | Evaluate after each refresh                        |
| Dynamic tables with time-based lag   | Cron aligned with refresh  | Coordinate evaluation with refresh cycle           |

### Common Mistakes to Avoid

1. **Forgetting the schedule** - Attaching DMFs without setting `DATA_METRIC_SCHEDULE` means expectations never run
2. **Over-scheduling** - Running `TRIGGER_ON_CHANGES` on high-frequency tables can be costly
3. **Misaligned schedules** - Setting a cron schedule that runs before data is loaded


---

## DDL Hooks

DDL Hooks provide an **interim solution** for object types not yet supported by `DEFINE` statements. They allow raw DDL execution at specific points in the deployment lifecycle.

### Hook Syntax

```sql
ATTACH PRE_HOOK
AS [
    CREATE IF NOT EXISTS object_type qualified_name ...;
    CREATE OR REPLACE object_type qualified_name ...;
];

-- Regular DEFINE statements here

ATTACH POST_HOOK
AS [
    CREATE IF NOT EXISTS object_type qualified_name ...;
    CREATE OR REPLACE object_type qualified_name ...;
];
```

### Capabilities & Constraints

| Feature | Behavior |
|---------|----------|
| **Hooks per project** | 1 pre-hook + 1 post-hook maximum |
| **Statements per hook** | Multiple DDL statements allowed |
| **Execution order** | Statements run in definition order |
| **Allowed commands** | `CREATE IF NOT EXISTS` (recommended) or `CREATE OR REPLACE` only |
| **Jinja templating** | ✅ Supported—use same variables as DEFINE statements |
| **Plannable dependencies** | ✅ DCM understands hook objects for dependency resolution |

### ⚠️ Current Limitations

- **Not visible in PLAN/DEPLOY output** (coming soon)
- **Not stored in deployment history** (coming soon)
- **Error messages lack line numbers** and may show incomplete stack traces
- **Removing DDL from hook does NOT drop the object**—manual cleanup required
- **Only DDL statements**—no `ALTER`, `SET`, `COPY INTO`, etc.

### Supported Object Types

Use DDL Hooks for these object types until native `DEFINE` support is added:

| Category | Objects |
|----------|---------|
| **Data** | Stream, External Stage (with URL), File Format |
| **Monitoring** | Alert |
| **Analytics** | Semantic View |
| **Sharing** | Share |
| **Security** | Network Policy, Network Rule |
| **Integrations** | API Integration, Notification Integration, External Access Integration, Catalog Integration, Security Integration |

> **⚠️ Important**: **Internal stages** (without URL parameter) are fully supported via `DEFINE STAGE` and should NOT be placed in POST_HOOK. Only **external stages** (S3, Azure, GCS with URL parameter) require POST_HOOK.

### Examples

```sql
-- Pre-hook: Create integrations before DCM definitions
ATTACH PRE_HOOK
AS [
    CREATE API INTEGRATION IF NOT EXISTS GITHUB_API_{{env_suffix}}
        API_PROVIDER = git_https_api
        API_ALLOWED_PREFIXES = ('https://github.com')
        ALLOWED_AUTHENTICATION_SECRETS = all
        ENABLED = true;

    CREATE NOTIFICATION INTEGRATION IF NOT EXISTS EMAIL_NOTIFICATIONS_{{env_suffix}}
        TYPE = EMAIL
        ENABLED = true
        ALLOWED_RECIPIENTS = ('admin@example.com');

    CREATE SHARE IF NOT EXISTS DEMO_SHARE_{{env_suffix}}
        COMMENT = 'Share created in pre-hook for DCM grants';
];

-- Regular DCM definitions reference pre-hook objects
DEFINE SCHEMA MY_PROJECT_{{env_suffix}}.RAW;

-- Post-hook: Create objects dependent on DCM definitions
ATTACH POST_HOOK
AS [
    CREATE STREAM IF NOT EXISTS MY_PROJECT_{{env_suffix}}.RAW.ORDER_STREAM
        ON TABLE MY_PROJECT_{{env_suffix}}.RAW.ORDERS
        APPEND_ONLY = true;

    CREATE ALERT IF NOT EXISTS MY_PROJECT_{{env_suffix}}.ANALYTICS.LOW_INVENTORY_ALERT
        WAREHOUSE = 'MY_WH'
        SCHEDULE = 'USING CRON 0 9 * * * UTC'
        IF (EXISTS (
            SELECT 1 FROM MY_PROJECT_{{env_suffix}}.RAW.INVENTORY
            WHERE IN_STOCK < 10
        ))
        THEN CALL SYSTEM$SEND_EMAIL(
            'email_notifications_{{env_suffix}}',
            'admin@example.com',
            'Low Inventory Alert',
            'Items below threshold detected'
        );

    CREATE OR REPLACE FILE FORMAT MY_PROJECT_{{env_suffix}}.RAW.CSV_FORMAT
        TYPE = CSV
        FIELD_DELIMITER = '|'
        SKIP_HEADER = 1
        COMPRESSION = gzip;
];
```

### When to Use DDL Hooks vs DEFINE

| Use DEFINE when... | Use DDL Hooks when... |
|-------------------|----------------------|
| Object type is supported (Table, View, Internal Stage, etc.) | Object type not yet in DCM (Stream, Alert, External Stage, etc.) |
| You need full lifecycle management | Temporary until native support added |
| You want automatic object drops on removal | One-time creation is sufficient |

**Stage-Specific Guidance:**
- Internal stages (no URL) → Use `DEFINE STAGE`
- External stages (S3/Azure/GCS with URL) → Use `ATTACH POST_HOOK`

> **Recommendation:** Prefer `CREATE IF NOT EXISTS` in hooks—it's idempotent and won't fail on re-deployment. Use `CREATE OR REPLACE` only when object definitions change frequently.

---


---

## Object Properties Reference

### Common Properties

These properties can be used across multiple object types:

| Property               | Applies To                    | Description                     |
| ---------------------- | ----------------------------- | ------------------------------- |
| `COMMENT`              | Most objects                  | Descriptive text for the object |
| `CHANGE_TRACKING`      | Tables, Dynamic Tables        | Enable change tracking for CDC  |
| `DATA_METRIC_SCHEDULE` | Tables, Views, Dynamic Tables | Schedule for DMF evaluation     |

### Dynamic Table Properties

| Property               | Values                            | Description                  |
| ---------------------- | --------------------------------- | ---------------------------- |
| `WAREHOUSE`            | Warehouse name                    | Compute resource for refresh |
| `TARGET_LAG`           | `'DOWNSTREAM'` or time expression | Refresh frequency            |
| `INITIALIZE`           | `'ON_SCHEDULE'`, `'ON_CREATE'`    | When to first populate       |
| `DATA_METRIC_SCHEDULE` | Schedule expression               | DMF evaluation timing        |

### Warehouse Properties

| Property         | Values                                  | Description              |
| ---------------- | --------------------------------------- | ------------------------ |
| `WAREHOUSE_SIZE` | `'XSMALL'`, `'SMALL'`, `'MEDIUM'`, etc. | Compute size             |
| `AUTO_SUSPEND`   | Seconds                                 | Idle time before suspend |
| `AUTO_RESUME`    | `TRUE`/`FALSE`                          | Auto-resume on query     |

> **Tip**: For complete property options, consult Snowflake's DDL documentation for the corresponding `CREATE` statement.

---


---

## Syntax Summary

| Object Type          | Keyword                       | Notes                                                    |
| -------------------- | ----------------------------- | -------------------------------------------------------- |
| Database             | `DEFINE DATABASE`             |                                                          |
| Schema               | `DEFINE SCHEMA`               |                                                          |
| Table                | `DEFINE TABLE`                | Supports `CHANGE_TRACKING`, `DATA_METRIC_SCHEDULE`       |
| View                 | `DEFINE VIEW`                 | Supports `DATA_METRIC_SCHEDULE`, but only cron schedules |
| Dynamic Table        | `DEFINE DYNAMIC TABLE`        | Requires `WAREHOUSE`, `TARGET_LAG`                       |
| Warehouse            | `DEFINE WAREHOUSE`            | Uses `WITH` clause for properties                        |
| Role                 | `DEFINE ROLE`                 | Account-level roles                                      |
| Database Role        | `DEFINE DATABASE ROLE`        | Database-scoped roles                                    |
| Stage                | `DEFINE STAGE`                | Internal stages only; encryption type is immutable       |
| SQL Function         | `DEFINE FUNCTION`             | No automatic dependency sorting—deploy before dependents |
| Task                 | `DEFINE TASK`                 | Auto-suspend/resume during deployment                    |
| Data Metric Function | `DEFINE DATA METRIC FUNCTION` | Custom DMFs                                              |
| DDL Hooks            | `ATTACH PRE_HOOK / POST_HOOK` | Raw DDL for unsupported object types; 1 pre + 1 post max |
| Grants               | `GRANT ... TO ...`            | Imperative (no DEFINE)                                   |
| Expectations         | `ATTACH DATA METRIC FUNCTION` | Imperative (no DEFINE)                                   |

---


---

## Best Practices

1. **Use fully qualified names** - MUST ALWAYS specify fully qualified names for objects in the form of `database.schema.object`.

2. **Set appropriate `DATA_METRIC_SCHEDULE`** based on data freshness requirements:

   - `TRIGGER_ON_CHANGES` for operational tables with frequent updates
   - Cron schedules for reporting views queried at specific times

3. **Reference Snowflake documentation** for detailed syntax of complex object types—DCM mirrors `CREATE` syntax exactly

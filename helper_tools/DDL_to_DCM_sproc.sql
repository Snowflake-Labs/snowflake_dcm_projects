CREATE OR REPLACE PROCEDURE DCM_DEMO.PROJECTS.GENERATE_DEFINITIONS(
    db_name STRING,
    schema_allow_list ARRAY,
    output_path STRING
)
RETURNS TABLE (
    STATUS STRING,
    FILE_NAME STRING,
    TARGET_PATH STRING
)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
import re
import io

def main(session, db_name, schema_allow_list, output_path):
    # 1. Normalize Inputs
    allowed_schemas = None
    if schema_allow_list is not None:
        allowed_schemas = set([s.upper() for s in schema_allow_list])

    stage_root = output_path.rstrip('/')

    # 2. Build Inventory (Scan ALL schemas)
    session.sql(f"USE DATABASE {db_name}").collect()
    objects_df = session.sql(f"SHOW OBJECTS IN DATABASE {db_name}").collect()

    object_map = []
    for row in objects_df:
        s_name = row['schema_name'].upper()
        if s_name != 'INFORMATION_SCHEMA':
            fqn = f"{db_name}.{s_name}.{row['name']}"
            object_map.append({
                "name": row['name'],
                "fqn": fqn,
                "schema": s_name,
                "kind": row['kind']
            })

    # Sort by length (descending)
    object_map.sort(key=lambda x: len(x["name"]), reverse=True)

    generated_files = []

    # 3. Generate DDL and Stream to Stage
    for obj in object_map:
        short_name = obj['name']
        schema = obj['schema']
        fqn = obj['fqn']

        # Filtering
        if allowed_schemas is not None and (schema not in allowed_schemas):
            continue

        ddl_text = ""

        try:
            res = session.sql(f"SELECT GET_DDL('TABLE', '{fqn}', TRUE) as DDL").collect()
            ddl_text = res[0]['DDL']
        except Exception:
            try:
                res = session.sql(f"SELECT GET_DDL('VIEW', '{fqn}', TRUE) as DDL").collect()
                ddl_text = res[0]['DDL']
            except Exception as e:
                generated_files.append(("ERROR", short_name, str(e)))
                continue

        # === REPLACE CREATE WITH DEFINE ===
        # Pattern 1: Handle "CREATE OR REPLACE <TYPE>"
        ddl_text = re.sub(r'^\s*CREATE\s+OR\s+REPLACE\s+', 'DEFINE ', ddl_text, flags=re.IGNORECASE)
        # Pattern 2: Handle "CREATE <TYPE>" (fallback)
        ddl_text = re.sub(r'^\s*CREATE\s+', 'DEFINE ', ddl_text, flags=re.IGNORECASE)

        # Regex Patching for FQNs
        for target_obj in object_map:
            t_name = target_obj['name']
            t_fqn = target_obj['fqn']
            pattern = r'(?i)(?<!\.|"|")\b{}\b'.format(re.escape(t_name))
            ddl_text = re.sub(pattern, t_fqn, ddl_text)

        # Upload Stream
        file_name = f"{db_name}__{schema}__{short_name}.sql"
        full_stage_path = f"{stage_root}/{file_name}"

        input_stream = io.BytesIO(ddl_text.encode('utf-8'))

        session.file.put_stream(input_stream, full_stage_path, auto_compress=False, overwrite=True)

        generated_files.append(("SAVED", file_name, full_stage_path))

    # 4. Return Result
    if generated_files:
        return session.create_dataframe(
            generated_files,
            schema=["STATUS", "FILE_NAME", "TARGET_PATH"]
        )
    else:
         return session.create_dataframe(
            [("NONE", "No files generated", stage_root)],
            schema=["STATUS", "FILE_NAME", "TARGET_PATH"]
        )
$$;


CALL DCM_DEMO.PROJECTS.GENERATE_DEFINITIONS(
    'DCM_DEMO_2',       -- Database Name
    NULL,   --['RAW'],                    -- Whitelist: Only process this schema
    'snow://workspace/USER$.PUBLIC.DCM_DEMO/versions/live/Internal Testing/test_proc'
);

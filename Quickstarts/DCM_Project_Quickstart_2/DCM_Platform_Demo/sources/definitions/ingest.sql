define schema DCM_DEMO_2.INGEST;

define stage DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA
    directory = ( enable = true )
    comment = 'for csv files with sample data to demo DCM Pipeline project';

define task DCM_DEMO_2.INGEST.LOAD_NEW_DATA
    schedule='USING CRON 15 8-18 * * MON-FRI CET'
    comment = 'loading sample data to demo DCM Pipeline project'
as 
begin
        
    -- Load fact tables
    copy into 
        DCM_DEMO_2.RAW.DATE_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/DATE_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.HR_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/HR_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.INDUSTRY_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/INDUSTRY_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.STATUSTYPE_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/STATUSTYPE_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.TAXRATE_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/TAXRATE_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.TIME_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/TIME_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.TRADETYPE_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/TRADETYPE_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.ACCOUNT_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/ACCOUNT_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.CASHTRANSACTION_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/CASHTRANSACTION_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.CUSTOMER_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/CUSTOMER_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.DAILYMARKET_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/DAILYMARKET_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.FINWIRE_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/FINWIRE_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.HOLDINGHISTORY_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/HOLDINGHISTORY_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.PROSPECT_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/PROSPECT_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.TRADE_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/TRADE_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.TRADEHISTORY_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/TRADEHISTORY_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;

    copy into 
        DCM_DEMO_2.RAW.WATCH_HISTORY_STG
    from 
        '@DCM_DEMO_2.INGEST.DCM_SAMPLE_DATA/WATCH_HISTORY_STG.csv'
    file_format = DCM_DEMO_2.INGEST.CSV_FORMAT
    on_error = continue;
    
    call SYSTEM$SET_RETURN_VALUE('✅ raw dataset loaded into all staging tables');
end;


attach post_hook
as
[
    create file format if not exists DCM_DEMO_2.INGEST.CSV_FORMAT
        TYPE = CSV
        COMPRESSION = NONE
        FIELD_OPTIONALLY_ENCLOSED_BY = '"'
        SKIP_HEADER = 1
        FIELD_DELIMITER = ','
        NULL_IF = ('NULL', 'null', '')
        EMPTY_FIELD_AS_NULL = TRUE
    ;
];
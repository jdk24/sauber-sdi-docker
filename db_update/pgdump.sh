

NEW_STRUCT=`ls -t new_structures | head -n1`
NEW_STRUCT_TS=`stat -c "%Y" new_structures/$NEW_STRUCT`

LATEST_DMP_TS=`ls -t pg_dumps | head -n1`
LATEST_STRUCT_TS=`stat -c "%Y" pg_dumps/$NEW_STRUCT`

if ! [ $LATEST_DMP_TS > $LATEST_STRUCT_TS ] ; then

    OUTFILE=backup_$(date "+%Y%m%d_%H%M%S")
    echo "dumping latest database state to $OUTFILE"
    
    if PGPASSWORD=$POSTGRES_INIT_PASSWORD pg_dumpall -s -h db -U postgres > pg_dumps/$OUTFILE.sql; then
        if PGPASSWORD=$POSTGRES_INIT_PASSWORD psql -h db -U postgres -d sauber_data -c 'SELECT timescaledb_pre_restore();' ; then
            if PGPASSWORD=$POSTGRES_INIT_PASSWORD psql -U postgres -Atc "select 'drop database \"'||datname||'\";' from pg_database where datistemplate=false;" | PGPASSWORD=$POSTGRES_INIT_PASSWORD psql -U postgres -d postgres ; then 
                if PGPASSWORD=$POSTGRES_INIT_PASSWORD psql -h db -U postgres < new_structures/$NEW_STRUCT ; then
                    if PGPASSWORD=$POSTGRES_INIT_PASSWORD psql -h db -U postgres -d sauber_data -c 'SELECT timescaledb_pre_restore();' ; then
                        echo 'Finished updating new database structure'
                    else echo 'Warning: TimscaleDB-post-restore not set'; fi
                else echo 'Error restoring databases'; fi
            else echo 'Error dropping existing databases'; fi
        else echo "Error: Could not set TimescaleDB to restore mode."; fi
    else echo "Error: Could not backup DB."; fi
else echo "Error: New DB structure file is older than latest Database dump. Check file or update creation time."; fi

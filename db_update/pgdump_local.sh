#!/bin/bash

NEW_STRUCT=`ls -t db_structure | head -n1`
NEW_STRUCT_TS=`stat -c "%Y" db_structure/$NEW_STRUCT`

LATEST_BK=`ls -t db_backup | head -n1`
LATEST_BK_TS=`stat -c "%Y" db_backup/$LATEST_BK`

if [ ${NEW_STRUCT_TS} -gt ${LATEST_BK_TS} ] ; then

    OUTFILE=backup_$(date "+%Y%m%d_%H%M%S")
    echo "dumping latest database state to $OUTFILE"
    
    if PGPASSWORD=$POSTGRES_INIT_PASSWORD pg_dumpall -p 5449 -s  -U postgres > db_backup/$OUTFILE.sql; then
        if PGPASSWORD=$POSTGRES_INIT_PASSWORD psql -p 5449  -U postgres -d sauber_data -c 'SELECT timescaledb_pre_restore();' ; then 
                if PGPASSWORD=$POSTGRES_INIT_PASSWORD psql -p 5449  -U postgres < db_structure/$NEW_STRUCT ; then
                    if PGPASSWORD=$POSTGRES_INIT_PASSWORD psql -p 5449  -U postgres -d sauber_data -c 'SELECT timescaledb_pre_restore();' ; then
                        echo 'Finished updating new database structure'
                    else echo 'Warning: TimscaleDB-post-restore not set'; fi
                else echo 'Error restoring databases'; fi
        else echo "Error: Could not set TimescaleDB to restore mode."; fi
    else echo "Error: Could not backup DB structure."; fi
else echo "Error: New DB structure file is older than latest Database dump. Check file or update creation time."; fi

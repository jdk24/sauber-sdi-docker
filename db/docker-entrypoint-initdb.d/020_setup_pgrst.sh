# Set up pgREST roles and structures 
# Seach for 'STEP' comments for key steps  

# STEP 1: Add any new DBs to list that pgREST should access
INIT_DBS="here sauber_data"

# Read secrets
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	#echo "$var,$val"
	export "$var"="$val"
	unset "$fileVar" 
}

# STEP 2: Add other token secrets if necessary
secrets=(
    PGRST_JWT_SECRET
    PGRST_PASSWORD
)

for e in "${secrets[@]}"; do
		file_env "$e"
done

# Check if all tokens are set
envs=(
    PGRST_JWT_SECRET
    PGRST_PASSWORD
)

for e in "${envs[@]}"; do
	if [ -z ${!e:-} ]; then
		echo "error: Env $e is not set"
		exit 1
	fi
done


# STEP 4: Grant pgREST roles basic priviliges.
# STEP 5: Create pgREST structure for JWT and basic auth. 
for DB in $INIT_DBS; do
    echo "Setting up PostgREST access in $DB"
    psql -d $DB -q<<- 'EOSQL'

    CREATE schema IF NOT EXISTS basic_auth;
    CREATE TYPE  basic_auth.jwt_token AS (
    token text
    );
    CREATE table IF NOT EXISTS
    basic_auth.users (
    email    text primary key check ( email ~* '^.+@.+\..+$' ),
    pass     text not null check (length(pass) < 512),
    role     name not null check (length(role) < 512)
    );

    CREATE or replace function
    basic_auth.check_role_exists() returns trigger AS $$
    begin
    IF NOT EXISTS (select 1 from pg_roles AS r where r.rolname = new.role) then
        raise foreign_key_violation using message =
        'unknown database role: ' || new.role;
        return null;
    end if;
    return new;
    end
    $$ language plpgsql;

    drop trigger if exists ensure_user_role_exists on basic_auth.users;

    CREATE constraint trigger ensure_user_role_exists
    after insert or update on basic_auth.users
    for each row
    execute procedure basic_auth.check_role_exists();

    CREATE extension IF NOT EXISTS pgcrypto;

    CREATE or replace function
    basic_auth.encrypt_pass() returns trigger AS $$
    begin
    if tg_op = 'INSERT' or new.pass <> old.pass then
        new.pass = crypt(new.pass, gen_salt('bf'));
    end if;
    return new;
    end
    $$ language plpgsql;

    drop trigger if exists encrypt_pass on basic_auth.users;
    CREATE trigger encrypt_pass
    before insert or update on basic_auth.users
    for each row
    execute procedure basic_auth.encrypt_pass();

    CREATE or replace function
    basic_auth.user_role(email text, pass text) returns name
    language plpgsql
    AS $$
    begin
    return (
    select role from basic_auth.users
    where users.email = user_role.email
        and users.pass = crypt(user_role.pass, users.pass)
    );
    end;
    $$;

    CREATE or replace function
    login(email text, pass text) returns basic_auth.jwt_token AS $$
    declare
    _role name;
    result basic_auth.jwt_token;
    begin
    -- check email and password
    select basic_auth.user_role(email, pass) into _role;
    if _role is null then
        raise invalid_password using message = 'invalid user or password';
    end if;

    SELECT sign(
    row_to_json(r), current_setting('app.jwt_secret')
    ) AS token
    FROM (
        select _role AS role, login.email AS email,
            extract(epoch from now())::integer + 60*60 AS exp
        ) r
        into result;
    return result;
    end;
    $$ language plpgsql;

    CREATE or replace function
    login(email text, pass text) returns basic_auth.jwt_token AS $$
    declare
    _role name;
    result basic_auth.jwt_token;
    begin
    -- check email and password
    select basic_auth.user_role(email, pass) into _role;
    if _role is null then
        raise invalid_password using message = 'invalid user or password';
    end if;

    SELECT sign(
    row_to_json(r), current_setting('app.jwt_secret')
    ) AS token
    FROM  (
        select _role AS role, login.email AS email,
            extract(epoch from now())::integer + 60*60 AS exp
        ) r
        into result;
    return result;
    end;
    $$ language plpgsql;

    GRANT USAGE ON schema public, basic_auth to anon;
    GRANT SELECT ON table pg_authid, basic_auth.users to anon;
    GRANT EXECUTE ON function login(text,text) to anon;
EOSQL
done 

# STEP 6: Set secret JWT token 
# Append new tokens if necessary
# For var expansion, EOSQL must NOT be quoted 
for DB in $INIT_DBS; do
    echo "Setting JWT Secret"
    psql -q <<-EOSQL
    SET "app.jwt_secret" TO $PGRST_JWT_SECRET;
EOSQL
done

# STEP 7: Grant pgREST roles access to actual DB data. 

psql -d here -q <<-'EOSQL' 
    GRANT USAGE ON SCHEMA here_traffic TO anon; 
    GRANT SELECT ON ALL TABLES IN SCHEMA here_traffic TO anon;
EOSQL

psql -d sauber_data -q <<-'EOSQL'
    GRANT USAGE ON SCHEMA image_mosaics TO app;
    GRANT USAGE ON SCHEMA station_data TO app;
    GRANT ALL ON FUNCTION station_data.createlogentry(pload jsonb) TO app;
    GRANT ALL ON FUNCTION station_data.lanuv_parse(input_ts text) TO app;
    GRANT ALL ON FUNCTION station_data.lubw_parse() TO app;
    GRANT ALL ON FUNCTION station_data.prediction_parse() TO app;
    GRANT ALL ON SEQUENCE station_data.logtable_idpk_log_seq TO app;
    GRANT ALL ON SEQUENCE station_data.lut_component_idpk_component_seq TO app;
    GRANT ALL ON SEQUENCE station_data.lut_station_idpk_station_seq TO app;
    GRANT ALL ON SEQUENCE station_data.prediction_input_idpk_json_seq TO app;
    GRANT ALL ON SEQUENCE station_data.tab_measurement_idpk_prediction_seq TO app;
    GRANT ALL ON SEQUENCE station_data.tab_prediction_idpk_value_seq TO app;
    GRANT ALL ON TABLE station_data.input_lanuv TO app;
    GRANT ALL ON TABLE station_data.input_lubw TO app;
    GRANT ALL ON TABLE station_data.input_prediction TO app;
    GRANT CREATE ON DATABASE sauber_data TO app;
    GRANT SELECT,INSERT,UPDATE ON TABLE image_mosaics.raster_metadata TO app;
    GRANT SELECT,INSERT,UPDATE ON TABLE station_data.logtable TO app;
    GRANT SELECT,INSERT,UPDATE ON TABLE station_data.lut_component TO app;
    GRANT SELECT,INSERT,UPDATE ON TABLE station_data.lut_station TO app;
    GRANT SELECT,INSERT,UPDATE ON TABLE station_data.tab_measurement TO app;
    GRANT SELECT,INSERT,UPDATE ON TABLE station_data.tab_prediction TO app;
    GRANT SELECT,USAGE ON SEQUENCE image_mosaics.raster_metadata_idpk_image_seq TO app;
    GRANT SELECT,USAGE ON SEQUENCE station_data.tab_prediction_idpk_value_seq TO sauber_user;
    GRANT SELECT ON TABLE image_mosaics.raster_metadata TO sauber_user;
    GRANT SELECT ON TABLE station_data.fv_wfs TO sauber_user;
    GRANT SELECT ON TABLE station_data.logtable TO sauber_user;
    GRANT SELECT ON TABLE station_data.lut_component TO sauber_user;
    GRANT SELECT ON TABLE station_data.lut_station TO sauber_user;
    GRANT SELECT ON TABLE station_data.tab_measurement TO sauber_user;
    GRANT SELECT ON TABLE station_data.tab_prediction TO sauber_user;
    GRANT SELECT,INSERT,UPDATE ON TABLE image_mosaics.raster_metadata TO sauber_user;
    GRANT SELECT,USAGE ON SEQUENCE image_mosaics.raster_metadata_idpk_image_seq TO sauber_user;
    GRANT SELECT,USAGE ON SEQUENCE station_data.logtable_idpk_log_seq TO sauber_user;
    GRANT SELECT,USAGE ON SEQUENCE station_data.lut_component_idpk_component_seq TO sauber_user;
    GRANT SELECT,USAGE ON SEQUENCE station_data.lut_station_idpk_station_seq TO sauber_user;
    GRANT SELECT,USAGE ON SEQUENCE station_data.prediction_input_idpk_json_seq TO sauber_user;
    GRANT SELECT,USAGE ON SEQUENCE station_data.tab_measurement_idpk_prediction_seq TO sauber_user;
    GRANT USAGE ON SCHEMA image_mosaics TO sauber_user;
    GRANT USAGE ON SCHEMA station_data TO sauber_user;
    GRANT USAGE ON SCHEMA station_data TO anon;
    GRANT USAGE ON SCHEMA basic_auth TO anon;
    GRANT SELECT ON TABLE basic_auth.users TO anon;
    GRANT USAGE ON SCHEMA daten TO anon;
    GRANT USAGE ON SCHEMA image_mosaics TO anon;
    GRANT SELECT,INSERT,UPDATE(is_published) ON TABLE image_mosaics.raster_metadata TO anon;
    GRANT SELECT,USAGE ON SEQUENCE image_mosaics.raster_metadata_idpk_image_seq TO anon;
    GRANT SELECT ON TABLE pg_catalog.pg_authid TO anon;
    GRANT SELECT ON TABLE station_data.logtable TO anon;
    GRANT SELECT ON TABLE station_data.lut_component TO anon;
    GRANT SELECT ON TABLE station_data.lut_region TO anon;
    GRANT SELECT ON TABLE station_data.lut_station TO anon;
    GRANT SELECT ON TABLE station_data.tab_measurement TO anon;
    GRANT SELECT ON TABLE station_data.tab_prediction TO anon;
    GRANT anon TO authenticator GRANTED BY postgres;
    GRANT ALL ON FUNCTION public.login(email text, pass text) TO anon;
EOSQL

#echo 'PGRST PASSWORD: ' $PGRST_PASSWORD
#echo 'TOKEN: ' $PGRST_JWT_SECRET
# STEP 8: Set password for role authenticator 
psql -q -U "${POSTGRES_USER}" -c "ALTER ROLE authenticator PASSWORD '$PGRST_PASSWORD';"
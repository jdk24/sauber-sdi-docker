#!/bin/bash

for file in /run/secrets/* ;
	do
	echo $(basename "$file" | tr a-z A-Z)=$(cat $file)
	# uppercase file basename env var = file contents
done

export CATALINA_OPTS="${CATALINA_OPTS} \
	-Djdbc.username=\"${POSTGRES_USER}\" \
	-Djdbc.password=\"${SAUBER_MANAGER_PASSWORD}\""
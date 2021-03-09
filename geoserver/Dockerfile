FROM meggsimum/geoserver:2.18.2

# see http://docs.geoserver.org/stable/en/user/production/container.html
ENV CATALINA_OPTS='-Xms256m -Xmx1g -Dfile.encoding=UTF-8 -D-XX:SoftRefLRUPolicyMSPerMB=36000 -Xbootclasspath/a:$CATALINA_HOME/lib/marlin.jar -Xbootclasspath/p:$CATALINA_HOME/lib/marlin-sun-java2d.jar -Dsun.java2d.renderer=org.marlin.pisces.PiscesRenderingEngine -Dorg.geotools.coverage.jaiext.enabled=true'
#
WORKDIR /tmp

RUN apk -U upgrade --update && \ 
    apk add curl

# Add JNDI datasource
COPY conf/context.xml $CATALINA_HOME/conf/context.xml

# Add the postgresql driver to tomcat for JNDI access.
RUN rm $GEOSERVER_LIB_DIR/postgresql-*.jar
WORKDIR $CATALINA_HOME/lib
RUN curl -jkSL https://jdbc.postgresql.org/download/postgresql-42.2.19.jar -o postgresql-42.2.19.jar
RUN chmod 775 postgresql-42.2.19.jar

# Add script to pass environment vars into tomcat.
RUN echo $CATALINA_HOME
COPY conf/read_secrets.sh $CATALINA_HOME/bin/setenv.sh
RUN chmod 775 $CATALINA_HOME/bin/setenv.sh

RUN ls -l $CATALINA_HOME/bin/

WORKDIR /
CMD ["$CATALINA_HOME/bin/setenv.sh"]
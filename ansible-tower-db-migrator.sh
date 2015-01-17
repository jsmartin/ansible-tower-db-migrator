#! /bin/bash -ex

NEW_DB_HOST=foo.us-east-1.rds.amazonaws.com
NEW_DB_ADMIN_USER=dbadmin
NEW_DB_ADMIN_PW=password
NEW_DB_AWX_PW=password

DB_CONFIG="/etc/tower/conf.d/postgres.py"

echo ""

if [ ! -w $DB_CONFIG ]; then
	echo "You must run the script with a user who has write permission to"
	echo $DB_CONFIG
	echo ""
fi

if [ ! -d /etc/tower ];then
	echo "No Tower installation found."
	exit 1
fi

# ensure connection/access to remote instance

db_password=$(grep PASSWORD $DB_CONFIG |awk 'BEGIN {FS="\"\"\""} {print $2}')

#echo the db password is $password


# dump the current database, could alternately write to .pgpass of operating user
echo "Dumping the current database to /var/lib/awx/db-migrate.sql"
PGPASSWORD=$db_password pg_dump -U awx awx  -f /tmp/db.sql --no-acl --no-owner 

if [ $? != 0 ]; then
	echo "There was a problem exporting the database."
	exit 1
fi


# stop tower
ansible localhost -m service -a "name=ansible-tower state=stopped" --connection=local -s


echo "create awx database on the remote side"
ansible localhost -m postgresql_db -a "name=awx login_user=$NEW_DB_ADMIN_USER login_password=$NEW_DB_ADMIN_PW login_host=$NEW_DB_HOST db=awx" --connection=local

echo "creating the awx user on the remote side"
ansible localhost -m postgresql_user -a "name=awx password=$NEW_DB_AWX_PW login_user=$NEW_DB_ADMIN_USER login_password=$NEW_DB_ADMIN_PW login_host=$NEW_DB_HOST db=awx" --connection=local


echo "Now going to import the database to the new location"
PGPASSWORD=$NEW_DB_ADMIN_PW psql  -h $NEW_DB_HOST -U $NEW_DB_ADMIN_USER awx < /tmp/db.sql

if [ $? != 0 ]; then
	echo "There was a problem importing the database."
	exit 1
fi

 #modifying the owner of the tables to the awx user, the postgres super user role on RDS is not
# able to REASSIGN (not a real superuser)
sql=$(PGPASSWORD=$NEW_DB_ADMIN_PW psql -h $NEW_DB_HOST -U $NEW_DB_ADMIN_USER -qAt -c "SELECT 'ALTER TABLE '|| schemaname || '.' || tablename ||' OWNER TO awx;' FROM pg_tables WHERE NOT schemaname IN ('pg_catalog', 'information_schema') ORDER BY schemaname, tablename;" awx) 

echo "Fixing table ownership"
PGPASSWORD=$NEW_DB_ADMIN_PW psql -h $NEW_DB_HOST -U $NEW_DB_ADMIN_USER  -c "$sql" awx

echo "backing up configuration file"
cp /etc/tower/conf.d/postgres.py /etc/tower/conf.d/postgres.py.pre-migrate.$(date +"%s")

echo "writing new configuration file"
cat << EOF > /etc/tower/conf.d/postgres.py

# Ansible Tower database settings.

DATABASES = {
   'default': {
       'ATOMIC_REQUESTS': True,
       'ENGINE': 'django.db.backends.postgresql_psycopg2',
       'NAME': 'awx',
       'USER': 'awx',
       'PASSWORD': """$NEW_DB_AWX_PW""",
       'HOST': '$NEW_DB_HOST',
       'PORT': 5432,
   }
}

# Use SQLite for unit tests instead of PostgreSQL.
if len(sys.argv) >= 2 and sys.argv[1] == 'test':
    DATABASES = {
        'default': {
            'ATOMIC_REQUESTS': True,
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': '/var/lib/awx/awx.sqlite3',
            # Test database cannot be :memory: for celery/inventory tests.
            'TEST_NAME': '/var/lib/awx/awx_test.sqlite3',
        }
    }
EOF

echo "Starting Tower"
ansible localhost -m service -a "name=ansible-tower state=started" --connection=local -s







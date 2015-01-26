#! /bin/bash -e

vercomp () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

testvercomp () {
    vercomp $1 $2
    case $? in
        0) op='=';;
        1) op='>';;
        2) op='<';;
    esac
    if [[ $op != $3 ]]
    then
        echo "FAIL: Expected '$3', Actual '$op', Arg1 '$1', Arg2 '$2'"
    else
        echo "Pass: '$1 $op $2'"
    fi
}

fetchPyValue () {
python  -c "import sys; execfile(\"$DB_CONFIG\"); print DATABASES[\"default\"][\"$1\"]"
}



detectOSfamily() {
  DISTRIBID=$(ansible -m setup localhost|grep ansible_os_family|cut -f2 -d':'|tr -d '"'|tr -d ','|tr -d ' ')
}

detectOldSettings() {

# get current db name
#OLD_AWX_DB_NAME=$(grep -m1 NAME $DB_CONFIG | awk -F\' '{print $4}')
OLD_AWX_DB_NAME=$(fetchPyValue NAME)

# get the current db password
OLD_AWX_DB_PW=$(fetchPyValue PASSWORD)

# get the current db user
OLD_AWX_DB_USER=$(fetchPyValue USER)

# get the current db host
OLD_DB_HOST=$(fetchPyValue HOST)

# get the current db port
OLD_DB_HOST_PORT=$(fetchPyValue PORT)

}

promptOldSettings() {

if [ ! -n "$OLD_DB_HOST" ]; then
    read -p "Enter old DB host: " OLD_DB_HOST
fi

if [ ! -n "$OLD_DB_HOST_PORT" ]; then
    read -p "Enter OLD DB host port: " -e -i 5432 OLD_DB_HOST_PORT
fi

if [ ! -n "$OLD_AWX_DB_NAME" ]; then
    read -p "Enter old Tower DB name: " OLD_AWX_DB_NAME
fi

if [ ! -n "$OLD_AWX_DB_USER" ]; then
    read -p "Enter old Tower DB user: " OLD_AWX_DB_USER
fi

if [ ! -n "$OLD_AWX_DB_PW" ]; then
    while true
        do
            read -s -p "Enter old Tower DB user password: " password
            echo
            read -s -p "Enter old Tower DB user password (again): " password2
            echo
            [ "$password" = "$password2" ] && break
            echo "Please try again"
        done
    OLD_AWX_DB_PW=$password
fi

}



promptNewSettings() {
 if [ ! -n "$NEW_DB_HOST" ]; then
    read -p "Enter new DB host: " NEW_DB_HOST
 fi

 if [ ! -n "$NEW_DB_HOST_PORT" ]; then
   read -p "Enter NEW DB host port: " -e -i 5432 NEW_DB_HOST_PORT
 fi

 if [ ! -n "$NEW_AWX_DB_NAME" ]; then
   read -p "Enter new Tower DB name: " NEW_AWX_DB_NAME
 fi

 if [ ! -n "$NEW_AWX_DB_USER" ]; then
   read -p "Enter new Tower DB user: " NEW_AWX_DB_USER
 fi


 if [ ! -n "$NEW_AWX_DB_PW" ]; then
    while true
    do
        read -s -p "Enter new Tower DB user password: " password
        echo
        read -s -p "Enter new Tower DB user password (again): " password2
        echo
        [ "$password" = "$password2" ] && break
        echo "Please try again"
    done
   NEW_AWX_DB_PW=$password
 fi


 if [ ! -n "$NEW_DB_ADMIN_USER" ]; then
   read -p "Enter new DB admin user: " NEW_DB_ADMIN_USER
 fi

 if [ ! -n "$NEW_DB_ADMIN_PW" ]; then
    while true
    do
        read -s -p "Enter new DB admin user password: " password
        echo
        read -s -p "Enter new DB admin user password (again): " password2
        echo
        [ "$password" = "$password2" ] && break
        echo "Please try again"
    done
   NEW_DB_ADMIN_PW=$password
 fi

}

detectRequirements () {

echo "Checking writing permission for $DB_CONFIG"
if [ ! -w $DB_CONFIG ]; then
    echo "You must run the script with a user who has write permission to"
    echo $DB_CONFIG
    exit 1
else
    echo "Success"
fi

echo "Checking for Tower installation"
if [ ! -d /etc/tower ];then
    echo "No Tower installation found."
    exit 1
else
    echo "Success"
fi

}

#optinally load a settings file that contains new and old db parameters
if [  -n "$1" ] && [ -r "$1" ]; then
        source $1
fi


### Begin 
if [ -z "$DB_CONFIG"]; then
    DB_CONFIG="/etc/tower/conf.d/postgres.py"
fi

if [ -z "$DB_DUMP_FILE"]; then
    DB_DUMP_FILE="$HOME/ansible-tower-db-migrate.sql"
fi

echo ""
detectRequirements
promptNewSettings
detectOSfamily


# make sure Tower 2.1 or greater

if [ -x $(which tower-manage) ]; then
    T_MANAGE=$(which tower-manage)
else
    echo "Could not find tower-manage"
    exit 1
fi

TOWER_VERSION=$($T_MANAGE version)

CMP=$(printf "2.1.0\n$TOWER_VERSION" | sort --version-sort|head -1)

if [ "$CMP" != "2.1.0" ]; then
    echo "Ansible Tower version must be >= 2.1.0"
fi



echo "create awx database on the remote side"
ansible localhost -m postgresql_db -a "name=$NEW_AWX_DB_NAME port=$NEW_DB_HOST_PORT login_user=$NEW_DB_ADMIN_USER login_password=$NEW_DB_ADMIN_PW login_host=$NEW_DB_HOST" --connection=local


#prompt to confirm these things, and allow for override

echo "I need the settings for the database currently being used by Tower"
echo "Shall I attempt to detect these myself?"

read -r -p "Are you sure? [y/N] " detect_settings
if [[ $detect_settings =~ ^([yY][eE][sS]|[yY])$ ]]
then
    detectOldSettings
else
    promptOldSettings
fi



#echo the db password is $password

# stop all services but DB

if [[ $DISTRIBID == "Debian" ]]
then
  ansible localhost -m service -a "name=apache2 state=stopped" --connection=local -s
  ansible localhost -m service -a "name=supervisor state=stopped" --connection=local -s
  ansible localhost -m service -a "name=redis-server state=stopped" --connection=local -s
else
 ansible localhost -m service -a "name=httpd state=stopped" --connection=local -s
 ansible localhost -m service -a "name=supervisord state=stopped" --connection=local -s
 ansible localhost -m service -a "name=redis state=stopped" --connection=local -s
fi



# dump the current database, could alternately write to .pgpass of operating user
echo "Dumping the current database to $DB_DUMP_FILE"
PGPASSWORD=$OLD_AWX_DB_PW pg_dump -h "$OLD_DB_HOST" -p $OLD_DB_HOST_PORT -U $OLD_AWX_DB_USER $OLD_AWX_DB_NAME  -f $DB_DUMP_FILE --no-acl --no-owner 

if [ $? != 0 ]; then
    echo "There was a problem dumping the database."
    exit 1
fi

# stop DB
ansible localhost -m service -a "name=postgresql state=stopped" --connection=local -s


echo "creating the awx user on the remote side"
ansible localhost -m postgresql_user -a "name=$NEW_AWX_DB_USER password=$NEW_AWX_DB_PW login_user=$NEW_DB_ADMIN_USER login_password=$NEW_DB_ADMIN_PW login_host=$NEW_DB_HOST port=$NEW_DB_HOST_PORT db=$NEW_AWX_DB_NAME" --connection=local


echo "Now going to import the database to the new location"
PGPASSWORD=$NEW_DB_ADMIN_PW psql  -h $NEW_DB_HOST -p $NEW_DB_HOST_PORT -U $NEW_DB_ADMIN_USER $NEW_AWX_DB_NAME -f $DB_DUMP_FILE

if [ $? != 0 ]; then
    echo "There was a problem importing the database."
    exit 1
fi

# Modifying the owner of the tables to the awx user because RDS rds_superuser is not
# able to REASSIGN (not a real superuser)
sql=$(PGPASSWORD=$NEW_DB_ADMIN_PW psql -h $NEW_DB_HOST -p $NEW_DB_HOST_PORT -U $NEW_DB_ADMIN_USER -qAt -c "SELECT 'ALTER TABLE '|| schemaname || '.' || tablename ||' OWNER TO $NEW_AWX_DB_USER;' FROM pg_tables WHERE NOT schemaname IN ('pg_catalog', 'information_schema') ORDER BY schemaname, tablename;" $NEW_AWX_DB_NAME) 

echo "Fixing table ownership"
PGPASSWORD=$NEW_DB_ADMIN_PW psql -h $NEW_DB_HOST -p $NEW_DB_HOST_PORT -U $NEW_DB_ADMIN_USER  -c "$sql" awx

echo "backing up configuration file"
cp /etc/tower/conf.d/postgres.py /etc/tower/conf.d/postgres.py.pre-migrate.$(date +"%s")

echo "writing new configuration file"
cat << EOF > /etc/tower/conf.d/postgres.py

# Ansible Tower database settings.

DATABASES = {
   'default': {
       'ATOMIC_REQUESTS': True,
       'ENGINE': 'django.db.backends.postgresql_psycopg2',
       'NAME': '$NEW_AWX_DB_NAME',
       'USER': '$NEW_AWX_DB_USER',
       'PASSWORD': """$NEW_AWX_DB_PW""",
       'HOST': '$NEW_DB_HOST',
       'PORT': $NEW_DB_HOST_PORT,
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







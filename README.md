# Ansible Tower DB Migrator

## Description
This script is designed to help you migrate your Ansible Tower database from one system to another.

## Requirements

You must download this script and run it from your Ansible Tower server.

**Please backup your Ansible Tower postgres database before performing this operation.**

## Flow

The script performs the following:

1. Prompts you for connection information to your new database server.
2. Connects and creates the new Ansible Tower database
3. Attempts to detect connection information to old database.
4. Stops all Ansible Tower services (except postgres)
5. Performs a pg_dump on the old database
6. Stops old postgres service
7. Creates new Ansible Tower database user.
8. Moves dumped data to new postgres instance
9. Makes sure new DB tables are owned by the correct user.
10. A backup of your /etc/tower/conf.d/postgres.py is made with a timestmap.
11. Writes a new Ansible Tower postgres.py file containing new connection information.


## Issues

If the script fails, please drop the user and the db on the new postgres instance.

    PGPASSWORD=password dropdb -h foo.rds.amazonaws.com -U dbadmin awx
    PGPASSWORD=password dropuser -h foo.rds.amazonaws.com -U dbadmin awx

And revert the backup settings file to the original (if it exists)

    cp /etc/tower/conf.d/postgres.py.pre-migrate.1421454626 /etc/tower/conf.d/postgres.py

And re-run the script

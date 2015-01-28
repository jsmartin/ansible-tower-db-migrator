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

## Glossary



### Old DB

The new DB is the old/current Tower DB 

If directed the script will automatically detect the connection settings for the old Tower DB.  If you decide to provide them yourself, they are:


| term              | definition                                                     |
|-------------------|----------------------------------------------------------------|
| old DB host       | the host where the old Tower postgres DB lives.                |
| old DB host port  | the port to use to connect to the old Tower postgres instance. |
| old Tower DB name | the name of the old Tower database                             |
| old Tower DB user | the name of the user to connect to the old Tower database      |
| old Tower DB user | password the password for the old Tower DB user                |


### New DB

The new DB is the proposed Tower DB 

You will be prompted for the **new** Tower DB connection settings:

| term              | definition                                                     |
|-------------------|----------------------------------------------------------------|
| new DB host       | the host where the new Tower postgres DB lives.                |
| new DB host port  | the port to use to connect to the new Tower postgres instance. |
| new Tower DB name | the name of the new Tower database                             |
| new Tower DB user | the name of the user to connect to the new Tower database      |
| new Tower DB user | password the password for the new Tower DB user                |
| new DB admin user | the name of the user that has a superuser role                 |
| new DB admin user password | the password of the user with the superuser role      |

## Issues

If the script fails, please drop the user and the db on the new postgres instance.

    PGPASSWORD=password dropdb -h foo.rds.amazonaws.com -U dbadmin awx
    PGPASSWORD=password dropuser -h foo.rds.amazonaws.com -U dbadmin awx

And revert the backup settings file to the original (if it exists)

    cp /etc/tower/conf.d/postgres.py.pre-migrate.1421454626 /etc/tower/conf.d/postgres.py

And re-run the script

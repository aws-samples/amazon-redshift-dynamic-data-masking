import redshift_connector, os, sys
from getpass import getpass

host = input("Cluster Host: ")
db = input("Database Name: ")
user = input("User: ")
port = int(input("Port: ") )
password = getpass("Password: ")

conn = redshift_connector.connect(database=db, host=host, user=user, password=password, port=port)
cur = conn.cursor()

f = open('f_mask_bigint.sql').read()
cur.execute(f)
f = open('f_mask_varchar.sql').read()
cur.execute(f)
f = open('f_mask_timestamp.sql').read()
cur.execute(f)

cur.close()
conn.close()

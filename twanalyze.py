# Import optimization job object
from twcollector import OptJob

# Import json for pretty printing
import json
import argparse

# Arguments definition and initialization
parser = argparse.ArgumentParser()
parser.add_argument('--db_user', action="store", dest='db_user', default=None)
parser.add_argument('--db_pass', action="store", dest='db_pass', default=None)
parser.add_argument('--db_host', action="store", dest='db_host', default=None)
parser.add_argument('--db_port', action="store", dest='db_port', default=None)
parser.add_argument('--db_sock', action="store", dest='db_sock', default=None)
parser.add_argument('--db_name', action="store", dest='db_name', default=None)
parser.add_argument('--auth_token', action="store", dest='auth_token', default=None)
parser.add_argument('--query_digest_file', action="store", dest='query_digest_file', default=None)
args = parser.parse_args()

sqjs = open(args.query_digest_file)
sqdict = json.load(sqjs)

#self,hostname,user,passwd,defdb,port,sqltext,token

for i,queryblock in enumerate(sqdict['classes']):

    # Skip empty queries
    if queryblock['example']['query'] == '/* No query */':
        continue
    print("============== Query ",i+1,"==================\n")
    sqltext = queryblock['example']['query']
    print(sqltext)
    if 'db' in queryblock['metrics'] and queryblock['metrics']['db']['value'] != "":
        dbname = queryblock['metrics']['db']['value']
    else:
        dbname = args.db_name

    # For each slow query instantiate optimization job by 
    # passing connections parameters, together with the query
    myjob =  OptJob(args.db_host,
    args.db_user,
    args.db_pass,
    dbname,
    int(args.db_port),
    sqltext,
    args.auth_token)

    # Run analysis
    myjob.analyze()

    print("Sending report to your email..")
    myjob.send_report()
    
    # Delete object
    del myjob

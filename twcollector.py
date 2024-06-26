#!/usr/bin/python

from sqlglot import parse_one, exp, errors
import pymysql
import json
import requests
import sys
import json_duplicate_keys

twengine_url = 'https://tuningwizard.query-optimization.com/api/'

def close_conn(dbconn):
    dbconn.close()


def get_table_names(sqltext):
    tables_dict={}
    try:
        sg_table_list = parse_one(sqltext,"mysql").find_all(exp.Table)
    except sqlglot.errors.ParseError:
        return tables_dict
    else:
        for table in sg_table_list:
            if '.' in str(table):
                table_db = str(table).split('.')[0]
                if table_db[0] == '"': table_db = table_db[1:]
                if table_db[-1] == '"': table_db = table_db[:-1]
            else:
                table_db = None
            tables_dict[table.name] = table_db
    return tables_dict

def rest_api_call(method,relpath,data,token):

    headers = { "Authorization" : "Token "+token,"Content-Type":"application/json" }
    try:
        if method == 'POST':
            response = requests.post(twengine_url+relpath, data = json.dumps(data), headers = headers)

        if method == 'PUT':
            response = requests.put(twengine_url+relpath, data = json.dumps(data), headers = headers)
    except:
        print("Failed to connect to the TWEngine API at",twengine_url)
        responsejs = {}
    else:
        if response.status_code != 200 and response.status_code != 202:
            print("Error calling the TWengine API. The server returned HTTP ",response.status_code,". Method:",method," - Path: ",relpath," - Data: ",data)
            responsejs = {}
        else:
            try: 
                responsejs = json.loads(response.text)
            except Exception as e:
                print("We couldn't parse the JSON returned by the TWEngine API")
                responsejs = {}
    return responsejs

def get_server_parameter(conn,var_name):

    result = None
    varref = '@@GLOBAL.'+var_name
    query = 'SELECT '+varref
    with conn.cursor() as cursor:
        cursor.execute(query)
        r = cursor.fetchone()
        result = r[varref]
    
    return result 


def collect_query_data(conn,sqltext,default_schema,token) :

    # Retrieve execution plan
    with conn.cursor() as cursor:
        explainstmt = 'EXPLAIN FORMAT=JSON '+sqltext
        try:
            cursor.execute(explainstmt)
        except Exception as err:
            print(err)
            return None
        else:
            r = cursor.fetchone()
            explaintxt = r['EXPLAIN']
            explainjs = json_duplicate_keys.loads(explaintxt)

    # Create Optimization Job
    data = {}
    optjob_res = rest_api_call('POST','optjobs/',data,token)
    if len(optjob_res.keys()) == 0:
        return None
    optjob_id = optjob_res['id']

    # Attach query
    data = {"sqltext" : sqltext, "hashval" : 'xxxxxx'}
    query_res = rest_api_call('POST','optjobs/'+optjob_id.__str__()+'/query/',data,token)
    if len(query_res.keys()) == 0:
        return optjob_id

    # Attach execution plan to job
    data = {"plan": json.dumps(explainjs.getObject())}
    qp_res = rest_api_call('POST','optjobs/'+optjob_id.__str__()+'/executionplan/',data,token)
    if len(qp_res.keys()) == 0:
        return optjob_id

    # Attach dbserver to job
    versionparam = get_server_parameter(conn,"version")
    version_comm_param = get_server_parameter(conn,"version_comment")

    if 'mariadb' in versionparam.lower() or 'mariadb' in version_comm_param.lower():
        server_type = 2
    elif 'percona' in versionparam.lower() or 'percona' in version_comm_param.lower():
        server_type = 3
    else:
        server_type = 1

    # Extract version number from version GV
    full_server_version = get_server_parameter(conn,"version")

    if '-' in full_server_version:
        server_version = full_server_version.split('-')[0]
    else:
        server_version = full_server_version    

    hostname = get_server_parameter(conn,"hostname")
    data = {"server_type":server_type,"server_version":server_version,"hostname":hostname}
    dbs_res = rest_api_call('POST','optjobs/'+optjob_id.__str__()+'/dbserver/',data,token)
    if len(dbs_res.keys()) == 0:
        return optjob_id

    # Get table stats
    tablesdict = get_table_names(sqltext)

    for tablename in tablesdict.keys():

        if tablesdict[tablename] == None:
            schema = default_schema
        else:
            schema = tablesdict[tablename]

        # Table data
        with conn.cursor() as cursor:
            cursor.execute('select TABLE_NAME,TABLE_SCHEMA,ENGINE,TABLE_ROWS,AVG_ROW_LENGTH,DATA_LENGTH,INDEX_LENGTH,TABLE_COLLATION  \
            from information_schema.tables where table_name = \''+tablename+'\' and table_schema = \''+schema+'\'')
            table_row = cursor.fetchall()

            # If no tables or more than one were returned, something is wrong
            if len(table_row) != 1:
                print("We couldn't retrieve information for table",tablename,"- Is it temporary?")
                return optjob_id

            table_row = table_row[0]

        # Column info
        with conn.cursor() as cursor:
            cursor.execute('select COLUMN_NAME,ORDINAL_POSITION,IS_NULLABLE,DATA_TYPE,CHARACTER_MAXIMUM_LENGTH,NUMERIC_PRECISION,NUMERIC_SCALE,CHARACTER_SET_NAME  \
            from information_schema.columns where table_name = \''+tablename+'\' and table_schema = \''+schema+'\'')

            columnsjson = {}
            while True:
                col_row = cursor.fetchone()
                if not col_row: break           

                CHARACTER_MAXIMUM_LENGTH = col_row['CHARACTER_MAXIMUM_LENGTH'] if col_row['CHARACTER_MAXIMUM_LENGTH'] != None else "null"
                NUMERIC_PRECISION = col_row['NUMERIC_PRECISION'] if col_row['NUMERIC_PRECISION'] != None else "null"
                NUMERIC_SCALE = col_row['NUMERIC_SCALE'] if col_row['NUMERIC_SCALE'] != None else "null"
                CHARACTER_SET_NAME = col_row['CHARACTER_SET_NAME'] if col_row['CHARACTER_SET_NAME'] != None else "null"

                # Build columns JSON
                columnsjson[col_row['COLUMN_NAME']] = {"ordinal_position":col_row['ORDINAL_POSITION'],"is_nullable":col_row['IS_NULLABLE'],
                "data_type":col_row['DATA_TYPE'],"character_maximum_length":CHARACTER_MAXIMUM_LENGTH,"numeric_precision":NUMERIC_PRECISION,
                "numeric_scale":NUMERIC_SCALE,"character_set_name":CHARACTER_SET_NAME}
        

        # Attach table data to job
        data = {"table_name":table_row['TABLE_NAME'],"schema_name":table_row['TABLE_SCHEMA'],"engine":table_row['ENGINE'],
        "rows":table_row['TABLE_ROWS'],"avg_row_length":table_row['AVG_ROW_LENGTH'],"data_length":table_row['DATA_LENGTH'],
        "index_length":table_row['INDEX_LENGTH'],"collation":table_row['TABLE_COLLATION'],"columns":columnsjson}

        table_res = rest_api_call('POST','optjobs/'+optjob_id.__str__()+'/tables/',data,token)
        if len(table_res.keys()) == 0:
            return optjob_id
        table_id = table_res['id']


        # Index data
        # Contemplate functional indexes in MySQL 8.0
        if server_type in [1,3] and server_version[0] == '8':
            index_query = 'select INDEX_NAME,NON_UNIQUE,SEQ_IN_INDEX,COLUMN_NAME,COLLATION,CARDINALITY,SUB_PART,PACKED,NULLABLE,INDEX_TYPE, \
            EXPRESSION from information_schema.statistics where table_name = \''+tablename+'\' and table_schema = \''+schema+'\''
        else:
            index_query = 'select INDEX_NAME,NON_UNIQUE,SEQ_IN_INDEX,COLUMN_NAME,COLLATION,CARDINALITY,SUB_PART,PACKED,NULLABLE,INDEX_TYPE \
            from information_schema.statistics where table_name = \''+tablename+'\' and table_schema = \''+schema+'\''

        with conn.cursor() as cursor:
            cursor.execute(index_query)
            
            while True:
                index_row = cursor.fetchone()
                if not index_row: break           

                # Attach index data to job
                if index_row['NULLABLE'] == 'YES':
                    nullable = True
                else:
                    nullable = False

                # Define the is_functional field
                is_functional = False
                expression = None
                if 'EXPRESSION' in index_row \
                and index_row['EXPRESSION'] != None \
                and index_row['COLUMN_NAME'] == None:
                    is_functional = True
                    expression = index_row['EXPRESSION']
            
                data = {
                    "key_name":index_row['INDEX_NAME'],
                    "unique":not bool(index_row['NON_UNIQUE']),
                    "seq_in_index":index_row['SEQ_IN_INDEX'],
                    "column_name":index_row['COLUMN_NAME'],
                    "cardinality":index_row['CARDINALITY'],
                    "sub_part":index_row['SUB_PART'],
                    "packed":index_row['PACKED'],
                    "nullable":nullable,
                    "index_type":index_row['INDEX_TYPE'],
                    "expression":expression,
                    "is_functional":is_functional
                }
                index_res = rest_api_call('POST','optjobs/'+optjob_id.__str__()+'/tables/'+table_id.__str__()+'/indexes/',data,token)
                if len(index_res.keys()) == 0:
                    return optjob_id
    return optjob_id


class QueryParseError(Exception):
    def __str__(self):
        return "The query could not be parsed"
    
class ConnectionError(Exception):
    def __str__(self):
        return "Could not connect to the database"

class OptJob:
    def __init__(self,hostname,user,passwd,defdb,port,sqltext,token):
        self.connection = None
        self.job_id = None
        self.token = token
        self.params = {'hostname':hostname, 'username':user,'password':passwd,'database':defdb,'port':port}

        #The current SQL parser can't handle \G
        sqlstrip = sqltext.strip()
        if sqlstrip[-1].upper() == 'G' and sqlstrip[-2] == '\\':
            sqltext = sqlstrip[:-2].strip()

        # Do not create a job if sqlglot can't properly parse the query
        try:
            parse_one(sqltext,"mysql").find_all(exp.Table)
        except Exception as e:
            print('Could not parse query')
        else:
            self.connection = self.create_conn()
            self.job_id = collect_query_data(self.connection,sqltext,self.params['database'],self.token)

    def __del__(self):
        if self.connection:
            close_conn(self.connection)

    def create_conn(self):
        try:
            dbconn = pymysql.connect(
                host=self.params['hostname'], 
                user=self.params['username'], 
                passwd=self.params['password'], 
                database=self.params['database'],
                port=self.params['port'],
                cursorclass=pymysql.cursors.DictCursor
            )
        except Exception as e:
            print("We got the following error connecting to the database:")
            print(e)
            sys.exit()
        else:
            return dbconn


    def analyze(self):
        if self.job_id == None:
            print("A job ID was not returned by the TWEngine API. This is either because it is not available or because an error ocurred while trying to create the job")
            self.analysis_result = {}
        else:
            query_res = rest_api_call('PUT','optjobs/'+self.job_id.__str__()+'/',{},self.token)
            self.analysis_result = query_res

    def send_report(self):
        if self.job_id != None:
            query_res = rest_api_call('POST','optjobs/'+self.job_id.__str__()+'/mailreport/',{},self.token)

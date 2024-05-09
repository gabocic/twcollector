# Tuning Wizard tools
In this repository, you will find two main scripts:

* **query_collector.sh:** a script that simplifies the process of sending your slow queries to the Tuning Wizard service. It will read the slow query log, sort and aggregate the slow queries to then submit them for review. It will also assist you in requesting the security token required to authenticate.

* **twcollector.py (recommended for developers)**: Python module to submit optimization jobs to tuningwizard.query-optimization.com


## Using query_collector.sh

### 1. Download the files in this repo

You can either use the "Download zip" option in the **<> Code** button or `git clone`

```bash
$ git clone https://github.com/gabocic/twcollector.git
```

### 2. Execute query_collector.sh and follow the instructions

```bash
(pve) gabriel@mypc:~/gitroot/twcollector$ ./query_collector.sh 
===========================================
=== Tuning Wizard - Slow query analyzer ===
===========================================

This tool will help you by: 
 - Sorting and priortizing the slow queries logged
 - Collecting the required info for analysis
 - Authenticating against Tuning Wizard
 - Submitting the queries for review

For that, you will need:
 * Database username and password
 * An email where we can send you the analysis report
 * A password to secure your token


DON'T Panic! the tool will guide you through the process


2024-05-09-14:03:25 [INFO] Checking that required tools are installed
2024-05-09-14:03:25 [INFO] mysql is present on the system
2024-05-09-14:03:25 [INFO] perl is present on the system
Please provide the Database user: admin
Please provide the Database password: 
If connecting through socket, please specify the path: 
Please provide the Database host [127.0.0.1]: 
Please provide the Database port [3306]: 
Please specify a default database name, in case we need it: airportdb
2024-05-09-14:03:36 [INFO] Successfully connected to database server
2024-05-09-14:03:36 [INFO] Slow query log is enabled
2024-05-09-14:03:36 [INFO] Long query time set to 10.000000 seconds
2024-05-09-14:03:36 [INFO] Minimum rows read to be included in the slow query log: 0
2024-05-09-14:03:36 [INFO] Slow query log output is set to FILE
2024-05-09-14:03:36 [INFO] Slow query log file path: /var/lib/mysql/mysql-slow.log
2024-05-09-14:03:36 [WARN] I can't access the slow query log in '/var/lib/mysql/mysql-slow.log'
Please specify the location of the slow query log: /tmp/mysql-slow.log
2024-05-09-14:03:42 [INFO] I will now aggregate and prioritize the slow queries..
You need a Tuning Wizard API token to authenticate. If you already have one, please paste it here. Otherwise, hit enter to request one:  
...

```

## Using twcollector.py 

### 1. Download the files in this repo

You can either use the "Download zip" option in the **<> Code** button or `git clone`

```bash
$ git clone https://github.com/gabocic/twcollector.git
```


### 2. Install the required modules

```bash
$ python -m pip install -r requirements.txt
```
*Optional: consider using a python virtual environment so you can keep the module dependencies isolated from your local installation. **This should be done before running pip install***

```bash

$ python -m venv /path/to/myenv

$ source /path/to/myenv/bin/activate
```

### 3. Create an account and retrieve your token

Below are two sample scripts: one using Python and the other using BASH. **Choose the one you prefer**

#### 3.a Using Python

Make sure you modify the dict with your name and email!

```python
import json
import requests

twengine_url = 'https://tuningwizard.query-optimization.com/api/'

def rest_api_call(method,relpath,data):

    headers = { "Content-Type":"application/json" }
    if method == 'POST':
        response = requests.post(twengine_url+relpath, data = json.dumps(data), headers = headers)

    if method == 'GET':
        response = requests.get(twengine_url+relpath, data = json.dumps(data), headers = headers)
    print(response.text)
    return response

# Replace values with your info
account = {
"email":"john.doe@domain.com",
"password":"fastquery2023",
"first_name":"John",
"last_name":"Doe"
}

# Sign up
rest_api_call('POST','accounts/signup/',account)

print("Check your email click the link to verify the account")
input("Press Enter to continue...")

# Retrieve your token
rest_api_call('POST','accounts/login/',account)

```

#### 3.b Using cURL

Don't forget to specify your name and email in the script!


```bash
# Replace the values with your info
echo '{
"email":"myemail@domain.com",
"password":"fastquery2023",
"first_name":"John",
"last_name":"Doe"
}' > account.json

# Sign up
curl -X POST -H 'Content-Type: application/json' -d "@account.json" 'https://tuningwizard.query-optimization.com/api/accounts/signup/'

# Check your email click the link to verify the account

# Login and get your token
curl -X POST -H 'Content-Type: application/json' -d "@account.json" 'https://tuningwizard.query-optimization.com/api/accounts/login/'
```


### 4. Edit params.json and configure the database connection parameters and API token

```json
{
    "hostname":"127.0.0.1",
    "username":"myuser",
    "password":"mypass",
    "port":3306,
    "dbname":"airportdb",
    "token":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
}

```


### 5. Submit an optimization job and profit!

```python
# Import optimization job object
from twcollector import OptJob

# Import json for pretty printing
import json

# Query to analyze
sqltext = "select b.price,b.seat,f.flightno,p.firstname,p.lastname  from  booking b,     passenger p,     flight f where b.flight_id = f.flight_id     and b.passenger_id = p.passenger_id     and f.departure between '2015-06-01 00:00:00' and '2015-06-02 00:00:00'"

# Instantiate optimization job by passing connections parameters, together with the query
pfile = open('params.json','r')
pjs = json.load(pfile)
myjob = OptJob(pjs["hostname"],pjs["username"],pjs["password"],pjs["dbname"],pjs["port"],sqltext,pjs["token"])

# Run analysis
myjob.analyze()

# Print job_id and analysis results
print(json.dumps(myjob.analysis_result,indent=4))

# Send a pdf report to the email registered above
myjob.send_report()

# Delete object
del myjob
```

## Sample output
```json
{
    "five_points_review": {
        "DATA_AMOUNT": [
            "Nothing to report for this tuning point"
        ],
        "LOOKUP_SPEED": [
            "49830938 rows were read from table `booking` by scanning it entirely. One or more conditions were specified for column `price` but no index exists for this column"
        ],
        "OPERATIONS": [
            "Nothing to report for this tuning point"
        ],
        "SCHEMA": [
            "All tables are using the same collation. This is important to avoid performance issues when joining tables.",
            "Duplicate indexes were found. See the recommendations section below for more details."
        ],
        "SERVER_CONFIGURATION": [
            "Nothing to report for this tuning point"
        ]
    },
    "recommendations": [
        {
            "title": "Create required index",
            "description": "We noticed that no index exists for the column included on the WHERE clause (`price`) for table `booking`. You can create it by using the attached CREATE INDEX statement",
            "type": "LOOKUP_SPEED",
            "level": "SERVER",
            "sql": [
                "CREATE INDEX idx_price ON booking(price) ALGORITHM=INPLACE LOCK=NONE"
            ]
        },
        {
            "title": "Remove redundant indexes",
            "description": "Below is a list of indexes that can be removed because they overlap with other existing ones.",
            "type": "SCHEMA",
            "level": "SERVER",
            "duplicate_keys": [
                {
                    "db_name": "airportdb",
                    "table_name": "booking",
                    "keys_to_remove": [
                        {
                            "redundant_key": "flight_idx",
                            "redundant_key_cols": [
                                "flight_id"
                            ],
                            "key_that_duplicates": "seatplan_unq",
                            "key_that_duplicates_cols": [
                                "flight_id",
                                "seat"
                            ],
                            "reason": "flight_idx is a left-prefix of seatplan_unq",
                            "drop_stmt": "ALTER TABLE airportdb.booking DROP INDEX flight_idx, ALGORITHM=INPLACE, LOCK=NONE"
                        }
                    ]
                }
            ]
        }
    ]
}


```

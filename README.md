# twcollector
Python module to submit optimization jobs to tuningwizard.query-optimization.com


## Quick start

### 1. Download the files in this repo

### 2. Install the required modules

```bash
$ python -m pip install -r requirements.txt
```


### 3. Create an account and retrieve your token

#### 3.a Using Python
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

# Delete object
del myjob
```

## Sample output
```json
{
    "costly_operations": [
        "4932 rows were read from table `flight`. Column `departure` from index `departure_idx` was used, although the range of values specified is too broad",
        "The Join between `booking` and `flight` produced 513185 rows. Approximately 104 rows were retrieved from `booking` for each of the 4934 rows obtained from `flight`",
        "The Join between `passenger` and `booking` produced 513185 rows. Approximately 1 rows were retrieved from `passenger` for each of the 513185 rows obtained from `booking`"
    ],
    "recommendations": [
        {
            "description": "The query is using index `departure_idx` for table `flight`, but the range of values requested is too broad. A workaround is to reduce or split the range of values for column `departure` and implement 'pagination', which involves retrieving the total range of values in smaller chunks",
            "type": "QUERY_REWRITE",
            "relevance": "medium"
        },
        {
            "description": "For table `booking`, consider including additional conditions, even if they are not indexed. This will help reducing the amount of rows generated by the Join.",
            "type": "QUERY_REWRITE",
            "relevance": "low"
        },
        {
            "description": "The LIMIT clause can be used in cases where long Joins are generated but either only a fixed amount of rows is required or where the whole result set is too long to consume",
            "type": "QUERY_REWRITE",
            "relevance": "low"
        }
    ]
}

```

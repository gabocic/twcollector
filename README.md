# twcollector
Python module to submit optimization jobs to tuningwizard.query-optimization.com


## Using the module for a single query

### 1. Edit params.json and configure the database connection parameters and API token

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

### 2. Install dependencies

```bash
$ python -m pip install -r requirements.txt
```


### 3. Use the module as follows and profit

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

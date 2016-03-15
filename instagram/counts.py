import itertools
from pymongo import MongoClient

client = MongoClient()
matches = client.DeepDress.Matches

probs = [i['prediction']['styleNames'][0]['probability'] for i in matches.find()]

rounded = [round(round(i, -1)) for i in probs]

for key, rows in itertools.groupby(sorted(rounded)):
    print(key, sum(1 for r in rows))

print("total", len(rounded))

#0.0 31
#10.0 184
#20.0 189
#30.0 145
#40.0 89
#50.0 96
#60.0 78
#70.0 66
#80.0 42
#90.0 73
#100.0 145

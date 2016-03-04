import urllib.request
import json
from pymongo import MongoClient
import time

DEEP_DRESS_WGET = 'http://deepnets.nyc/wget/?url='
DEEP_DRESS_PREDICT = 'http://deepnets.nyc/predict/'

def wget_deep_dress(url):
	serviceurl = DEEP_DRESS_WGET + url
	response = urllib.request.urlopen(serviceurl)
	f = response.read()
	j = json.loads(f.decode('utf-8'))
	return(j['file_id'])

def predict_deep_dress(file_id, top_n):
	serviceurl = DEEP_DRESS_PREDICT + '?file_id=' + file_id + '&top_n=' + top_n
	response = urllib.request.urlopen(serviceurl)
	f = response.read()
	j = json.loads(f.decode('utf-8'))
	return(j)


client = MongoClient()
db = client.DeepDress
instagram = db.Instagram
matches = db.Matches
# already tagged
ids = set([m['_id'] for m in matches.find()])

for i in instagram.find():
	try:
		if (i['_id'] not in ids):
			#file_id = wget_deep_dress(i['payload']['images']['low_resolution']['url'])
			file_id = wget_deep_dress(i['image'])
			preds = predict_deep_dress(file_id, '3')
			result = matches.insert({'_id' : i['_id'], 'prediction' : preds})
			time.sleep(1)
	except:
		print("failed on ", i)



import itertools
from pymongo import MongoClient
import json

client = MongoClient()
fromCollection = client.DeepDress.InstagramV3
toCollection = client.DeepDress.InstagramSimpleV3

#result = client.DeepDress.Instagram.insert_many([{'_id' : i['caption']['id'], 'payload': payload.encode('utf-8'), 'image': i['images']['low_resolution']['url']} for i in j['data'] if i['caption'] is not None])

for i in fromCollection.find():
	toCollection.insert({'_id' : i['_id'], 'content' : json.loads((i['payload']).decode('utf-8'))['data'], 'image' : i['image']})


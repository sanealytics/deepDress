import urllib.request
import json
from pymongo import MongoClient
import time


def fetchAndStash(url, client):
	try:
		response = urllib.request.urlopen(url + '&count=100')
		f = response.read()
		payload = f.decode('utf-8')
		j = json.loads(payload)

		if j['meta']['code'] == 200 :
			for i in j['data']:
				try:
					result = client.DeepDress.InstagramV4.insert({'_id' : i['link'], 'payload' : i, 'image' : i['images']['low_resolution']['url']}) 
				except:
					print("bad batch url: " + url + '; tried to insert ' + i)
					with open('error', 'a') as of:
						of.write(f.decode('utf-8'))

			time.sleep(1)
			fetchAndStash(j['pagination']['next_url'], client)

		else : 
			print(url)
	except:
		print("Failed url ", url)


client = MongoClient()
url = 'https://api.instagram.com/v1/tags/renttherunway/media/recent/?client_id=a9f303e9d3244d5e8a67b5a4f025ec41'
fetchAndStash(url, client) # could hit stack overflow.. but gonna be cray cray yeah


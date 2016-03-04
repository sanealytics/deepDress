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
			try: 
				result = client.DeepDress.Instagram.insert_many([{'_id' : i['caption']['id'], 'payload': payload.encode('utf-8'), 'image': i['images']['low_resolution']['url']} for i in j['data'] if i['caption'] is not None])
			except:
				print("bad batch url: " + url)
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


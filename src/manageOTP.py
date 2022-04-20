#!/usr/bin/python

import sys
import os
import json
import datetime
import time
import urllib
import urllib.request
import psycopg2

''' A part of this code comes from the OpenTripPlanner Plugin :
	You'll find the repository here : https://github.com/mkoenigb/OpenTripPlannerPlugin '''
#TODO permettre un port different

def getCoordinate(response) :
	res = []
	for coordinate in response :
		for i in coordinate :
			res.append(i[6:-1])
	return res

def setParameters(parameters) :
	''' create paramaters which be inserted into the API call
		May introduce default paramters if not specified by the user '''
	if len(parameters) == 0 :
		tempo_parameters = []
	else :	
		tempo_parameters = parameters.split(' ')
	res = {}
	for i in range (0,len(tempo_parameters)) :
		res[tempo_parameters[i].split('=')[0]]=tempo_parameters[i].split('=')[1]
	if 'date' not in res :
		res['date']= str(datetime.date.today())
	if 'time' not in res :
		now = datetime.datetime.now()
		res['time'] = now.strftime("%H:%M:%S")
	if 'mode' not in res:
		res['mode']='WALK,TRANSIT'
	if 'numItineraries' not in res :
		res['numItineraries'] = '2'
	return res

def matchNodes() :
	sql = "SELECT s.id, t.id from optstart s, opttarget t where s.id = t.ein;"
	cur.execute(sql)
	response = cur.fetchall()
	return response
	

# Source: https://stackoverflow.com/a/33557535/8947209 (slightly modified)
def decode_polyline(polyline_str):
	index, lat, lng = 0, 0, 0
	#coordinates = []
	pointlist = []
	changes = {'latitude': 0, 'longitude': 0}
	    
	# Coordinates have variable length when encoded, so just keep
	# track of whether we've hit the end of the string. In each
	# while loop iteration, a single coordinate is decoded.
	while index < len(polyline_str):
		# Gather lat/lon changes, store them in a dictionary to apply them later
		for unit in ['latitude', 'longitude']: 
			shift, result = 0, 0
			while True:
				byte = ord(polyline_str[index]) - 63
				index+=1
				result |= (byte & 0x1f) << shift
				shift += 5
				if not byte >= 0x20:
					break
				
			if (result & 1):
				changes[unit] = ~(result >> 1)
			else:
				changes[unit] = (result >> 1)

		lat += changes['latitude']
		lng += changes['longitude']
		
		qgspointgeom = (float(lng / 100000.0),float(lat / 100000.0))
		pointlist.append(qgspointgeom)
	return pointlist


conn = psycopg2.connect("host="+str(sys.argv[1])+" dbname="+str(sys.argv[2])+" user="+str(sys.argv[3])+" password="+sys.argv[4])
cur = conn.cursor()

match_item = matchNodes()
sql = "DROP TABLE IF EXISTS ROUTES;"
cur.execute(sql)
sql = "CREATE TABLE ROUTES (route_legid int,route_routeid int,route_from_starttime timestamp, route_leg_starttime timestamp, route_leg_distance double precision, route_leg_endtime timestamp, route_leg_from_lat double precision, route_leg_from_lon double precision, source_id bigint, target_id bigint,route_leg_mode text, geom geometry);"
cur.execute(sql)

route_routeid = 0
route_legid = 0
parameters = input("please enter the desired parameters ( key=value ) : ")
d_parameters = setParameters(parameters)
cnt = 0

for source, target in match_item :
	source_id = source
	cur.execute('SELECT st_astext(the_geom) from optstart where id='+str(source)+';')
	response = cur.fetchall()
	coordinate_start = getCoordinate(response)
	target_id = target
	cur.execute('SELECT st_astext(the_geom) from opttarget where id='+str(target)+';')
	response = cur.fetchall()
	coordinate_target = getCoordinate(response)
	
	coordinate_start=coordinate_start[0].split(' ')
	coordinate_target=coordinate_target[0].split(' ')
	route_url = 'http://localhost:8080/otp/routers/default/plan?fromPlace='+coordinate_start[1]+','+coordinate_start[0]+'&toPlace='+coordinate_target[1]+','+coordinate_target[0]
	for key in d_parameters :
		route_url = route_url +'&'+key+'='+d_parameters[key]
	
	route_headers = {"accept":"application/json"}
	route_request = urllib.request.Request(route_url, headers=route_headers)
	route_response = urllib.request.urlopen(route_request)
	response_data = route_response.read()
	encoding = route_response.info().get_content_charset('utf-8')
	route_data = json.loads(response_data.decode(encoding))
	
	route_from_lat = route_data['plan']['from']['lat']
	route_from_lon = route_data['plan']['from']['lon']
	
	try :
		route_from_name = route_data['plan']['from']['name']
	except :
		route_from_name = None # not available
		continue
	
	try :
		route_errormessage = route_data['error']['message']
		if route_errormessage == 'LOCATION_NOT_ACCESSIBLE' :
			cur.execute('DELETE from optstart where id='+str(source)+';')
			cur.execute('DELETE from opttarget where id='+str(target)+';')
			cnt +=1
			continue
	except :
		pass
	route_to_lat = route_data['plan']['to']['lat']
	route_to_lon = route_data['plan']['to']['lon']
	for iter in route_data['plan']['itineraries']:
		route_routeid += 1
		route_from_starttime = iter['startTime']
		route_to_endtime = iter['endTime']
		route_total_duration = iter['duration']
		route_total_transittime = iter['transitTime']
		route_total_waitingtime = iter['waitingTime']
		route_total_walktime = iter['walkTime']
		route_total_walkdistance = iter['walkDistance']
		route_total_transfers = iter['transfers']
		route_leg_totaldistcounter = 0
		
		
		for leg in iter['legs']:
			route_legid += 1
			route_leg_starttime = leg['startTime']
			route_leg_departuredelay = leg['departureDelay']
			route_leg_endtime = leg['endTime']
			route_leg_arrivaldelay = leg['arrivalDelay']
			route_leg_duration = leg['duration']
			route_leg_distance = leg['distance']
			route_leg_mode = leg['mode']
			route_leg_from_lat = leg['from']['lat']
			route_leg_from_lon = leg['from']['lon']
			route_leg_from_name = leg['from']['name']
			route_leg_from_departure = leg['from']['departure']
			route_leg_to_lat = leg['to']['lat']
			route_leg_to_lon = leg['to']['lon']
			route_leg_to_name = leg['to']['name']
			route_leg_to_arrival = leg['to']['arrival']
			route_leg_encodedpolylinestring = leg['legGeometry']['points']
			route_leg_decodedpolylinestring_aspointlist = decode_polyline(route_leg_encodedpolylinestring)
			
			sql1 = "ST_Setsrid(ST_Makeline(ARRAY["
			for coordinate in route_leg_decodedpolylinestring_aspointlist :
				sql1 = sql1 + "ST_Point("+str(coordinate[0])+","+str(coordinate[1])+"),"
			sql1 = sql1[:-1]
			sql1 = sql1 +']),4326)'
			
			
			sql = "INSERT INTO ROUTES VALUES("+str(route_legid)+","+str(route_routeid)+",TIMESTAMP '"+str(datetime.datetime.fromtimestamp(route_from_starttime/1000))+"',TIMESTAMP '"+str(datetime.datetime.fromtimestamp(route_leg_starttime/1000))+"',"+str(route_leg_distance)+",TIMESTAMP '"+str(datetime.datetime.fromtimestamp(route_leg_endtime/1000))+"',"+str(route_leg_from_lat)+","+str(route_leg_from_lon)+","+str(source_id)+","+str(target_id)+", '"+route_leg_mode+"',"+str(sql1)+");"
			cur.execute(sql)

conn.commit()
conn.close()

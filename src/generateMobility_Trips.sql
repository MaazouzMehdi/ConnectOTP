
DROP TYPE IF EXISTS step CASCADE;
CREATE TYPE step as (geom geometry,route_leg_from_lat double precision, route_leg_from_lon double precision,route_leg_starttime timestamp,route_leg_endtime timestamp,route_leg_distance float,route_leg_mode text);


DROP FUNCTION IF EXISTS wait;
CREATE OR REPLACE FUNCTION wait(starttime timestamptz, endtime timestamptz, trip geometry)
RETURNS tgeompoint AS $$
DECLARE
	p1 geometry;
	curtime timestamptz;
	instants tgeompoint[];
	l int;
BEGIN
	
	p1 = ST_PointN(trip, -1);
	curtime = starttime;
	endtime = endtime - 1000 * interval '1 ms';
	l=1;
	WHILE (curtime < endtime) LOOP
		curtime = curtime + 100 * interval '1 ms';
		instants[l] = tgeompoint_inst(p1, curtime);
		l = l + 1;
	END LOOP;

	RETURN tgeompoint_seq(instants, true, true, true);
END;
$$ LANGUAGE plpgsql STRICT;

DROP FUNCTION IF EXISTS generateTrip;
CREATE OR REPLACE FUNCTION generateTrip(trip step[])
RETURNS tgeompoint AS $$
DECLARE
	srid int;
	instants tgeompoint[];
	curtime timestamptz;
	departureTime timestamptz;
	linestring geometry;
	latitude_from double precision;
	longitude_from double precision;
	p1 geometry;
	p2 geometry;
	points geometry [];
	noEdges int;
	noSegs int;
	speed float; x1 float; x2 float;y1 float; y2 float;
	curDist double precision;traveltime double precision;
	l int;
	notrips int;
BEGIN
	
	p1 = ST_PointN((trip[1]).geom, 1);
	curtime = (trip[1]).route_leg_starttime;
	instants[1] = tgeompoint_inst(p1, curtime);
	l=2;
	noEdges = array_length(trip, 1);
	FOR i IN 1..noEdges LOOP
		linestring = (trip[i]).geom;
		SELECT array_agg(geom ORDER BY path) INTO points FROM ST_DumpPoints(linestring);
		
		noSegs = array_length(points, 1) - 1;
		speed = (trip[i]).route_leg_distance / (EXTRACT(EPOCH from (trip[i]).route_leg_endtime-(trip[i]).route_leg_starttime) + 0.1);
		
		FOR j IN 1..noSegs LOOP
			p2 = ST_setSRID(points[j + 1],4326);
			x2 = ST_X(p2);
			y2 = ST_Y(p2);
			
			curDist = ST_Distance(p1::geography,p2::geography);
			IF curDist = 0 THEN
				curDist = 0.1;
			END IF;
				
			travelTime = (curDist / speed);
			curtime = curtime + travelTime * interval '1 second';
			
			p1 = p2;
			x1 = x2;
			y1 = y2;
				
			instants[l] = tgeompoint_inst(p1, curtime);
			l = l + 1;
		END LOOP;
	END LOOP;	
	RETURN tgeompoint_seq(instants, true, true, true);
END;
$$ LANGUAGE plpgsql STRICT;


DROP FUNCTION IF EXISTS createTrips;
CREATE OR REPLACE FUNCTION createTrips(itineraries bool)
RETURNS void AS $$
DECLARE
	trip tgeompoint;
	notrips int;
	id int;
	d date;
	tmode text;
	actual_source int;
	next_source int;
	maxleg int;
	nolegs int;
	baseleg int;
	nodeSource bigint;
	nodeTarget bigint;
	leg_starttime timestamptz;
	leg_endtime timestamptz;
	leg_geom geometry;
	changed_itinerary bool;
	path step[];
BEGIN
	id = 1;
	DROP TABLE IF EXISTS MobilityTrips CASCADE;
	CREATE TABLE MobilityTrips(id int, routeid int, day date, source bigint,
		target bigint, transport_mode text, trip tgeompoint, trajectory geometry,
		PRIMARY KEY (id));
	
	select max(route_routeid) from routes into notrips;
	select max(route_legid) from routes into maxleg;
	
	For actualtrip in 1..notrips LOOP
		
		
		IF itineraries != true THEN
			-- Verification in order to delete first itinary composed only of walk 
			select source_id from routes into actual_source where actualtrip=route_routeid;
			IF actualtrip != notrips THEN
				select source_id from routes into next_source where actualtrip+1=route_routeid;
				continue when actual_source=next_source;
			END IF;
		END IF;
			
		select min(route_legid) from routes into baseleg where route_routeid=actualtrip;
		changed_itinerary = true;
		select count(route_routeid) from routes where route_routeid=actualtrip into nolegs;
		
		For j in 0..nolegs-1 LOOP
			IF baseleg+j != 1 and baseleg+j != maxleg and changed_itinerary != true THEN
				select route_leg_starttime from routes into leg_starttime where baseleg+j = route_legid;
				select route_leg_endtime from routes into leg_endtime where baseleg+j-1 = route_legid;
				select geom from routes into leg_geom where baseleg+j-1 = route_legid;
				
				select source_id from routes into nodeSource where baseleg+j = route_legid;
				select target_id from routes into nodeTarget where baseleg+j = route_legid;
				
				-- We check if the user has to wait for a transfer
				If leg_starttime != leg_endtime THEN
					trip = wait(leg_endtime,leg_starttime,leg_geom);
					INSERT INTO MobilityTrips VALUES (id, actualtrip, d, nodeSource, nodeTarget, 'WAIT', trip, trajectory(trip));
					id = id+1;
				END IF;
			END IF;
			
			changed_itinerary = false;
			SELECT array_agg((geom,route_leg_from_lat,    
				route_leg_from_lon,route_leg_starttime,route_leg_endtime,route_leg_distance,route_leg_mode)::step) 
				INTO path FROM routes where baseleg+j = route_legid;
		
			select route_from_starttime from routes into d where baseleg+j = route_legid;
			select source_id from routes into nodeSource where baseleg+j = route_legid;
			select target_id from routes into nodeTarget where baseleg+j = route_legid;
			select route_leg_mode from routes into tmode where baseleg+j = route_legid;
			
			trip = generatetrip(path);
			INSERT INTO MobilityTrips VALUES (id, actualtrip,d, nodeSource, nodeTarget, tmode, trip, trajectory(trip));
			id = id+1;
		END LOOP;
	END LOOP;
	RETURN;
END;
$$ LANGUAGE plpgsql STRICT;

COMMIT;

SELECT createTrips(:itineraries);
--RAISE INFO 'Advanced display enabled on QGis';

DROP TABLE if EXISTS public_transport_trip CASCADE;
create table public_transport_trip as select * from mobilitytrips where transport_mode not in ('WALK','WAIT','BICYCLE','CAR');

DROP table if EXISTS walk_trip CASCADE;
create table walk_trip as select * from mobilitytrips where transport_mode='WALK'; 

DROP TABLE if EXISTS wait_trip CASCADE;
 create table wait_trip as select * from mobilitytrips where transport_mode='WAIT';

DROP TABLE if EXISTS bike_trip CASCADE;
 create table bike_trip as select * from mobilitytrips where transport_mode='BICYCLE';
 
DROP TABLE if EXISTS car_trip CASCADE;
 create table car_trip as select * from mobilitytrips where transport_mode='CAR';



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
CREATE OR REPLACE FUNCTION createTrips(itineraries bool,ncores int)
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
				select source_id from routes into next_source where actualtrip+ncores=route_routeid;
				continue when actual_source=next_source;
			END IF;
		END IF;
			
		select min(route_legid) from routes into baseleg where route_routeid=actualtrip;
		changed_itinerary = true;
		select count(route_routeid) from routes where route_routeid=actualtrip into nolegs;
		
		For j in 0..nolegs-1 by ncores LOOP
			IF baseleg+j != 1 and baseleg+j != maxleg and changed_itinerary != true THEN
				select route_leg_starttime from routes into leg_starttime where baseleg+j = route_legid;
				select route_leg_endtime from routes into leg_endtime where baseleg+j-ncores = route_legid;
				select geom from routes into leg_geom where baseleg+j-ncores = route_legid;
				
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

SELECT createTrips(:itineraries, :ncores);
--RAISE INFO 'Advanced display enabled on QGis';

DROP TABLE if EXISTS stibtrip CASCADE;
create table stibtrip as select * from mobilitytrips where transport_mode not in ('WALK','WAIT');

DROP table if EXISTS walktrip CASCADE;
create table walktrip as select * from mobilitytrips where transport_mode='WALK'; 

DROP TABLE if EXISTS waittrip CASCADE;
 create table waittrip as select * from mobilitytrips where transport_mode='WAIT';



--SELECT openTrip();

--drop table IF EXISTS affichage;
--create table affichage as select gid, the_geom from streetnetwork where gid in ( select edge from pgr_dijkstra('SELECT gid as id, source, target, length_m AS cost, length_m * sign(reverse_cost_s) as reverse_cost FROM streetnetwork',116,123));

-- Creates a trip following a path between a source and a target node starting
-- at a timestamp t. Implements Algorithm 1 in BerlinMOD Technical Report.
-- The last argument corresponds to the parameter P_DISTURB_DATA.

/*
DROP FUNCTION IF EXISTS createTrip;
CREATE OR REPLACE FUNCTION createTrip(edges step[], startTime timestamptz)
RETURNS tgeompoint AS $$
DECLARE
	---------------
	-- Variables --
	---------------
	-- SRID of the geometries being manipulated
	srid int;
	-- Number of edges in a path, number of segments in an edge,
	-- number of fractions of size P_EVENT_LENGTH in a segment
	noEdges int; noSegs int; noFracs int;
	-- Loop variables
	i int; j int; k int;
	-- Number of instants generated so far
	l int;
	-- Categories of the current and next road
	category text; nextCategory int;
	-- Current speed and distance of the moving car
	curSpeed float; curDist float;
	-- Time to wait and total wait time
	waitTime float; totalWaitTime float = 0.0;
	-- Time to travel the fraction given the current speed and total travel time
	travelTime float; totalTravelTime float = 0.0;
	-- Angle between the current segment and the next one
	alpha float;
	-- Maximum speed of an edge
	maxSpeedEdge float;
	-- Maximum speed of a turn between two segments as determined
	-- by their angle
	maxSpeedTurn float;
	-- Maximum speed and new speed of the car
	maxSpeed float; newSpeed float;
	-- Coordinates of the next point
	x float; y float;
	-- Coordinates of p1 and p2
	x1 float; y1 float; x2 float; y2 float; xtemp float; ytemp float;
	-- Number in [0,1] used for determining the next point
	fraction float;
	-- Disturbance of the coordinates of a point and total accumulated
	-- error in the coordinates of an edge. Used when disturbing the position
	-- of an object to simulate GPS errors
	dx float; dy float;
	errx float = 0.0; erry float = 0.0;
	-- Length of a segment and maximum speed of an edge
	segLength float;
	-- Geometries of the current edge
	linestring geometry;
	-- Points of the current linestring
	points geometry [];
	pointsWait geometry [];
	
	StibPosition tgeompoint [];
	noEdgesStib int;
	
	
	-- Start and end points of segment of a linestring
	p1 geometry; p2 geometry;
	-- Next point (if any) after p2 in the same edge
	ptemp geometry;
	
	stop1 geometry;
	stop2 geometry;
	
	route Text;
	routeAffichage Text;
	tripp Text;
	ad Text;
	aa Text;
	
	
	depart timestamptz;
	wait boolean;
	arrival timestamptz;
	-- Current position of the moving object
	curPos geometry;
	-- Current timestamp of the moving object
	curtime timestamptz;
	-- Instants of the result being constructed
	instants tgeompoint[];
	-- Statistics about the trip
	noAccel int = 0;
	noDecel int = 0;
	noStop int = 0;
	twSumSpeed float = 0.0;
BEGIN
	srid = ST_SRID((edges[1]).linestring);
	p1 = ST_PointN((edges[1]).linestring, 1);
	--p1 = ST_SetSRID(p1,srid);
	x1 = ST_X(p1);
	y1 = ST_Y(p1);
	curPos = p1;
	curtime = startTime;
	curSpeed = 1.29;
	wait = false;
	instants[1] = tgeompoint_inst(p1, curtime);
	l = 2;
	noEdges = array_length(edges, 1);
	
	-- Loop for every edge
	FOR i IN 1..noEdges LOOP
		-- Get the information about the current edge
		linestring = (edges[i]).linestring;
		maxSpeedEdge = (edges[i]).maxSpeed;
		category = (edges[i]).category;
		--RAISE INFO 'Category %', category;
		IF category != 'FOOT' THEN
			select ST_PointN(linestring, 1) into stop1;
			select ST_PointN(linestring, -1) into stop2;
			
			select route_id from trip_segs where seg_geom = linestring limit 1 into routeAffichage;
			select route_short_name from gtfs.routes where route_id in ( select route_id from trip_segs where seg_geom = linestring limit 1 ) into routeAffichage;
			
			
			select route_id from trip_segs where seg_geom = linestring limit 1 into route;
			RAISE INFO 'Ligne %', routeAffichage;
			
			drop table if exists input;
			drop table if exists temp1;
			drop table if exists temp2;
			create table Temp1 AS select * from trips_input_oneday tr where tr.route_id=route and tr.point_geom = stop1 and tr.t >= curtime ORDER BY tr.t ASC limit 1;
			
			create table Temp2 AS select * from trips_input_oneday tr where (tr.trip_id,tr.route_id,tr.service_id) in ( select temp.trip_id,temp.route_id,temp.service_id from temp1 temp) AND tr.point_geom = stop2 and tr.t >= curtime ORDER BY tr.t ASC limit 1 ;
			
			create table input as select tr.trip_id ,tr.route_id,tr.service_id,tr.date,tr.point_geom,tr.t from trips_input_oneday tr ,Temp1 t1,Temp2 t2 where t1.trip_id = tr.trip_id and tr.route_id = route and t1.service_id = tr.service_id and tr.t >= t1.t and tr.t <= t2.t;
			
			Select trip_id from input limit 1 INTO tripp;
			Select t from input ORDER BY T DESC limit 1 INTO arrival;
			Select t from input ORDER BY T ASC limit 1 INTO depart;
			
			RAISE INFO 'Trip %', tripp;
			RAISE INFO 'Heure actuelle avant depart %', curtime;
			RAISE INFO 'Heure de depart %', depart;
			RAISE INFO 'Heure d arriver %', arrival;
			IF depart is NULL THEN
				p1 = stop2;
			
			ELSE
				WHILE (curtime < depart ) LOOP
					curtime = curtime + 100 * interval '1 ms';
				--curspeed = 0;
				END LOOP;
				--RAISE INFO 'Heure actuelle %', curtime;
			
				SELECT array_agg(tgeompoint_inst(point_geom, t) ORDER BY T) INTO StibPosition
				FROM input;
			
				noEdgesStib = array_length(StibPosition, 1);
				FOR i IN 2..noEdgesStib LOOP
					instants[l] = StibPosition[i];
					l = l + 1;
				END LOOP;
				
				Select t from input ORDER BY T DESC limit 1 INTO curtime;
				Select point_geom from input ORDER BY T DESC limit 1 INTO p1;
				x1 = ST_X(p1);
				y1 = ST_Y(p1);
			END IF;
		
		ELSE
			RAISE INFO 'Category %', category;
			drop table if exists segment;
			create table segment (point geometry);
			SELECT array_agg(geom ORDER BY path) INTO points
			FROM ST_DumpPoints(linestring);
			noSegs = array_length(points, 1) - 1;
			insert into segment values (points[1]);
			FOR j IN 1..noSegs LOOP
				insert into segment values (points[j + 1]);
				p2 = points[j + 1];
				x2 = ST_X(p2);
				y2 = ST_Y(p2);
				
				curDist = ST_Distance(p1::geography,p2::geography);
				
				travelTime = (curDist / curSpeed);
				curtime = curtime + travelTime * interval '1 sec';

				p1 = p2;
				x1 = x2;
				y1 = y2;
				
				instants[l] = tgeompoint_inst(p1, curtime);
				insert into text values (instants[l]);
				l = l + 1;			
			
			END LOOP;
		END IF;
	END LOOP;
	
	Raise INFO 'Heure d Arrive Finale %',curtime;
	RETURN tgeompoint_seq(instants, true, true, true);
END;
$$ LANGUAGE plpgsql STRICT;
*/
/*DROP TABLE IF EXISTS gtfs.affichage;
create table gtfs.affichage as select id, the_geom from tentative where id in ( select edge from pgr_dijkstra('SELECT id, source, target, cost, reverse_cost FROM tentative', 37631, 17210));
DROP table IF EXISTS gtfs.tdijkstra CASCADE;
create table gtfs.tdijkstra as SELECT createTrip(createPath(37631, 17210), '2022-01-18 08:00:00');



DROP TABLE IF EXISTS gtfs.affichage2;
create table gtfs.affichage2 as select id, the_geom from tentative where id in ( select edge from pgr_dijkstra('SELECT id, source, target, cost, reverse_cost FROM tentative', 37631, 21917));
DROP table IF EXISTS gtfs.tdijkstra2 CASCADE;
create table gtfs.tdijkstra2 as SELECT createTrip(createPath(37631, 21917), '2022-01-18 08:00:00');

DROP TABLE IF EXISTS gtfs.affichage3;
create table gtfs.affichage3 as select id, the_geom from tentative where id in ( select edge from pgr_dijkstra('SELECT id, source, target, cost, reverse_cost FROM tentative', 37631, 94057));
DROP table IF EXISTS gtfs.tdijkstra3 CASCADE;
create table gtfs.tdijkstra3 as SELECT createTrip(createPath(37631, 94057), '2022-01-18 08:00:00');
*/


/*
WITH Temp(trip) AS (
	SELECT createTrip(createPath(116, 123), '2019-11-02 08:00:00')
)
SELECT startTimestamp(trip), endTimestamp(trip), timespan(trip)
FROM Temp;
*/

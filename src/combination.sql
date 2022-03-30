
DROP FUNCTION IF EXISTS generateCombinations;
CREATE OR REPLACE FUNCTION generateCombinations(noCombinations int)
RETURNS void AS $$
DECLARE
	noVertices int;
	startVertice int;
	targetVertice int;
	allstartVertices int[];
	alltargetVertices int[];
	
BEGIN
	DROP TABLE IF EXISTS optstart;
	DROP TABLE IF EXISTS opttarget;
	CREATE TABLE optstart (id int,cnt int,chk int,ein int,eout int,the_geom geometry);
	CREATE TABLE opttarget (id int,cnt int,chk int,ein int,eout int,the_geom geometry);
	
		
	select count(*) from ways_vertices_pgr into noVertices;
	FOR i in 1..noCombinations LOOP
		 select ceiling(random()*noVertices) into startVertice;
		 INSERT INTO optstart ( select id,cnt,chk,ein,eout,the_geom from ways_vertices_pgr where id = startVertice );

		 select ceiling(random()*noVertices) into targetVertice;
		 INSERT INTO opttarget ( select id,cnt,chk,ein,eout,the_geom from ways_vertices_pgr where id = targetVertice );
		 
		 UPDATE opttarget set ein = startVertice where id = targetVertice;
	END LOOP;
	RETURN;
END;
$$ LANGUAGE plpgsql STRICT;

Select generateCombinations(:o);

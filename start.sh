sed  -i '16s/NUMERIC(5,8);/NUMERIC(5,0);/g' ./routes.sql
sed  -i '17s/NUMERIC(5,8);/NUMERIC(5,0);/g' ./routes.sql
sed  -i '22s/NUMERIC(5,8);/NUMERIC(5,0);/g' ./routes.sql
sed  -i '23s/NUMERIC(5,8);/NUMERIC(5,0);/g' ./routes.sql
sed  -i '43s/NUMERIC(5,8);/NUMERIC(5,0);/g' ./routes.sql
sed  -i '44s/NUMERIC(5,8);/NUMERIC(5,0);/g' ./routes.sql
sed  -i '49s/NUMERIC(5,8);/NUMERIC(5,0);/g' ./routes.sql
sed  -i '50s/NUMERIC(5,8);/NUMERIC(5,0);/g' ./routes.sql
psql -h localhost -U postgres -d stib -f /home/mehdi/Bureau/masterFIN/Thesis/Code/routes.sql
psql -h localhost -U postgres -d stib -f /home/mehdi/Bureau/masterFIN/Thesis/Code/generateMobility_Trips.sql


#!/bin/sh
#
# script to download, import, and plot earthquakes from the last week.
#
# (c) 2010 Hamish Bowman, and the GRASS Development Team
# Based on earlier version by Markus Neteler, which in turn was based on
#  comments from Sharyn Namnath and Glynn Clements.
#
# This script is licensed under the GPL >=2. See GPL.TXT which comes with
#  the GRASS source code for details.
#
# World DTM picture is from the ETOPO1 dataset,
#   http://www.ngdc.noaa.gov/mgg/global/global.html
# Nice colors were done in GMT by J. Varner and E. Lim, CIRES, University
#  of Colorado at Boulder.
#
# Earthquake data is downloaded from the USGS
#  http://neic.usgs.gov/neis/gis/bulletin.asc (defunct)
#  new1:  http://earthquake.usgs.gov/earthquakes/catalogs/eqs7day-M2.5.txt (defunct)
#  new2:  http://earthquake.usgs.gov/earthquakes/feed/csv/2.5/week (defunct)
#  new3:  https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_week.csv
#

if  [ -z "$GISBASE" ] ; then
    echo "You must be in GRASS GIS to run this program." >&2
    exit 1
fi


PROJ_SHORT_NAME=world_ll
WEB_DIR=/var/www/grass/earthquakes

#GRASS_PNGFILE=earthquakes.png
GRASS_PNGFILE=earthquakes.ppm
GRASS_WIDTH=900
GRASS_HEIGHT=450
GRASS_TRUECOLOR=TRUE
GRASS_PNG_COMPRESSION=9
GRASS_VERBOSE=0
export GRASS_WIDTH GRASS_HEIGHT GRASS_TRUECOLOR GRASS_PNG_COMPRESSION \
   GRASS_VERBOSE GRASS_PNGFILE

TMPDIR="/var/tmp/grass"
if [ ! -d "$TMPDIR" ] ; then
   mkdir -p "$TMPDIR"
fi
cd "$TMPDIR"


### download and import

wget -nv -O "eqs7day-M2.5.raw" \
   "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_week.csv" 2>&1

if [ $? -ne 0 ] ; then
   echo "Failed to download data from the USGS." >&2
   exit 1
fi

# just the basics
cut -d',' -f1-6 eqs7day-M2.5.raw > eqs7day-M2.5.csv
rm eqs7day-M2.5.raw

#convert commas+quoting to pipe delims:
csv_dequote.pl eqs7day-M2.5.csv

# add a '#' at the start of the first line and remove spurious whitespace
#  -e '1,/^/s//#/'
mv eqs7day-M2.5.psv eqs7day-M2.5.psv.in

sed -e '0,/^/s//#/' -e 's/^Date/#Date/' \
    -e 's+| \([0-9]\)|+|\1|+' \
  eqs7day-M2.5.psv.in > eqs7day-M2.5.psv

rm eqs7day-M2.5.psv.in


# eqs7day-M2.5.csv format:
#DateTime,Latitude,Longitude,Depth,Magnitude,MagType,NbStations,Gap,Distance,RMS,Source,EventID,Version
#https://earthquake.usgs.gov/earthquakes/feed/v1.0/csv.php

COL_DEF="eq_time varchar(50), latitude double precision, longitude double precision, \
   depth double precision, magnitude double precision, magn_type varchar(7)"

INPUT="$TMPDIR/eqs7day-M2.5.psv"

db.connect -c
DBDRIVER=`db.connect -p | grep '^driver:' | cut -f2 -d:`

if [ "$DBDRIVER" != 'sqlite' ] ; then
   # a bit slower, but we can use longer column names
   db.connect driver=sqlite database='$GISDBASE/$LOCATION_NAME/$MAPSET/sqlite.db'
fi

v.in.ascii in="$INPUT" out=recent_earthquakes skip=1 \
    fs='|' y=2 x=3 z=4 column="$COL_DEF" --overwrite


### unlog & scale magnitude

# http://earthquake.usgs.gov/learn/topics/measure.php
#    1 J = 1e7 erg
#    1 PJ = 1e15 J
#   Energy_petajoules = ( 10^(11.8 + 1.5*Ms) ) * 1e-07 * 1e-15
#
# rationale: keep within pixel equiv of 90deg lon from source pt so a
#            quake in the middle makes it onto the plot.
#   (8.8^10) * 1e-7 = 278.5     : very rough unlog scale
#

v.db.addcol recent_earthquakes column="magn_energy DOUBLE PRECISION"

# how to do POW(x,n) in SQLite?
#v.db.update recent_earthquakes column=magn_energy value="POW(magnitude,10) * 1e-7" --verbose

v.db.select -c recent_earthquakes column=cat,magnitude | awk -F'|' \
  '{printf("UPDATE recent_earthquakes SET magn_energy=%f WHERE cat=%d;\n", ($2^10)*1e-7, $1)}' \
  > "${PROJ_SHORT_NAME}_$$.sql"

db.execute input="${PROJ_SHORT_NAME}_$$.sql"
\rm "${PROJ_SHORT_NAME}_$$.sql"


# get the timestamp
YMD=`head -n 3 "$INPUT" | tail -n 1 | cut -f1 -d'T' | tr '-' '/'`
if [ `echo "$YMD" | wc -c` -lt 11 ] ; then
    echo "Bad timestamp ($YMD). Using system date instead." >&2
    YMD=`date +%Y/%m/%d`
fi


### draw

g.region n=90N s=90S w=25W e=25W res=0:24  # -p

d.mon start=PNG

d.rgb r=color_etopo1_ice_900.red@etopo1 g=color_etopo1_ice_900.green@etopo1 \
    b=color_etopo1_ice_900.blue@etopo1


# d.rast -o usgs_logo
# d.rast -o grass_logo

d.font Vera

#echo "
#.G 250:250:250
#.C red
#Shallow
#.C yellow
#Intermediate
#.C green
#Deep" | d.text at=99,99 size=3 align=ur


#quake3.png
#d.vect recent_earthquakes icon=extra/ring fcolor=none size_col=magn_energy \
#   size=5 wcol=magn_energy wscale=0.01 -z zcolor=ryg  
#
# size=5 * 0.1
# magn^3
# wscale=0.01

#quake5.png:
#d.vect recent_earthquakes icon=extra/ring fcolor=none size_col=magn_energy \
#   size=1 wcol=magn_energy wscale=0.0005 -z zcolor=ryg
#
# size=1 * 0.01
# magn^5
# wscale=0.0005


#quake10.png:
d.vect recent_earthquakes icon=extra/ring fcolor=none size_col=magn_energy \
   size=3 wcol=magn_energy wscale=0.2 -z zcolor=ryg 
#
# size=3
# (magn^10) * 1e-7
# wscale=0.1

#quake2.72.png:
# size=1
# magn^2.72
# wscale=0.01


echo "Earthquakes for the week ending $YMD" | \
   d.text at=1,2 color=60:60:60 size=3


sync
d.mon stop=PNG
sync

IMG=graphics/earthquakes_logo_overlay
#pngtopnm $IMG.png > $IMG.pnm
#pngtopnm -alpha $IMG.png > $IMG.pgm
pnmcomp -alpha $IMG.pgm $IMG.pnm earthquakes.ppm | \
   pnmtopng > earthquakes.png

if [ $? -ne 0 ] ; then
   echo "Failed to compose image." 1>&2
   exit 1
fi

pngtopnm earthquakes.png | pnmtojpeg -quality=85 > earthquakes.jpg
convert -geometry 75% -quality 85 earthquakes.png earthquakes_small.jpg
convert -geometry 40% -quality 85 earthquakes.png earthquakes_tiny.jpg

cp -f earthquakes.png earthquakes*.jpg "$WEBDIR/"

# Output KML file.
#TODO: make fancy with Peter Loewe's more advanced v.out.kml addon script
v.out.ogr in=recent_earthquakes dsn=recent_earthquakes.kml \
    format=KML type=point
zip -q recent_earthquakes.zip recent_earthquakes.kml
cp -f recent_earthquakes.zip "$WEB_DIR/recent_earthquakes_USGS.kmz"


### cleanup and closeup
g.remove vect=recent_earthquakes --quiet
rm -f "$TMPDIR/eqs7day-M2.5.psv"


# all done.
exit 0


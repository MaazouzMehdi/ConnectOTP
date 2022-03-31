#!/bin/bash 
if [ $1 == '-html' ]
then
	cd doc/
	if (xsltproc --stringparam html.stylesheet "docbook.css" --xinclude -o ./index.html /usr/share/xml/docbook/stylesheet/nwalsh/html/chunk.xsl connectotp-workshop.xml)
	cd ..
	then
		echo './doc/index.html generated'
	else
		echo 'Error : ./doc/index.html has not been generated'
	fi
elif [ $1 == '-pdf' ]
then
	if (dblatex -s ./doc/texstyle.sty -T native -t pdf -o ./doc/connect-workshop.pdf ./doc/connectotp-workshop.xml )
	then
		echo './doc/connect-workshop.pdf generated'
	else
		echo 'Error : ./doc/connect-workshop.pdh has not been generated'

	fi
else
echo ' wrong argument : please insert -html or -pdf to generate doc'
fi


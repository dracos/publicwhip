#! /usr/bin/python2.3

import sys
import re
import os
import string

import mx.DateTime

from miscfuncs import ApplyFixSubstitutions

# this filter converts column number tags of form:
#     <I>23 Oct 2003 : Column 637W</I>
# into xml form
#     <stamp coldate="2003-10-23" colnum="637W"/>

fixsubs = 	[
	( 'Continued in col 47W', '', 1, '2003-10-27' ),

	# Note the 2!
	( '<H1 align=center></H1>[\s\S]{10,99}?\[Continued from column \d+?W\](?:</H2>)?', '', 2, '2003-11-17' ),
	( '<H2 align=center> </H2>[\s\S]{10,99}?Monday 13 October 2003', '', 1, '2003-10-14' ),
 		]

# <I>23 Oct 2003 : Column 637W</I>
lcolumnregexp = '<i>\s*.*?\s*:\s*column:?\s*\d+w?\s*</i>(?i)'
columnregexp = '<i>\s*(.*?)\s*:\s*column:?\s*(\d+)w?\s*</i>(?i)'

#<i>23 Oct 2003 : Column 640W&#151;continued</i>
lcolumncontregexp = '<i>\s*.*?\s*:\s*column\s*\d+w?&#151;continued\s*</i>(?i)'
columncontregexp = '<i>\s*(.*?)\s*:\s*column\s*(\d+)w?&#151;continued\s*</i>(?i)'

combiregexp = '(%s|%s)' % (lcolumnregexp, lcolumncontregexp)


def FilterWransColnum(fout, text, sdate):
	text = ApplyFixSubstitutions(text, sdate, fixsubs)

	fs = re.split(combiregexp, text)

	colnum = -1

	for fss in fs:
		columng = re.match(columnregexp, fss)
		if columng:
			ldate = mx.DateTime.DateTimeFrom(columng.group(1)).date
			if sdate != ldate:
				raise Exception, "Column date disagrees %s -- %s" % (sdate, fss)

			lcolnum = string.atoi(columng.group(2))
			if (colnum == -1) or (lcolnum == colnum + 1):
				pass  # good
			elif lcolnum < colnum:
				raise Exception, "Colnum not incrementing %d -- %s" % (lcolnum, fss)
			# column numbers do get skipped during division listings

			colnum = lcolnum
			fout.write('<stamp coldate="%s" colnum="%sW"/>' % (sdate, lcolnum))

			continue

		columncontg = re.match(columncontregexp, fss)
		if columncontg:
			ldate = mx.DateTime.DateTimeFrom(columncontg.group(1)).date
			if sdate != ldate:
				raise Exception, ("Cont column date disagrees %s -- %s" % (sdate, fss))
			lcolnum = string.atoi(columncontg.group(2))
			if colnum != lcolnum:
				raise Exception, "Cont column number disagrees %d -- %s" % (colnum, fss)

			# no need to output result
		else:
			fout.write(fss)


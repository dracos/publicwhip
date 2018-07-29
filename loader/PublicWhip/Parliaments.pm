# $Id: Parliaments.pm,v 1.3 2005/10/05 17:21:41 frabcus Exp $
# List of parliaments we are covering.  This data is duplicated in
# website/parliaments.inc.

# The Public Whip, Copyright (C) 2003 Francis Irving and Julian Todd
# This is free software, and you are welcome to redistribute it under
# certain conditions.  However, it comes with ABSOLUTELY NO WARRANTY.
# For details see the file LICENSE.html in the top level of the source.

# XXX Does anything ever use this?

=doc
    my @parls = PublicWhip::Parliaments::getlist();
    foreach my $parl (@parls)
    {
        print $$parl{"id"}, $$parl{"from"}, $$parl{"to"};
    }
=cut

package PublicWhip::Parliaments;
use strict;

our @list = ( # put newer Parliaments first
    # keep in sync with website/parliaments.inc
    { id => '2017', from => '2017-06-08', to => '9999-12-31', name => '2017' },
    { id => '2015', from => '2015-05-06', to => '2017-06-08', name => '2015' },
    { id => '2010', from => '2010-05-06', to => '2015-03-15', name => '2010' },
    { id => '2005', from => '2005-05-05', to => '2010-04-12', name => '2005' },
    { id => '2001', from => '2001-06-07', to => '2005-04-11', name => '2001' },
    { id => '1997', from => '1997-05-01', to => '2001-05-14', name => '1997' },
    #{ id => '1992', from => '1992-04-09', to => '1997-05-01', name => '1992' },
    #{ id => '1987', from => '1987-06-11', to => '1992-04-09', name => '1987' },


);

sub getlist {
    return @list;
}

sub getcurrent {
	return ($list[0]);
}

1;

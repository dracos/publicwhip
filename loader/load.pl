#! /usr/bin/perl -w 
use strict;

# $Id: load.pl,v 1.1 2004/06/08 11:56:54 frabcus Exp $
# The script you actually run to do screen scraping from Hansard.  Run
# with no arguments for usage information.

# The Public Whip, Copyright (C) 2003 Francis Irving and Julian Todd
# This is free software, and you are welcome to redistribute it under
# certain conditions.  However, it comes with ABSOLUTELY NO WARRANTY.
# For details see the file LICENSE.html in the top level of the source.

use WWW::Mechanize;
use Getopt::Long;
use PublicWhip::Clean;
use PublicWhip::FindDays;
use PublicWhip::Content;
use PublicWhip::DivsXML;
use PublicWhip::Divisions;
use PublicWhip::Calc;
use PublicWhip::MPList;
use PublicWhip::DB;
use PublicWhip::Error;

my $from;
my $to;
my $date;
my $verbose;
my $chitter;
my $quiet;
my $force;
my $result = GetOptions(
    "from=s"  => \$from,
    "to=s"    => \$to,
    "date=s"  => \$date,
    "verbose" => \$verbose,
    "chitter" => \$chitter,
    "quiet"   => \$quiet,
    "force"   => \$force
);

if ($date) {
    die "Specify either specific date or date range, not both"
      if ( $from || $to );
    $from = $date;
    $to   = $date;
}
my $where_clause = "";
my @where_params;
$where_clause .= "and day_date >= ? " if defined $from;
push @where_params, $from if defined $from;
$where_clause .= "and day_date <= ? " if defined $to;
push @where_params, $to if defined $to;
$from = "1000-01-01" if not defined $from;
$to   = "9999-12-31" if not defined $to;

PublicWhip::Error::setverbosity( ERR_IMPORTANT + 1 ) if $quiet;
PublicWhip::Error::setverbosity(ERR_USEFUL)          if $verbose;
PublicWhip::Error::setverbosity(ERR_CHITTER)         if $chitter;

if ( $#ARGV < 0 || ( !$result ) ) {
    help();
    exit;
}

my $dbh = PublicWhip::DB::connect();

for (@ARGV) {
    clean();

    if    ( $_ eq "mps" )       { mps(); }
    elsif ( $_ eq "months" )    { crawl_recent_months(); }
    elsif ( $_ eq "sessions" )  { crawl_recent_sessions(); }
    elsif ( $_ eq "content" )   { all_content(); }
    elsif ( $_ eq "divsxml" )   { all_divsxml(); }
    elsif ( $_ eq "divisions" ) { all_divisions(); }
    elsif ( $_ eq "calc" )      { update_calc(); }
    elsif ( $_ eq "check" )     { check(); }
    elsif ( $_ eq "words" )     { word_count(); }
    elsif ( $_ eq "test" )      { test(); }
    else { help(); exit; }
}
exit;

sub help {
    print <<END;

Downloads divisions from Hansard via HTTP, and parses them into MP
voting records within a MySQL database.

scrape.pl [OPTION]... [COMMAND]...

Commands are any or all of these, in order you want them run:
mps - insert MPs into database from local raw data files
months - scan back through months to get new day URLs
sessions - scan recent sessions and find day URLs
content - fetch debate content for all days
divsxml - parse divisions from XML files and add them to database
divisions - DEPRECATED parse divisions from local content and add them to database
check - check database consistency
calc - update cached calculations, do this after every crawl

These options apply to "content" and "divisions" commands only:
--date=YYYY-MM-DD - date to apply to
--from=YYYY-MM-DD - process all from this date onwards
--to=YYYY-MM-DD - process all up to this date
(you can specify from and to for an inclusive date range)
--force - delete previous data, and refetch/recalculate

These are general options:
--quiet - say nothing, except for errors
--verbose - say more about what is going on
--chitter - display detailed debug logs

END

}

# Called every time to tidy up database
sub clean {
    print "Erasing half-parsed divisions...\n";
    PublicWhip::Clean::erase_duff_divisions($dbh);
}

sub mps {
    print "Inserting MPs...\n";
    PublicWhip::MPList::insert_mps($dbh);

    #    mplist::mid_transfer($dbh);
}

sub crawl_recent_months {

    # Test most recent month and sessions crawl
    my $agent     = WWW::Mechanize->new();
    my $start_url = "http://www.publications.parliament.uk/pa/cm/cmhansrd.htm";
    $agent->get($start_url)->is_success()
      or die "Failed to read URL $start_url";
    print "Scanning recent months...\n";
    PublicWhip::FindDays::recent_months( $dbh, $agent );

    # Add this on end of recent_months to start only back from Jan:
    #, "cmhn0301");
    #http://www.publications.parliament.uk/pa/cm/cmhn0302.htm
}

sub crawl_recent_sessions {
    if ($force) {
        clear_crawl_in_range();
        clear_content_in_range();
        clear_divisions_in_range();
    }

    # Test most recent month and sessions crawl
    my $agent     = WWW::Mechanize->new();
    my $start_url = "http://www.publications.parliament.uk/pa/cm/cmhansrd.htm";
    $agent->get($start_url)->is_success()
      or die "Failed to read URL $start_url";
    print "Scanning recent sessions...\n";
    PublicWhip::FindDays::recent_sessions( $dbh, $agent, "cmse0203",
        "cmse9798" );    # inclusive
}

sub update_calc {
    print "Counting party statistics...\n";
    PublicWhip::Calc::count_party_stats($dbh);
    print "Guessing whip for each party/division...\n";
    PublicWhip::Calc::guess_whip_for_all($dbh);
    print "Counting rebellions/attendence by MP...\n";
    PublicWhip::Calc::count_mp_info($dbh);
    print "Counting rebellions/turnout by division...\n";
    PublicWhip::Calc::count_division_info($dbh);
    print "Rankings...\n";
    PublicWhip::Calc::current_rankings($dbh);
}

sub check {
    print "Checking integrity...\n";
    PublicWhip::Clean::check_integrity($dbh);
    print "Fixing up corrections we know about...\n";
    PublicWhip::Clean::fix_division_corrections($dbh);
    print "Fixing bothway votes...\n";
    PublicWhip::Clean::fix_bothway_voters($dbh);
}

sub all_content {
    my $agent = WWW::Mechanize->new();

    if ($force) {
        clear_content_in_range();
        clear_divisions_in_range();
    }

    my $new_where_clause = $where_clause;
    $new_where_clause =~ s/day_date/pw_hansard_day.day_date/g;
    my $sth = PublicWhip::DB::query(
        $dbh, "select pw_hansard_day.day_date,
        first_page_url from pw_hansard_day left join pw_debate_content on
        pw_hansard_day.day_date = pw_debate_content.day_date where
        pw_debate_content.day_date is null $new_where_clause order by day_date desc",
        @where_params
    );

    print "Getting content for " . $sth->rows() . " missing days\n";
    while ( my @data = $sth->fetchrow_array() ) {
        my ( $date, $url ) = @data;
        $agent->get($url);
        PublicWhip::Content::fetch_day_content( $dbh, $agent, $date );
    }
}

# Clear index of URLs for date range
sub clear_crawl_in_range {
    print "Clearing crawl URL index "
      . $where_params[0] . " to "
      . $where_params[1] . "\n";
    my $sth =
      PublicWhip::DB::query( $dbh,
        "delete from pw_hansard_day where 1=1 $where_clause",
        @where_params );
}

# Clean out downloaded content for date range
sub clear_content_in_range {
    print "Clearing downloaded content "
      . $where_params[0] . " to "
      . $where_params[1] . "\n";
    my $sth =
      PublicWhip::DB::query( $dbh,
        "delete from pw_debate_content where 1=1 $where_clause",
        @where_params );
}

# Clean out all parsed divisions we already have for date range
sub clear_divisions_in_range {
    print "Clearing parsed divisions "
      . $where_params[0] . " to "
      . $where_params[1] . "\n";
    my $sth = PublicWhip::DB::query(
        $dbh,
"update pw_debate_content set divisions_extracted = 0 where 1=1 $where_clause",
        @where_params
    );
    my $new_where_clause = $where_clause;
    $new_where_clause =~ s/day_date/division_date/g;
    $sth =
      PublicWhip::DB::query( $dbh,
        "update pw_division set valid = 0 where 1=1 $new_where_clause",
        @where_params );
    clean();
}

sub all_divisions {
    clear_divisions_in_range() if $force;

    my $sth = PublicWhip::DB::query(
        $dbh,
"select day_date, content from pw_debate_content where divisions_extracted = 0 $where_clause",
        @where_params
    );
    print "Getting divisions for " . $sth->rows() . " days\n\n";
    while ( my @data = $sth->fetchrow_array() ) {
        my ( $day_date, $content ) = @data;
        PublicWhip::Divisions::parse_all_divisions_on_page( $dbh, $content,
            $day_date );
    }
}

sub all_divsxml {
    PublicWhip::DivsXML::read_xml_files( $dbh, $from, $to );
}

sub test {
    my $agent     = WWW::Mechanize->new();
    my $start_url = "http://www.publications.parliament.uk/pa/cm/cmvol321.htm";
    $agent->get($start_url)->is_success()
      or die "Failed to read URL $start_url";
    print "Temporary testing code...\n";
    PublicWhip::FindDays::hunt_within_month_or_volume( $dbh, $agent );
}

#!/usr/bin/perl
#
# build by dongogo
#
# 2010/4/1 ver 1.0 , need log
#
use Smart::Comments ;
use DBI ;
use XML::Simple;
use Data::Dumper;
use HTML::Entities;
require LWP::UserAgent;
use Encode;
use strict ;
use utf8 ;

&main ;


sub main{

	my $dbh = &connect_sql ;

	my $boards = &find_board_list($dbh) ;

	foreach my $board(@$boards){

		### $board

		# download each xml
		my $board_content = &lwp_board($board) ;
	
		# decode UTF-8
		my $decoded_content = Encode::decode('UTF-8', $$board_content) ;

		# parse xml content into hashref	
		my $hashref_content = &parse_board_content( \$decoded_content ) ;	

		# insert into database
		&insert_into_db( $dbh , $board , $hashref_content ) ;	
	}


	$dbh->disconnect();
}


sub parse_push_count{
	my $content = shift ;
	my %result ;

	if(	my ($raw) = $content =~ /<pre>(.*?)<\/pre>/s ) {
		if (my ($pushes) = ($raw =~ /From: [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\n(.*)/s ) ){
			my $pos = 0 ;
			my $neg = 0 ;

			# get each line
			while($pushes =~ /(.*?)\n/s){
				$pushes = $' ;

				if($1 =~ /^推/){
					$pos += 1 ;
				}
				if($1 =~ /^噓/){
					$neg += 1 ;
				}
			}

			$result{'count_positive'} = $pos ;
			$result{'count_negative'} = $neg ;
		}
	}

	return \%result ;
}



sub insert_into_db{
	my $dbh = shift ;
	my $board = shift ;
	my $hashref_content = shift ;

	my $sth = $dbh->prepare("SELECT count(*) as count FROM board_list WHERE board_name=" . $dbh->quote($board) .
	     														      " AND last_updated=" . $dbh->quote($hashref_content->{'updated'}) );
	$sth->execute();

	# insert each entry
	if( ($sth->fetchrow_hashref())->{'count'} == 0 ){
		$dbh->do("UPDATE board_list SET last_updated=". $dbh->quote($hashref_content->{'updated'}) . " WHERE board_name=" . $dbh->quote($board) ) ; 

		for( @{$hashref_content->{'entry'}} ){
			&insert_into_db_entry($dbh , $board , $_) ;	
		}

	}else{
		### return
		return ;
	}

}


sub insert_into_db_entry {
	my $dbh = shift ;
	my $board = shift ;
	my $hashref_entry = shift ;
	
	#parse pushes	
	my $rpushes_result =	&parse_push_count( $hashref_entry->{'content'} ) ;

	#build key/value list	
	my $keys = "(" ;
	my $values = "(" ;

	foreach my $key( keys %$hashref_entry ){
		$keys .= $key . "," ;
		$values .= $dbh->quote($hashref_entry->{$key}) . "," ;
	}
	
	foreach my $key( keys %$rpushes_result ){
		$keys .= $key . "," ;
		$values .= $dbh->quote($rpushes_result->{$key}) . "," ;
	}

	chop($keys) ;
	chop($values) ;
	$keys .= ")" ;
	$values .= ")" ;

	
	# insert
	# delete if id exist
	$dbh->do( "DELETE FROM $board WHERE id=" . $dbh->quote($hashref_entry->{'id'}) ) ;
	$dbh->do( "INSERT INTO $board $keys VALUES $values" ) ;

}


sub parse_board_content {
	my $rboard_content = shift ;
	my %hashref_content ;

	#parse feed
	if( my ($feed) = $$rboard_content =~ /<feed .*?>(.*?)<\/feed>/s ){
	
		#parse updated
		if( my ($updated) = $feed=~/<updated>(.*?)<\/updated>/s ){
			$hashref_content{'updated'} = $updated ;
		}

		#parse entity
		my @arrayref_entry ;
		while( my ($entry) = $feed =~ /<entry>(.*?)<\/entry>/s ) {
			$feed = $' ;
			push @arrayref_entry , &parse_board_entry($entry) ;
		}
		$hashref_content{'entry'} =  \@arrayref_entry ;

	}

	return \%hashref_content ;	
}

sub parse_board_entry{
	my $entry = shift ;
	my %hashref_entry ;

	#author
	if( $entry =~ /<author><name>(.*?)<\/name><\/author>/s ){
		$hashref_entry{'author'} = $1 ;
	}
	
	#title
	if( $entry =~ /<title>(.*?)<\/title>/s ){
		$hashref_entry{'title'} = $1 ;
	}

	#id
	if( $entry =~ /<id>(.*?)<\/id>/s ){
		$hashref_entry{'id'} = $1 ;
	}

	#content
	if( $entry =~ /<content .*?>(.*?)<\/content>/s ){
		$hashref_entry{'content'} = decode_entities($1) ;
	}

	if( $entry =~ /<published>(.*?)<\/published>/s ){
		$hashref_entry{'published'} = $1 ;
	}

	if( $entry =~ /<updated>(.*?)<\/updated>/s ){
		$hashref_entry{'updated'} = $1 ;
	}

	return \%hashref_entry ;
}


sub lwp_board{
	my $board = shift ;

	my $url = "http://rss.ptt.cc/$board.xml" ;

	 
	my $ua = LWP::UserAgent->new;
	$ua->timeout(10);
	$ua->env_proxy;

	my $response = $ua->get( $url );

	my $all ;
	if ($response->is_success) {
		$all = $response->content;  # or whatever
	}
	else {
		die $response->status_line;
	}

	return \$all ;
}

sub find_board_list{
	my $dbh = shift ;


	my $results = $dbh->selectall_hashref('SELECT * FROM board_list WHERE enable=1', 'board_id');

	my @boards ;

	foreach(keys %$results){
		push @boards , $results->{$_}->{'board_name'} ;
	}

	return \@boards ;
}

sub connect_sql{
	my $dbh = DBI->connect('DBI:mysql:ptt;host=localhost', 
			'ptt', 'ntucsie',
			{ RaiseError => 1 }
			);

	$dbh->do("set names utf8") ;
	return $dbh ;
}

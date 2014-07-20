use Mojolicious::Lite;

use Config::YAML;
use DBI;
use DateTime;
use Scalar::Util qw/looks_like_number/;

my $cfg = Config::YAML->new( config => 'config.yaml' );
my $db_path = $cfg->{db_path};

my $dbh = DBI->connect("dbi:SQLite:dbname=$db_path",'','') 
  or die "Couldn't open DB";

get '/stats' => sub {

	my $c = shift;

	my $now = DateTime->now();

	my $last_fail_sco = last_failure('sco');
	my $last_fail_mc = last_failure('meta');

	if ( defined $last_fail_sco ) {
		my $outage_start = last_success_before( 'sco', $last_fail_sco );
		$c->stash( 
			sco_last_fail => 
			DateTime->from_epoch( epoch => $last_fail_sco )->strftime('%F %H:%M'),
			sco_outage_start => 
				DateTime->from_epoch( epoch => $outage_start )->strftime('%F %H:%M'),
		);
	} else {
		$c->stash( sco_outage_start => "N/A", sco_last_fail => "N/A" );
	}

	if ( defined $last_fail_mc ) {
		my $outage_start = last_success_before( 'meta', $last_fail_mc );
		$c->stash( 
			mc_last_fail => 
			DateTime->from_epoch( epoch => $last_fail_mc )->strftime('%F %H:%M'),
			mc_outage_start => 
				DateTime->from_epoch( epoch => $outage_start )->strftime('%F %H:%M'),
		);
	} else {
		$c->stash( mc_last_fail => "N/A", mc_outage_start => "N/A" );
	}

	my $current_status_sco = current_status('sco');
	my $current_status_mc = current_status('meta');

	$c->stash(
		sco_current => $current_status_sco->{result},
		mc_current => $current_status_mc->{result},
	);

	# and finally, the important bit. oops.

	my $speed; my $avail;

	for my $site (qw/meta sco/) {
		for ( 'all', 1, 7, 30, 90 ) {
			my $args = looks_like_number $_ ? { 
				start => DateTime->now->subtract( days => $_ )->epoch()
			} : {};
			my $res =  results_interval( $site, %$args );
			$speed->{$site}{$_.'days'} = $res->{avg_time};
			$avail->{$site}{$_.'days'} = $res->{percent_up};
		}
	}

	$c->stash( speed => $speed, avail => $avail );

	$c->render('stats');

};

get '/raw' => sub {

	my $c = shift;


	$c->render('raw');

};

app->start;

# "model" begins here.
# yeah, yeah

sub last_failure {

	my $site = shift;

	my $ts = $dbh->selectrow_array(
		'SELECT timestamp FROM results WHERE result = 0 AND site = ?
		ORDER BY timestamp DESC LIMIT 1',
		{}, $site
	);

	return $ts;

}

sub last_success_before {

	my $site = shift;
	my $before = shift;

	my $ts = $dbh->selectrow_array(
		'SELECT timestamp FROM results WHERE site = ? AND timestamp < ?
		 ORDER BY timestamp DESC LIMIT 1',
		 {}, $site, $before
	);

	return $ts;

}

sub current_status {

	my $site = shift;

	my $res = $dbh->selectrow_hashref(
		'SELECT * FROM results WHERE site = ? ORDER BY timestamp DESC LIMIT 1',
		{}, $site
	);

	return $res;

}

sub results_interval {

	my $site = shift;
	my %options = ( start => 0, end => time(), @_ );

	my ($avg, $up, $trials) = $dbh->selectrow_array(
		'SELECT avg(msec), sum(result), count(*) FROM results 
			WHERE timestamp > ? AND timestamp < ? AND site = ?',
		{},
		@options{qw/start end/}, $site
	);

	return {
		avg_time => sprintf( "%.0f", $avg ),
		percent_up => $trials ? sprintf( "%.2f", 100 * $up / $trials ) : 'N/A',
		trials => $trials
	};

}
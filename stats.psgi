use Mojolicious::Lite;

use Config::YAML;
use DBI;

my $cfg = Config::YAML->new( config => 'config.yaml' );
my $db_path = $cfg->{db_path};

my $dbh = DBI->connect("dbi:SQLite:dbname=$db_path",'','') 
  or die "Couldn't open DB";

get '/stats' => sub {

	my $c = shift;

	$c->render('stats');

};

app->start;

#!perl -w

use SOAP::Lite;# +trace => qw( debug );
use Data::Dumper;

my $client = SOAP::Lite->new;
$client->schema->useragent->agent("xxv 1.0");
my $service = $client->service('http://localhost/t10.php?wsdl');

my $result;
print "## getServerTime ######################################################\n";
$result = $service->getServerTime();
print Dumper($result);

print "## getUsrKey ##########################################################\n";
$result = $service->getUsrKey('myuserkey');
print Dumper($result);

print "## setEventLevel ######################################################\n";
$result = $service->setEventLevel("myuserkey1",1253535,5,time+3600);
print Dumper($result);

print "## setEventLevel ######################################################\n";
$result = $service->setEventLevel("myuserkey2",1253535,3,time+3600);
print Dumper($result);

print "## setEventLevel ######################################################\n";
$result = $service->setEventLevel("myuserkey3",1253535,3,time+3600);
print Dumper($result);

print "## setEventLevel ######################################################\n";
$result = $service->setEventLevel("myuserkey4",1253532,3,time+3600);
print Dumper($result);

print "## getEventLevel ######################################################\n";
$result = $service->getEventLevel("myuserkey4",1253535);
print Dumper($result);

print "## getEventLevels #####################################################\n";
$result = $service->getEventLevels("myuserkey4",);
print Dumper($result);

print "## getTopTen ##########################################################\n";
$result = $service->getTopTen("myuserkey4",20);
print Dumper($result);

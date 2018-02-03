use strict;
use warnings;
use Test::More;
use HTTP::Request::Common qw/ GET POST DELETE /;
use JSON qw/from_json/;

use Catalyst::Test 'stemmaweb';
use Test::WWW::Mechanize::Catalyst;
use stemmaweb::Controller::Relation;

use FindBin;
use lib ("$FindBin::Bin/lib");

use stemmaweb::Test::DB;
my $textids = stemmaweb::Test::DB::new_db("$FindBin::Bin/data");

# Traditions used to test
my $pubrelurl = '/relation/' . $textids->{public}->[2];
my $privrelurl = '/relation/' . $textids->{private}->[2];

### While not logged in:

# test GET public text
my $attempt = request GET $pubrelurl;
ok($attempt->is_redirect, "Got redirect to first section");
$pubrelurl = $attempt->header('location');
$attempt = request GET $pubrelurl;
ok($attempt->is_success, "Loaded viewer for public tradition");
like($attempt->decoded_content, qr!"readonly" === "full"!, "Viewer is in readonly mode");

# test GET private text (403)
$attempt = request GET $privrelurl;
is($attempt->code, 403, "Permission denied for private tradition");

# test GET, POST, DELETE relationships

$attempt = request GET $pubrelurl . "/relationships";
ok($attempt->is_success, "Requested relationships on public tradition section");
like( $attempt->header('Content-Type'), qr/application\/json/, "Got a JSON response");
my $rels = from_json($attempt->decoded_content);
is(scalar @$rels, 96, "Found the correct number of relationships");

$attempt = request POST $pubrelurl . "/relationships",
	[source_id => $rels->[0]->{source}, target_id => $rels->[0]->{target}];
is($attempt->code, 403, "Permission denied for relationship push");

$attempt = request DELETE $pubrelurl . "/relationships",
	[ source_id => $rels->[0]->{source}, target_id => $rels->[0]->{target} ];
is($attempt->code, 403, "Permission denied for relationship deletion");

# test GET readings
$attempt = request GET $pubrelurl . "/readings";
ok($attempt->is_success, "Requested reading list for public tradition section");
like( $attempt->header('Content-Type'), qr/application\/json/, "Got a JSON response");
my $pubrdgs = from_json($attempt->decoded_content);
is(scalar keys %$pubrdgs, 990, "Found the correct number of readings");

# test GET, POST reading
my @rdgsearch = grep { $_->{rank} == 7 && $_->{text} eq 'uirginem'} values %$pubrdgs;
my $virginem = shift(@rdgsearch);
ok($virginem, "Found test reading in list");
$attempt = request GET $pubrelurl . "/reading/" . $virginem->{id};
ok($attempt->is_success, "Got reading information");
my $rdgdata = from_json($attempt->decoded_content);
is($rdgdata->{normal_form}, 'uirginem', "Reading information look right");

$attempt = request POST $pubrelurl . "/reading/" . $virginem->{id},
	[id => $virginem->{id}, normal_form => 'wirginem'];
is($attempt->code, 403, "Permission denied trying to change reading");

# test POST compress/merge/duplicate/split (403)

### While logged in:

my $mech = Test::WWW::Mechanize::Catalyst->new( catalyst_app => 'stemmaweb' );
$mech->get_ok( '/login', "Requested the login page successfully" );
$mech->submit_form(
	form_id => 'login_local_form',
	fields => {  username => 'user@example.org', password => 'UserPass' } );
$mech->get_ok( '/' );
$mech->content_contains( 'Hello! user@example.org', "Successfully logged in" );

# test GET private text / next section
$attempt = $mech->get($privrelurl);
ok($attempt->is_success, "Loaded viewer for private tradition");
ok($attempt->previous, "We got here via a redirection");
like($attempt->decoded_content, qr!"full" === "full"!, "Viewer is in editing mode");
# Get the section URL for all remaining requests
$privrelurl = $mech->uri;

$attempt = $mech->follow_link(text => 'section test');
ok($attempt->is_success, "Loaded second section of the text");
my $privsection2 = $mech->uri;

# test GET, DELETE, POST relationships

$attempt = $mech->get($privrelurl . "/relationships");
ok($attempt->is_success, "Requested relationships on private tradition section");
like($mech->ct, qr/application\/json/, "Got a JSON response");
$rels = from_json($attempt->decoded_content);
is(scalar @$rels, 13, "Found the correct number of relationships");

my $testrel = $rels->[0];
## Horrible hackish way to construct a DELETE request
my $del = POST $privrelurl . "/relationships",
    [source_id => $testrel->{source}, target_id => $testrel->{target}];
$del->method('DELETE');
$attempt = $mech->request($del);
ok($attempt->is_success, "Deleted a relationship");

$attempt = $mech->get($privrelurl . "/relationships");
$rels = from_json($attempt->decoded_content);
is(scalar @$rels, 12, "Relationship is gone");

my $replace = POST $privrelurl . "/relationships",
    [source => $testrel->{source},
     target => $testrel->{target},
     scope => $testrel->{scope},
     type => $testrel->{type}];
$attempt = $mech->request($replace);
ok($attempt->is_success, "Replaced the relationship");
$attempt = $mech->get($privrelurl . "/relationships");
$rels = from_json($attempt->decoded_content);
is(scalar @$rels, 13, "Relationship has been restored");

# test GET, POST reading(s)
$attempt = $mech->get($privrelurl . "/readings");
ok($attempt->is_success, "Requested reading list for private tradition section");
like( $attempt->header('Content-Type'), qr/application\/json/, "Got a JSON response");
my $rdgs = from_json($attempt->decoded_content);
is(scalar keys %$rdgs, 30, "Found the correct number of readings");

@rdgsearch = grep { $_->{text} eq 'uenerabilis' } values %$rdgs;
my $ven = shift @rdgsearch;
ok($ven, "Got a test reading");
$attempt = $mech->request(POST($privrelurl . "/reading/" . $ven->{id},
    [normal_form => 'venerabilis', is_lemma => 'true']));
ok($attempt->is_success, "Altered data of a reading");

$attempt = $mech->get($privrelurl . "/reading/" . $ven->{id});
my $newven = from_json($attempt->decoded_content);
isnt($newven->{normal_form}, $ven->{normal_form}, "Normal form changed");
isnt($newven->{is_lemma}, $ven->{is_lemma}, "is_lemma setting changed");

# Get our marked readings from the public tradition for duplicate/merge
# operations
my( $wrong, $right );
@rdgsearch = grep { $_->{text} eq 'et' } values %$pubrdgs;
foreach my $r (@rdgsearch) {
    $wrong = $r if $r->{is_nonsense};
    $right = $r if $r->{grammar_invalid};
}
ok($right, "Found our marked target reading");
ok($wrong, "Found our marked target reading");

# test POST duplicate, now with the public tradition
$attempt = $mech->request(POST($pubrelurl . "/duplicate",
    ['readings[]' => $wrong->{id},
     'witnesses[]' => 'Ba96']));
ok($attempt->is_success, "Duplicated target reading");
my $resp = from_json($attempt->decoded_content);
is(scalar keys %$resp, 2, "Response has two keys");
ok(exists $resp->{DELETED}, "A relationship was deleted during duplicate");
is($resp->{DELETED}->[0]->[2], 'transposition', "It was a transposition relationship");
is($pubrdgs->{$resp->{DELETED}->[0]->[0]}->{text}, 'asserendo', '...between the expected readings');
delete($resp->{DELETED});
my $fixed = (values %$resp)[0];
ok(!exists $pubrdgs->{$fixed->{id}}, "Resulting reading is new");

# test POST merge
$attempt = $mech->request(POST($pubrelurl . "/merge",
    [source => $right->{id},
     target => $fixed->{id}]));
ok($attempt->is_success, "Merged a pair of 'et' readings");
$resp = from_json($attempt->decoded_content);
is($resp->{status}, "ok", "Merge succeeded");
ok($resp->{checkalign}, "Found more mergeable readings");

$attempt = $mech->get($pubrelurl . "/readings");
ok($attempt->is_success, "Re-requested reading list for public tradition section");
$pubrdgs = from_json($attempt->decoded_content);
is(scalar keys(from_json($attempt->decoded_content)), 990, "Number of readings unchanged");

# test POST compress

# test POST split

### Log out and try a few things with known data

$mech->get_ok('/logout', "Logged out successfully");

# test GET second section (403)
$attempt = $mech->get($privsection2);
is($attempt->code, 403, "Attempt to get known section of private text fails");

# test GET private relationships (403)
$attempt = $mech->get($privrelurl . "/relationships");
is($attempt->code, 403, "Attempt to get relationships of known private text fails");

# test GET private reading(s) (403)
$attempt = $mech->get($privrelurl . "/readings");
is($attempt->code, 403, "Attempt to get readings of known private text fails");


done_testing();

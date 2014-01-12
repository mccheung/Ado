#ado-sessions.t
use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

use_ok 'Ado::Sessions';
use_ok 'Mojolicious::Sessions';
my $config = {session => {type => 'mojo', options => {}}};
isa_ok my $m = Ado::Sessions::get_instance($config), 'Mojolicious::Sessions';
$config->{session} = {type => 'file', options => {}};
isa_ok my $f = Ado::Sessions::get_instance($config), 'Ado::Sessions::File';
$config->{session} = {type => 'database', options => {}};
isa_ok my $d = Ado::Sessions::get_instance($config), 'Ado::Sessions::Database';

foreach my $method (qw(load store)) {
    foreach my $instance ($f, $d, $m) {
        can_ok $instance, $method;
    }
}

foreach my $method (qw(generate_id)) {
    foreach my $instance ($f, $d) {
        my $sid = $instance->$method;
        ok $sid, "$method $sid ok";
    }
}

my $t           = Test::Mojo->new('Ado');
my $cookie_name = $t->app->config('session')->{options}{cookie_name};

# Create new SID
$t->get_ok("/добре/ок?$cookie_name=123456789");
my $sid = $t->tx->res->cookie($cookie_name)->value;
ok $sid, "new sid $sid ok";

$t->get_ok("/?$cookie_name=$sid");
is $sid, $t->tx->res->cookie($cookie_name)->value, "Param $sid ok";

#$t->get_ok("/");
#is $sid, $t->tx->res->cookie('adosessionid')->value, "Cookie $sid ok";

#$t->get_ok("/?adosessionid=wrong");
#isnt $sid, $t->tx->res->cookie('adosessionid')->value, "Param wrong sid ok";

#$t->tx->req->cookie('adosessionid', 'WRONG!');
#$t->get_ok("/");
#isnt $sid, $t->tx->res->cookie('adosessionid')->value, "Bad SID ok";

done_testing();


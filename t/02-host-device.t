# -*-perl-*-

use strict;
use warnings;
use Test::More;
use FindBin qw($Bin);

use MogileFS::Server;
use MogileFS::Util qw(error_code);
use MogileFS::Test;
use MogileFS::Factory;
use MogileFS::Factory::Host;
use MogileFS::Factory::Device;
use MogileFS::Host;
use MogileFS::Device;

use Data::Dumper qw/Dumper/;

my $sto = eval { temp_store(); };
if ($sto) {
    plan tests => 21;
} else {
    plan skip_all => "Can't create temporary test database: $@";
    exit 0;
}

# Fetch the factories.
my $hostfac = MogileFS::Factory::Host->get_factory;
ok($hostfac, "got a host factory");
my $devfac = MogileFS::Factory::Device->get_factory;
ok($devfac, "got a device factory");

MogileFS::Config->set_config_no_broadcast("min_free_space", 100);

# Ensure the inherited singleton is good.
ok($hostfac != $devfac, "factories are not the same singleton");

{
    # Test host.
    my $host = $hostfac->set({ hostid => 1, hostname => 'foo', hostip =>
'127.0.0.5', status => 'alive', http_port => 7500, observed_state =>
'reachable'});
    ok($host, 'made a new host object');
    is($host->id, 1, 'host id is 1');
    is($host->name, 'foo', 'host name is foo');

    # Test device.
    my $dev = $devfac->set({ devid => 1, hostid => 1, status => 'alive',
weight => 100, mb_total => 5000, mb_used => 300, mb_asof => 1295217165,
observed_state => 'writeable'});
    ok($dev, 'made a new dev object');
    is($dev->id, 1, 'dev id is 1');
    is($dev->host->name, 'foo', 'name of devs host is foo');
    ok($dev->can_delete_from, 'can_delete_from works');
    ok($dev->can_read_from, 'can_read_from works');
    ok($dev->should_get_new_files, 'should_get_new_files works');

    $hostfac->remove($host);
    $devfac->remove($dev);
}

# Might be able to skip the factory tests, as domain/class cover those.

{
    # Add a host and two devices to the DB.
    my $hostid = $sto->create_host('foo', '127.0.0.7');
    is($hostid, 1, 'new host got id 1');

    # returns 1 instead of the devid :(
    # since this it the only place which doesn't autogenerate its id.
    ok($sto->create_device(1, $hostid, 'alive'), 'created dev1');
    ok($sto->create_device(2, $hostid, 'down'), 'created dev2');

    # Update host details to DB and ensure they stick.
    ok($sto->update_host($hostid, { http_port => 6500, http_get_port => 6501 }),
        'updated host DB entry');
    # Update device details in DB and ensure they stick.
    ok($sto->update_device(1, { mb_total => 150, mb_used => 8 }),
        'updated dev1 DB entry');
    ok($sto->update_device(2, { mb_total => 100, mb_used => 3,
        status => 'dead' }), 'updated dev2 DB entry');

    # Test duplication errors.
}

{
    # Reload from DB and confirm they match what we had before.
    my @hosts = $sto->get_all_hosts;
    my @devs  = $sto->get_all_devices;

    is_deeply($hosts[0], {
            'http_get_port' => 6501,
            'status' => 'down',
            'http_port' => '6500',
            'hostip' => '127.0.0.7',
            'hostname' => 'foo',
            'hostid' => '1',
            'altip' => undef,
            'altmask' => undef
    }, 'host is as expected');

    is_deeply($devs[0], {
            'mb_total' => 150,
            'mb_used' => 8,
            'status' => 'alive',
            'devid' => '1',
            'weight' => '100',
            'mb_asof' => undef,
            'hostid' => '1'
    }, 'dev1 is as expected');
    is_deeply($devs[1], {
            'mb_total' => 100,
            'mb_used' => 3,
            'status' => 'dead',
            'devid' => '2',
            'weight' => '100',
            'mb_asof' => undef,
            'hostid' => '1'
    }, 'dev2 is as expected');
}


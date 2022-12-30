#!/usr/bin/perl
# this script is used to deploy zookeeper among current cluster
# 20200202 - mahaiqing - reconstruction.

use strict;
use warnings;
use FindBin '$RealBin';
use File::Basename;
use lib "$RealBin/../lib/perl5";
use lib "$RealBin";
use Config::Properties;
use Net::OpenSSH;
use Data::Dumper;


use Public_storage;


my $script_path = $RealBin;
my $directory_deploy = dirname($script_path);
my $log_directory=File::Spec->catfile($directory_deploy, "logs");
unless ( -d "$log_directory" ) {
    print "\nthere is no directory($log_directory) to save log, create one\n";
    # exit 1;
    system("mkdir -p $log_directory");
}

my $log_file = File::Spec->catfile($log_directory,"storage-zookeeper-deploy.log");
my $time_stamp = localtime();
if (-e "$log_file") {
    my $file_size = (stat "$log_file")[7];
    if ( $file_size >= 1048576 ) {
        system("echo -e 'clear old logs at $(time_stamp) to avoid log file too big' > $log_file");
    }
}

system("touch $log_file");
open(LOG_FILE, '>>', "$log_file") ||  die ("Can't open log file $log_file to record process of operation !!");
$| = 1;
my $step_index = 0;
$step_index++;
&show_step_information("This is going to do deploy zookeeper among current cluster ",$step_index);


$step_index++;
&show_step_information("check zookeeper.properties login information ",$step_index);
my $file_deploy_properties = File::Spec->catfile($directory_deploy, 'config/deploy.properties');
unless ( -e $file_deploy_properties ) {
    print "There is no expected deploy config file($file_deploy_properties) under deploy direcotry! \n";
    return 1;
}
open my $file_handler_deploy, '<', $file_deploy_properties
    or die "unable to open configuration file deploy.properties";
my $deploy_properties = Config::Properties->new();
$deploy_properties->load($file_handler_deploy);
my $config_tree_deploy_properties = $deploy_properties->splitToTree();
close $file_handler_deploy;

my $login_user = $config_tree_deploy_properties->{'remote'}{'user'};
$login_user =~ s/\s//g;
my $login_passwd = $config_tree_deploy_properties->{'remote'}{'password'};
$login_passwd =~ s/\s//g;
say LOG_FILE "from deploy config file, the login information to hosts is: $login_user(user), $login_passwd(password)";


my $file_zookeeper_properties = File::Spec->catfile($directory_deploy, 'config/zookeeper.properties');
unless ( -e $file_zookeeper_properties ) {
    print "There is no expected zookeeper config file($file_zookeeper_properties) under deploy direcotry! \n";
    return 1;
}

open my $file_handler_zookeeper, '<', $file_zookeeper_properties
    or die "unable to open configuration file zookeeper.properties";
my $zookeeper_properties = Config::Properties->new();
$zookeeper_properties->load($file_handler_zookeeper);
my $config_tree_zookeeper_properties = $zookeeper_properties->splitToTree();
close $file_handler_zookeeper;

my $login_user_zookeeper = $config_tree_zookeeper_properties->{'remote'}{'user'};
$login_user_zookeeper =~ s/\s//g;
my $login_passwd_zookeeper = $config_tree_zookeeper_properties->{'remote'}{'password'};
$login_passwd_zookeeper =~ s/\s//g;
say LOG_FILE "from zookeeper config file, the login information to hosts is: $login_user_zookeeper(user), $login_passwd_zookeeper(password)";

unless ( $login_user eq $login_user_zookeeper ) {
    print "update zookeeper.properties remote.user to $login_user \n";
    say LOG_FILE "update zookeeper.properties remote.user to $login_user \n";
    system ("sed -i 's#remote.user=.*#remote.user=$login_passwd#g' $file_zookeeper_properties ");
}
unless ( $login_passwd eq $login_passwd_zookeeper ) {
    print "update zookeeper.properties remote.password to $login_passwd \n";
    say LOG_FILE "update zookeeper.properties remote.password to $login_user \n";
    system ("sed -i 's#remote.password=.*#remote.password=$login_passwd_zookeeper#g' $file_zookeeper_properties ");
}

my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};


$step_index++;
&show_step_information("get properties' value from current settings",$step_index);

my $zookeeper_cfg = Config::Properties->new();
$zookeeper_cfg->format('%s=%s');

my @properties_list = qw(tickTime minSessionTimeout maxSessionTimeout initLimit syncLimit dataDir 
    dataLogDir clientPort maxClientCnxns autopurge.snapRetainCount autopurge.purgeInterval preAllocSize);

my $tmp_results = undef;
foreach (sort @properties_list) {
    $tmp_results = $zookeeper_properties->getProperty("default.$_");
    $zookeeper_cfg->setProperty($_, $tmp_results);
    say LOG_FILE "set property [$_] to value [$tmp_results]";
}

$step_index++;
&show_step_information("get port and hosts information from current settings",$step_index);
# my $default_communication_port = $config_tree_zookeeper_properties->{default}{communicationPort};
# my $default_selection_port = $config_tree_zookeeper_properties->{default}{selectionPort};
my $default_communication_port = $zookeeper_properties->getProperty("default.communicationPort");
my $default_selection_port = $zookeeper_properties->getProperty("default.selectionPort");
say LOG_FILE "default.communicationPort=$default_communication_port; default.selectionPort=$default_selection_port";

my %hash_id_server = %{$config_tree_zookeeper_properties->{server}};
for (sort keys %hash_id_server) {
    say LOG_FILE "zookeeper cluster index:$_, value:$hash_id_server{$_}\n";
} 

$tmp_results = keys %hash_id_server;
say LOG_FILE "current zookeeper cluster number is: $tmp_results";
if ( $tmp_results%2 == 0 ) {
    print "odd number is suggested for zookeeper cluster. Current number is: $tmp_results !!\n";
}

my @tmp_array = sort values %hash_id_server;
my %tmp_hash = ();
my @server_list = grep { ++$tmp_hash{$_}<2; } @tmp_array;
say LOG_FILE "zookeeper hosts are as follows: @server_list";
unless ( scalar(@server_list) eq $tmp_results ) {
    say LOG_FILE "It seems there are repeated host ip address in file $file_zookeeper_properties";
    print "It seems there are repeated host ip address in file $file_zookeeper_properties\n";
    exit 1;
}


for (sort keys %hash_id_server) {
    $tmp_results = "$hash_id_server{$_}:$default_communication_port:$default_selection_port";
    $zookeeper_cfg->setProperty("server.$_", $tmp_results);
    say LOG_FILE "set property [server.$_] to value [$tmp_results]";
}


$step_index++;
&show_step_information("save properties to file zookeeper.cfg",$step_index);
my $file_zookeeper_cfg = File::Spec->catfile($directory_deploy, "logs", 'zookeeper.cfg');
open my $file_handler_zookeeper_cfg, '>', $file_zookeeper_cfg
    or die "unable to open configuration file zookeeper.cfg";
$zookeeper_cfg->format('%s=%s');
$zookeeper_cfg->store($file_handler_zookeeper_cfg);    
close($file_handler_zookeeper_cfg);


$step_index++;
&show_step_information("get zookeeper package information from current settings",$step_index);
my $package_zookeeper_name = $zookeeper_properties->getProperty("zookeeper.package.location");
say LOG_FILE "zookeeper package name is: $package_zookeeper_name";

my $package_zookeeper_fullpath = File::Spec->catfile($directory_deploy,"packages", $package_zookeeper_name);
unless ( -e $package_zookeeper_fullpath ) {
    print "There is no zookeeper package $package_zookeeper_name under packages of $directory_deploy !! \n";
    say LOG_FILE "There is no zookeeper package $package_zookeeper_name under packages of $directory_deploy !! ";
    exit 1;
} else {
    say LOG_FILE "There is package file $package_zookeeper_name under packages of $directory_deploy !! ";
}


my $default_deploy_location = $zookeeper_properties->getProperty("default.deploy.location");
my $default_dataDir = $zookeeper_properties->getProperty("default.dataDir");
my $default_dataLogDir = $zookeeper_properties->getProperty("default.dataLogDir");
say LOG_FILE "default.deploy.location=$default_deploy_location; default.dataDir=$default_dataDir; default.dataLogDir=$default_dataLogDir";
my $direcotry_name = substr($package_zookeeper_name, 0, length($package_zookeeper_name)-7);
my $direcotry_remote_zookeeper = File::Spec->catfile($default_deploy_location, $direcotry_name);
say LOG_FILE "zookeeper remote deploy direcotry is : $direcotry_remote_zookeeper";



for (sort keys %hash_id_server) {
    my $host_ip = $hash_id_server{$_};
    $step_index++;
    &show_step_information("deploy zookeeper to host $host_ip",$step_index);
    $tmp_results =  &Public_storage::operation_ping($host_ip);
    if ( $tmp_results eq "fail" ) {
        print "zookeeper deploy operation fail as host $host_ip can't be accessed !!!\n";
        say LOG_FILE "zookeeper deploy operation fail as host $host_ip can't be accessed !!!\n";
        exit 1;
    }

    my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);
    $tmp_results = &Public_storage::check_remote_path_exists($login_user, $login_passwd, $host_ip, $default_deploy_location);
    if ( $tmp_results eq "file" ) {
        say LOG_FILE "remote $default_deploy_location is a file, delete it ";
        system("rm -f $default_deploy_location");
        $ssh->system("mkdir -p $default_deploy_location");
    } elsif ( $tmp_results =~ "fail" ) {
        say LOG_FILE "create direcotry $default_deploy_location as $tmp_results";
        $ssh->system("mkdir -p $default_deploy_location");
    } else {
        say LOG_FILE "remote direcotry $default_deploy_location exists already.";
    }

    $tmp_results = &Public_storage::check_remote_path_exists($login_user, $login_passwd, $host_ip, "$direcotry_remote_zookeeper/bin/zkServer.sh");
    if ( $tmp_results eq "file" ) {
        say LOG_FILE "stop zookeeper service and deploy it again";
        print "stop zookeeper service and deploy it again\n";
        $ssh->system("$direcotry_remote_zookeeper/bin/zkServer.sh stop $default_deploy_location/zookeeper.cfg");
    }
    
    $ssh->scp_put({recursive => 1}, $package_zookeeper_fullpath, $default_deploy_location);
    $ssh->system("tar -zxf $default_deploy_location/$package_zookeeper_name -C $default_deploy_location");
        
    $ssh->system("mkdir -p $default_dataDir");
    $ssh->system("mkdir -p $default_dataLogDir");

    $ssh->system("echo $_ > $default_dataDir/myid");

    $ssh->scp_put({recursive => 1}, $file_zookeeper_cfg, $default_deploy_location);

    say LOG_FILE "start zookeeper service on host $host_ip";
    print "start zookeeper service on host $host_ip\n";
    $ssh->system("$direcotry_remote_zookeeper/bin/zkServer.sh start $default_deploy_location/zookeeper.cfg");
}


$step_index++;
&show_step_information("This is the end of deploy zookeeper among current cluster ",$step_index);
say LOG_FILE "================================================================================";
print "================================================================================\n";
close LOG_FILE;
exit 0;


sub show_step_information {
    (my $message, my $step_index) = @_;
    chomp($time_stamp=localtime());
    say LOG_FILE "-------------------------------------------------------------------------------";
    print LOG_FILE "step $step_index : $message [$time_stamp]\n";
    say LOG_FILE "-------------------------------------------------------------------------------";
    print "step $step_index : $message [$time_stamp]\n";
}


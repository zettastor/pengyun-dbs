#!/usr/bin/perl
#
# 20191107 - mahaiqing - reconfiguration.
#
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib/perl5";
use lib "$RealBin";

use Config::Properties;
use File::Basename;
use Getopt::Long;
use Net::OpenSSH;

use Public_storage;

my $script_path = $RealBin;
my $directory_deploy = dirname($script_path);
my $log_directory=File::Spec->catfile($directory_deploy, "logs");
unless ( -d "$log_directory" ) {
    print "\nthere is no directory($log_directory) to save log, create one\n";
    # exit 1;
    system("mkdir -p $log_directory");
}

my $log_file = File::Spec->catfile($log_directory,"storage-service-operation.log");
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
&show_step_information("Check storage service operation input parameters",$step_index++);

# defines operation deploy, upgrade wipeout and so on
my $command_operation = undef;
# specify address of remote machine
my $pToDeployHost = undef;
# specify host range by group Id
my $groupId = undef;
# one of extra arguments for operation
my $isTest = undef;
# one of extra arguments for test to disable processmanager
my $noPM = undef;
my $yourkitEnabled = undef;
# only used to wipeout environment bypass config file.try to wipoeut all service on specify host
my $withoutConfig = undef;
# if ignoreUpdate, don't execute the script  to update local packages
my $ignoreUpdate = undef;
GetOptions ("command=s" => \$command_operation,
    "pToDeployHost=s" => \$pToDeployHost,
    "groupId=s" => \$groupId,
    "test" => \$isTest,
    "withoutconfig" => \$withoutConfig,
    "ignore_update" => \$ignoreUpdate,
    "noPM" =>\$noPM,
    "yourkit_enabled" =>\$yourkitEnabled);

die &usage() unless ( defined $command_operation and $command_operation =~ /.*:.*/);
my ($operation_type, $service_name) = split(/:/, $command_operation);
die &usage() unless ( defined $operation_type && defined $service_name);

$operation_type = lc $operation_type;
$service_name = uc $service_name;

my $params_input = undef;

if (defined $isTest) {
    $params_input = "--params=test" if defined $isTest;
    $params_input = $params_input.",pm_disabled" if defined $noPM;
    $params_input = $params_input.",yourkit_enabled" if defined $yourkitEnabled;
}


if(defined $withoutConfig) {
    if ($operation_type eq "wipeout") {
        if (defined $params_input) {
            $params_input = $params_input.",withoutconfig";
        } else {
            $params_input = "--params=withoutconfig";
        }
    } else {
        print "parameter 'withoutconfig' only used in wipeout operation, ignore it\n";
        say LOG_FILE "parameter 'withoutconfig' only used in wipeout operation, ignore it";
    }
}


if (defined $groupId) {
    if (defined $params_input) {
        $params_input = $params_input.",group".$groupId;
    } else {
        $params_input = "--params=group".$groupId;
    }
}

my @array_command_line = ();
push @array_command_line, "--operation=$operation_type";
push @array_command_line, "--serviceName=$service_name";
push @array_command_line, $params_input if defined $params_input;
push @array_command_line, "--serviceHostRange=$pToDeployHost" if defined $pToDeployHost;
push @array_command_line, "--groupId=$groupId" if defined $groupId;

my $string_command_line = "";
foreach (@array_command_line) {
    $string_command_line = $string_command_line." $_";
}
say LOG_FILE "To jar file parameter is :$string_command_line\n";

my $file_deploy_properties = File::Spec->catfile($script_path, "../config/deploy.properties");
&show_step_information("Check jdbc type",$step_index++);
my $jdbc_type = &get_jdbc_type();
unless ( ($jdbc_type eq "mariadb") || ($jdbc_type eq "postgresql")) {
    print "\n jdbc typc [$jdbc_type] is not in supported type list [mariadb postgresql]\n";
    say LOG_FILE "jdbc typc [$jdbc_type] is not in supported type list [mariadb postgresql]";
    exit 1;
}

&show_step_information("Check xml configuration",$step_index++);
my $file_xml = File::Spec->catfile($script_path, "../config/module_settings.xml");
unless( -e $file_xml ) {
    say LOG_FILE "there is no XML[$file_xml] file for product. Checking configuration again... \n";
    print "\nfail: no expect xml[$file_xml] find under config directory\n";
    exit 1;
}


my $tmp_value = &check_xml_configuration_by_jdbc();
if ($tmp_value =~ "fail") {
    print "xml configuration about jdbc is not right. $tmp_value\n";
    say LOG_FILE "xml configuration about jdbc is not right. $tmp_value\n";
    exit 1;
}


&show_step_information("Check need to update local packages or not",$step_index++);
my $choice_update = undef;
unless ( defined $ignoreUpdate) {
    # body...
    while () {
        print "==== Do you want to update configuration for local packages [y/n] ? ";
        chomp($choice_update = <STDIN>);
        say LOG_FILE "update local packages ? input: [$choice_update]";
        $choice_update = lc $choice_update;
        if (($choice_update eq "y") || ($choice_update eq "n")) {
            last;
        }
    }

    if ($choice_update eq 'y') {
        say LOG_FILE "update local packages according to user input";
        system ( "perl $script_path/update_system_config.pl");
    } else {
        say LOG_FILE "Not need to update local packages according to user input";
    }
} else {
    say LOG_FILE "Don't need to check this as input 'ignoreUpdate' ";
}

&show_step_information("Check need to wipeout database or not",$step_index++);
my $flag_wipeout_database = "false";
unless ( $operation_type eq "wipeout" ) {
    # body...
    say LOG_FILE "Not need to wipeout database except wipeout operation";
} else {
    if ( $service_name eq "DATABASE" ) {
        say LOG_FILE "wipeout database as service name [database] is specified";
        $flag_wipeout_database = "true";
    } elsif ( $service_name eq "ALL" ) {
        if (defined $pToDeployHost) {
            say LOG_FILE "only wipeout some specified host. Do not wipeout database";
        } else {
            say LOG_FILE "The whole environment will be wipeout";
            $flag_wipeout_database = "true";
        }
    }
}


if ($flag_wipeout_database eq "true") {
    print "clean database as input packages required...\n";
    say LOG_FILE "clean database as input packages required...";
    $tmp_value = "unclear";
    if ($jdbc_type eq "postgresql") {
        $tmp_value = &operation_clean_jdbc_postgresql();
    } elsif ($jdbc_type eq "mariadb") {
        $tmp_value = &operation_clean_jdbc_mariadb();
    }
    if ($tmp_value =~ "fail") {
        print "\n!!!ERROR clean database $tmp_value\n";
        say LOG_FILE "clean database $tmp_value\n";
    }
}


&show_step_information("deal with timestamp to some special service if needed",$step_index++);
if ( ($operation_type eq "deploy") || ($operation_type eq "upgrade") ) {
    if ( $service_name eq "ALL" ) {
        &handle_service_timestamp("COORDINATOR");
    } elsif ( $service_name eq "COORDINATOR") {
        &handle_service_timestamp($service_name);
    } else {
        
    }
} else {
    say LOG_FILE "Don't need to deal with service timestamp";
}

unless ( $service_name eq "DATABASE" ) {
    &show_step_information("process [$operation_type] operation to cluster hosts",$step_index++);
    system("java -noverify -Xms512m -Xmx512m -cp \".:$script_path/Deployment.jar\" py.deployment.client.OperationHandler $string_command_line");
}


&show_step_information("This is the end of storage [$operation_type] service [$service_name] operation",$step_index++);
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

sub usage() {
    my $usage = "Usage: \n";
    $usage = $usage."\t[-c|--command_operation\toperation:service name|all]\n";
    $usage = $usage."\t[-p|--pToDeployHost\tip-address[,ip-address...|:ip-address]]\n";
    $usage = $usage."\t[-g|--groupId\tgroup-id]\n";
    $usage = $usage."\t[-t|--test]\n";
    $usage = $usage."\t[-n|--noPM]\n";
    $usage = $usage."\t[-i|--ignore_update]\n";
    $usage = $usage."\t[-w|--withoutconfig]\n";
    $usage = $usage."\n";
    $usage = $usage."Example: \n";
    $usage = $usage."\t$0 -c deploy:all\n";
    $usage = $usage."\t$0 -c deploy:DIH -p 10.10.10.10 -t\n";
    $usage = $usage."\t$0 -c upgrade:DataNode --groupId=0\n";
    $usage = $usage."\t$0 -c wipeout:database\n";
    $usage = $usage."\t$0 -c wipeout:all -withoutconfig\n";
    $usage = $usage."See our user manual for detail.\n";

    return $usage;
}

sub check_xml_configuration_by_jdbc() {
    $tmp_value = `sed -n '/jdbc.url/p' $file_xml `;
    chomp(my $value_jdbc_url = $tmp_value);
    $tmp_value = `sed -n '/jdbc.driver.class/p' $file_xml `;
    chomp(my $value_jdbc_driver_class = $tmp_value);
    $tmp_value = `sed -n '/hibernate.dialect/p' $file_xml `;
    chomp(my $value_hibernate_dialect = $tmp_value);
    $tmp_value = `sed -n '/package.hbm/p' $file_xml `;
    chomp(my $value_package_hbm = $tmp_value);
    say LOG_FILE "jdbc configuration\n jdbc.url : $value_jdbc_url \njdbc.driver.class : $value_jdbc_driver_class 
    \nhibernate.dialect : \n$value_hibernate_dialect \npackage.hbm : $value_package_hbm";
    if ($jdbc_type eq "mariadb") {
        if ( $value_jdbc_url =~ "5432" ) {
            print "\nmariadb use port 3306\n";
            return "fail: mariadb port number should be : 3306";
        }
        unless ( $value_jdbc_driver_class =~ "mariadb" ) {
            print "\njdbc.driver.class should be : org.mariadb.jdbc.Driver\n";
            return "fail: mariadb driver class should be : org.mariadb.jdbc.Driver";
        }
        unless ( $value_hibernate_dialect =~ "MySQL5Dialect" ) {
            print "\nhibernate.dialect should be : org.hibernate.dialect.MySQL5Dialect\n";
            return "fail: mariadb hibernate dialect should be : org.hibernate.dialect.MySQL5Dialect";
        }
        unless ( $value_package_hbm =~ "mariadb" ) {
            print "\nhibernate.dialect should be : hibernate-config-mariadb\n";
            return "fail: mariadb hibernate dialect should be : hibernate-config-mariadb";
        }
    } elsif ($jdbc_type eq "postgresql") {
        if ( $value_jdbc_url =~ "3306" ) {
            print "\npostgresql use port 5432\n";
            return "fail: postgresql port number should be 5432";
        }
        unless ( $value_jdbc_driver_class =~ "postgresql" ) {
            print "\njdbc.driver.class should be org.postgresql.Driver\n";
            return "fail: postgresql driver class should be org.postgresql.Driver";
        }
        unless ( $value_hibernate_dialect =~ "PostgresCustomDialect" ) {
            print "\nhibernate.dialect should be py.dialect.PostgresCustomDialect\n";
            return "fail: postgresql hibernate dialect should be py.dialect.PostgresCustomDialect";
        }
        if ( $value_package_hbm =~ "mariadb" ) {
            print "\nhibernate.dialect should be : hibernate-config\n";
            return "fail: postgresql hibernate dialect should be : hibernate-config";
        }
    }

    return "pass";
}


sub operation_clean_jdbc_postgresql() {
    say LOG_FILE "get database host ip from file : $file_xml\n";
    my $database_ip = undef;
    $tmp_value = `sed -n '/controlandinfodb/p' $file_xml `;
    if ($tmp_value =~ "5432") {
        $tmp_value =~ /postgresql:\/\/(.*):5432/;
        $database_ip = $1;
    } else {
        say LOG_FILE "get controlandinfodb information: $tmp_value";
        return "fail: can't get controlandinfodb address";
    }

    unless ( defined $database_ip) {
        # body...
        say LOG_FILE "can't get database ip address from xml file";
        return "fail: can't get database ip address from xml file";
    } else {
        say LOG_FILE "get database ip address [$database_ip] from xml file";
    }

    (my $login_user, my $login_passwd) = &get_host_login_message();
    unless ( (defined $login_user) && (defined $login_passwd) ) {
        # body...
        return "fail: can't get host login information";
    }
    say LOG_FILE "get host login information: $login_user(user) $login_passwd(password)";

    $tmp_value = &Public_storage::operation_ping($database_ip);
    if ($tmp_value eq "fail" ) {
        say LOG_FILE "host $database_ip can't be accessed !";
        return "fail: host $database_ip can't be accessed !";
    }

    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
    my $ssh_connection = Net::OpenSSH->new( $database_ip, %$ssh_ops );
    (my $remote_message, my $err_info) = $ssh_connection->capture2({ timeout => 30 }, "find /usr -name psql");
    chomp($remote_message);
    my @tmp_array = split /\n/, $remote_message;
    my $fullpath_command_psql = undef;
    foreach (@tmp_array) {
        say LOG_FILE "check $_ is the right psql full path or not";
        (my $lastone_path, my $lasttwo_path) = (split /\//, $_)[-1,-2];
        if ( ($lastone_path eq "psql") && ($lasttwo_path eq "bin") ) {
            say LOG_FILE "psql command full path: $_";
            $fullpath_command_psql = $_;
            last;
        }
    }

    unless ( defined $fullpath_command_psql ) {
        # body...
        return "fail: can't find full path of psql command";
    }

    my @db_names = ( "fsserverdb", "controlandinfodb", "monitorserverdb");
    my $db_user = "py";
    foreach my $db_name (@db_names) {
        my $cmd_to_drop_all_tables =
            "sudo -u postgres $fullpath_command_psql -U postgres -d $db_name -c \"drop schema public cascade;\"";
        my $cmd_to_create_schema =
            "sudo -u postgres $fullpath_command_psql -U postgres -d $db_name -c \"create schema public authorization $db_user;\"";
        $ssh_connection->system("$cmd_to_drop_all_tables;$cmd_to_create_schema");
    }
    return "success";
}


sub operation_clean_jdbc_mariadb() {
    say LOG_FILE "get mariadb host ip from file : $file_xml\n";
    my $database_ip = undef;
    $tmp_value = `sed -n '/controlandinfodb/p' $file_xml `;
    if ($tmp_value =~ "3306") {
        $tmp_value =~ /mariadb:\/\/(.*):3306/;
        $database_ip = $1;
    } else {
        say LOG_FILE "get controlandinfodb information: $tmp_value";
        return "fail: can't get controlandinfodb address";
    }

    unless ( defined $database_ip) {
        # body...
        say LOG_FILE "can't get mariadb host ip address from xml file";
        return "fail: can't get mariadb host ip address from xml file";
    } else {
        say LOG_FILE "get mariadb host ip address [$database_ip] from xml file";
    }

    (my $login_user, my $login_passwd) = &get_host_login_message();
    unless ( (defined $login_user) && (defined $login_passwd) ) {
        # body...
        return "fail: can't get mariadb host login information";
    }
    say LOG_FILE "get mariadb host login information: $login_user(user) $login_passwd(password)";

    $tmp_value = &Public_storage::operation_ping($database_ip);
    if ($tmp_value eq "fail" ) {
        say LOG_FILE "mariadb host $database_ip can't be accessed !";
        return "fail: mariadb host $database_ip can't be accessed !";
    }

    my $package_type = &get_jdbc_installation_type($login_user, $login_passwd, $database_ip);
    say LOG_FILE "get mariadb installation type: $package_type";

    (my $jdbc_user, my $jdbc_passwd) = &get_jdbc_login_message();
    unless ( (defined $jdbc_user) && (defined $jdbc_passwd) ) {
        # body...
        return "fail: can't get mariadb host login information";
    }
    say LOG_FILE "get mariadb login information: $jdbc_user(user) $jdbc_passwd(password)";
    my $tmp_file = File::Spec->catfile($script_path, "clean_jdbc_mariadb.sh");
    system("sed -i 's/jdbc_user=.*/jdbc_user=$jdbc_user/' $tmp_file");
    system("sed -i 's/jdbc_password=.*/jdbc_password=$jdbc_passwd/' $tmp_file");

    my $fullpath_command_mysql = undef;
    if ($package_type eq "mariadb_rpm") {
        $fullpath_command_mysql = "/usr/bin/mysql";
    } else {
        $fullpath_command_mysql = "/usr/local/mysql/bin/mysql";
    }
    system("sed -i 's#jdbc_command_path=.*#jdbc_command_path=$fullpath_command_mysql#' $tmp_file");

    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
    my $ssh_connection = Net::OpenSSH->new( $database_ip, %$ssh_ops );
    $ssh_connection->scp_put({recursive => 1}, $tmp_file, "/tmp/clean_jdbc_mariadb.sh");
    $ssh_connection->system("bash /tmp/clean_jdbc_mariadb.sh");

    return "success";
}


sub get_jdbc_installation_type {
    (my $login_user, my $login_passwd, my $host_ip) = @_;
    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
    my $ssh = Net::OpenSSH->new($host_ip , %$ssh_ops);
    (my $remote_info, my $err_info) = $ssh->capture2({ timeout => 30 }, "rpm -qa | grep MariaDB-server 2>&1");
    if ($remote_info =~ "MariaDB-server") {
        return "mariadb_rpm";
    }
    return "mariadb_source";
}


sub get_host_login_message() {
    open my $configFileHandler, '<', $file_deploy_properties or die "unable to open configuration file $file_deploy_properties";
    my $properties = Config::Properties->new();
    $properties->load($configFileHandler);
    my $config_tree = $properties->splitToTree();
    close $configFileHandler;

    my $user = $config_tree->{'remote'}{'user'};
    $user =~ s/\s//g;
    my $passwd = $config_tree->{'remote'}{'password'};
    $passwd =~ s/\s//g;
    return ($user, $passwd);
}


sub get_jdbc_login_message() {
    open my $configFileHandler, '<', $file_deploy_properties or die "unable to open configuration file $file_deploy_properties";
    my $properties = Config::Properties->new();
    $properties->load($configFileHandler);
    my $config_tree = $properties->splitToTree();
    close $configFileHandler;

    my $user = $config_tree->{'jdbc'}{'user'};
    $user =~ s/\s//g;
    my $passwd = $config_tree->{'jdbc'}{'password'};
    $passwd =~ s/\s//g;
    return ($user, $passwd);
}


sub get_jdbc_type() {
    open my $configFileHandler, '<', $file_deploy_properties or die "unable to open configuration file $file_deploy_properties";
    my $properties = Config::Properties->new();
    $properties->load($configFileHandler);
    my $config_tree = $properties->splitToTree();
    close $configFileHandler;

    my $jdbc_type = $config_tree->{'jdbc'}{'type'};
    $jdbc_type =~ s/\s//g;
    return ($jdbc_type);
}


sub handle_service_timestamp {
    (my $service_name) = @_;
    my @array_timestamp = get_timestamp_list($service_name);
    my $choice_index = undef;
    if ( scalar(@array_timestamp) == 0 ) {
        say LOG_FILE "Can't find any package matched $service_name";
    } elsif ( scalar(@array_timestamp) == 1 ) {
        $choice_index = 1;
        &replace_configed_timestamp($service_name,$array_timestamp[$choice_index-1]);
    } else {
        my $index = 1;
        while ( $index <= scalar(@array_timestamp) ) {
            # body...
            say LOG_FILE "[$index] $array_timestamp[$index-1]";
            print "[$index] $array_timestamp[$index-1]\n";
            $index++;
        }
        print "type selection number: ";
        while () {
            chomp($choice_index = <STDIN>);
            $choice_index =~ /^\d+$/;
            if ( ($choice_index > 0 ) && ($choice_index <= scalar(@array_timestamp)) ) {
                say LOG_FILE "user input value is : $choice_index";
                last;
            }
        }
        print "choice $service_name package with timestamp $array_timestamp[$choice_index-1]\n";
        say LOG_FILE "choice $service_name package with timestamp $array_timestamp[$choice_index-1]";
        &replace_configed_timestamp($service_name,$array_timestamp[$choice_index-1]);
    }
}


sub replace_configed_timestamp(){
    (my $service_name, my $value_timestamp) = @_;
    my $running_command = undef;
    if ($service_name eq "COORDINATOR") {
        $running_command = "sed -i_bak 's/Coordinator.timestamp=.*/Coordinator.timestamp=$value_timestamp/g' $file_deploy_properties";
    } 
    say LOG_FILE "bakup and update $file_deploy_properties by command :\n $running_command";
    (system($running_command) == 0) or die "update $service_name timestamp to $value_timestamp failed.\n";
}


sub get_timestamp_list() {
    (my $service_name) = @_;
    my $directory_packages = File::Spec->catfile($script_path, "../packages");
    opendir (DH, $directory_packages);
    my @project_tars = readdir(DH);
    closedir DH;

    my @timestamps=();
    my @sorted_timestamps=();
    if ($service_name eq "COORDINATOR") {
        foreach my $project_tar(@project_tars) {
            if ($project_tar =~ m/coordinator/)  {
                # eg.XXX-coordinator-2.8.0-XXX-20220726135400.tar.gz
                my $timestamp = substr($project_tar, length($project_tar)-21, 14);
                # print "Coordinator $timestamp\n";
                push(@timestamps, $timestamp);
            }
        }
        @sorted_timestamps = sort @timestamps;
        say LOG_FILE "get COORDINATOR package timestamps [@sorted_timestamps]";
    } else {
        say LOG_FILE "$service_name shouldn't have any timestamp information";
    }
    return @sorted_timestamps;
}





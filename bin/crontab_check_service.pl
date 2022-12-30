#!/usr/bin/perl
# this scripts is used to check service status timely
# normally this file put to directory /opt/storage of all system nodes
#
# ----history-----
# 20171025 - mahaiqing - first version.
# 20220305 - mahaiqing - refactoring.

use File::Spec;
use constant SERVICE_STATUS_LOG_PATH     => "/var/log";

my $log_filename = "service-crontab-status";

# service and check times
# 0 - check forever
# -1 - check until status is OK
# F - don't need to check
my %service2checktimes = (
    deployment_daemon => 'F',
    zookeeper => '0',
    );

my $log_file = File::Spec->catfile(SERVICE_STATUS_LOG_PATH, $log_filename);
if ( -e "$log_file") {
    print "log file exists already. Check file size ...\n";
    my $file_size = (stat "log_file")[7];
    if ( $file_size >= 1048576) {
        system("echo -e 'As the file is bigger than 1M, remove old logs' > $log_file");
    }
} else {
    system("touch $log_file");
    print "It is going to create file($log_file) for service period checking\n";
}

my $date = localtime();
open(LOG_FILE, ">>$log_file") || die "\nCan't open log file $log_file to record results of opeation !! ";
select LOG_FILE;
$| = 1;

my $step_index = 0;
$step_index++;
&show_step_information("This is going to check host service status for storage product",$step_index);
say LOG_FILE "\n\n";

my $tmp_results = undef;
$step_index++;
&show_step_information("This is going to check service : zookeeper ",$step_index);
&check_service_zookeeper();

$step_index++;
&show_step_information("This is going to check service : deployment_daemon ",$step_index);
&check_service_deployment_daemon();

$step_index++;
&show_step_information("This is the end of check service status for storage product",$step_index);
say LOG_FILE "================================================================================";
# print "================================================================================\n";
close LOG_FILE;
exit 0;


sub show_step_information {
    (my $message, my $step_index) = @_;
    chomp(my $timestamp=localtime());
    say LOG_FILE "-------------------------------------------------------------------------------";
    say LOG_FILE "step $step_index : $message [$timestamp]";
    say LOG_FILE "-------------------------------------------------------------------------------";
    # print "step $step_index : $message [$timestamp]\n";
}


sub check_service_zookeeper {
    my $directory_zookeeper = "/opt/zookeeper";

    unless ( -d $directory_zookeeper ) {
        # body...
        say LOG_FILE "There is no working directory for zookeeper, don't need to check this service";
        return;
    }

    if ($service2checktimes{"zookeeper"} eq 'F') {
        print LOG_FILE "according to settings, service(zookeeper) don't need to check on current host.\n";
        return;
    }

    my $file_zkServer = File::Spec->catfile($directory_zookeeper, "zookeeper-3.4.6/bin/zkServer.sh");
    my $running_command = undef;
    $tmp_results = `netstat -npl | grep 2181 2>&1`;
    chomp($tmp_results);
    my @tmp_array = split /\n/, $tmp_results;
    my $flag_starup = "false";
    foreach(@tmp_array) {
        if ($_ =~ "java") {
            say LOG_FILE "zookeeper process information: \n$_";
            $flag_starup = "true";
            last;
        }
    }
    if ( $flag_starup eq "true" ) {
        say LOG_FILE "It seems service(zookeeper) is running well.";
        $running_command = "$file_zkServer status 2>&1 | grep Mode";
        $tmp_results = `$running_command`;
        chomp($tmp_results);
        say LOG_FILE "zookeeper status information: \n$tmp_results";
        return;
    } else {
        say LOG_FILE "zookeeper port 2181 couldn't be detected. Try to startup it ";
    }
    
    $running_command = "$file_zkServer stop";
    say LOG_FILE "stop zookeeper by command: $running_command";
    system("$running_command");

    my $directory_data_version2 = File::Spec->catfile($directory_zookeeper, "data/version-2");
    if ( -d $directory_data_version2 ) {
        say LOG_FILE "delete files under data directory ($directory_data_version2)";
        system("rm -rf $directory_data_version2");
    }

    my $directory_logs_version2 = File::Spec->catfile($directory_zookeeper, "logs/version-2");
    if ( -d $directory_logs_version2 ) {
        say LOG_FILE "delete files under log directory ($directory_logs_version2)";
        system("rm -rf $directory_logs_version2");
    }

    my $file_server_pid = File::Spec->catfile($directory_zookeeper, "data/zookeeper_server.pid");
    if ( -f $file_server_pid ) {
        say LOG_FILE "delete zookeeper pid file ($file_server_pid)";
        unlink $file_server_pid;
    }

    my $file_zookeeper_cfg = File::Spec->catfile($directory_zookeeper, "zookeeper.cfg");
    my $file_zoo_cfg = File::Spec->catfile("$directory_zookeeper", "zookeeper-3.4.6/conf/zoo.cfg");
    say LOG_FILE "copy file ($file_zookeeper_cfg) to file ($file_zoo_cfg)";
    system("cp -f $file_zookeeper_cfg $file_zoo_cfg");

    $running_command = "$file_zkServer start &";
    say LOG_FILE "start zookeeper by command: $running_command";
    system("$running_command");

    sleep(5);
    say LOG_FILE "check zookeeper service status ";
    $tmp_results = `netstat -npl | grep 2181 2>&1`;
    chomp($tmp_results);
    @tmp_array = split /\n/, $tmp_results;
    $flag_starup = "false";
    foreach(@tmp_array) {
        if ($_ =~ "java") {
            say LOG_FILE "zookeeper process information: \n$_";
            $flag_starup = "true";
            last;
        }
    }
    if ( $flag_starup eq "true" ) {
        say LOG_FILE "It seems service(zookeeper) is running well now";
        $running_command = "$file_zkServer status 2>&1 | grep Mode";
        $tmp_results = `$running_command`;
        chomp($tmp_results);
        say LOG_FILE "zookeeper status information: \n$tmp_results";
        return;
    } else {
        say LOG_FILE "ERROR : zookeeper port 2181 still couldn't be detected.";
    }
    return;
}


sub check_service_deployment_daemon {
    if ($service2checktimes{"deployment_daemon"} eq 'F') {
        print LOG_FILE "according to settings, service(deployment_daemon) don't need to check on current host.\n";
        return;
    }

    $tmp_results = `netstat -npl | grep 10002 2>&1`;
    chomp($tmp_results);
    my @tmp_array = split /\n/, $tmp_results;
    my $flag_starup = "false";
    foreach(@tmp_array) {
        if ($_ =~ "java") {
            say LOG_FILE "deployment_daemon process information: \n$_";
            $flag_starup = "true";
            last;
        }
    }
    if ( $flag_starup eq "true" ) {
        say LOG_FILE "It seems service(deployment_daemon) is running well";
        return;
    } else {
        say LOG_FILE "deployment_daemon port 10002 couldn't be detected.";
        say LOG_FILE "WARN:according to design, service deployment_daemon don't need to startup by this script......";
    }

}



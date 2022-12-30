#!/usr/bin/perl
# this scripts is as one part of storage system configuration files
# normally this file will be put to directory /opt/storage of all system nodes
#
# ----history-----
# 20191107 - mahaiqing - reconfiguration.
# 20200305 - mahaiqing - print out zookeeper service information.
use strict;
use warnings;

use File::Spec;


my $log_directory = "/var/log";
unless ( -d "$log_directory" ) {
    system("mkdir -p $log_directory");
}

my $log_file=File::Spec->catfile($log_directory,"storage-startup.log");
my $time_stamp = localtime();
if (-e "$log_file") {
    print "the log file for storage product envrionment prepare exists already. Check the file size ...\n";
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
&show_step_information("This is going to check host envrionment for storage product",$step_index);
&check_host_environments();

$step_index++;
&show_step_information("This is going to check service crond on current host",$step_index);
&check_service_crond();

$step_index++;
&show_step_information("This is going to prepare pyd files",$step_index);
&prepare_pyd_files();


$step_index++;
&show_step_information("This is going to prepare service zookeeper ",$step_index);
&start_zookeeper();


$step_index++;
&show_step_information("This is going to start service deployment_daemon ",$step_index);
&start_deployment_daemon();


$step_index++;
&show_step_information("sleep some time to check service deployment_daemon ",$step_index);
sleep(20);
my $check_results = &check_deployment_daemon();
if ( $check_results =~ "fail" ) {
    print "ERROR. deployment_daemon doesn't startup successfully as expected!!\n";
    say LOG_FILE "ERROR. deployment_daemon doesn't startup successfully as expected!!";
} else {
    say LOG_FILE "deployment_daemon startup successfully as expected!!";
}


$step_index++;
&show_step_information("This is the end of prepare envrionment for storage product as host startup",$step_index);
say LOG_FILE "================================================================================";
print "================================================================================\n";
close LOG_FILE;
exit 0;


sub check_deployment_daemon {
    my $tmp_results = `ps -ef | grep deployment_daemon | grep dd.launcher 2>&1`;
    chomp($tmp_results);
    unless ($tmp_results =~ "java") {
        return "fail: no process for service deployment_daemon";
    } else {
        say LOG_FILE "service deployment_daemon process information: $tmp_results";
    }

    $tmp_results = `netstat -npl | grep 000`;
    say LOG_FILE "checking netstat results is : $tmp_results.\n";
    if ( $tmp_results =~ /10002/ ) {
        say LOG_FILE "The target port 10002 for service deployment_daemon exists already.\n";
    } else {
        return "fail: There is no target port for service deployment_daemon";

    }

    return "success: service deployment_daemon has already startup";
}



sub start_deployment_daemon {
    unless (-d "/var/deployment_daemon/packages" ) {
        # body...
        print "ERROR: there is no deployment_daemon packages directory. Maybe the service hasn't been deployed yet !!\n";
        say LOG_FILE "ERROR: there is no deployment_daemon packages directory. Maybe the service hasn't been deployed yet !!";
        return;
    }

    opendir  DIR_PACKAGES, "/var/deployment_daemon/packages";
    my $directory_name = undef;
    my $service_number = 0;
    foreach (readdir DIR_PACKAGES) {
        if ( /deployment_daemon/ ) {
            $directory_name = $_;
            say LOG_FILE "get directory_name($directory_name) for service";
            $service_number++;
        }
    }
    if ( $service_number == 0 ) {
        print "there is no deployment_daemon working directory\n";
        say LOG_FILE "there is no deployment_daemon working directory";
        return;
    } elsif ( $service_number > 1) {
        print "ERROR. there are too many working directory matched deployment_daemon. Can't deceide which one should be used\n";
        say LOG_FILE "ERROR. there are too many working directory matched deployment_daemon. Can't deceide which one should be used";
        return;
    }

    my $file_serice_startup = File::Spec->catfile("/var/deployment_daemon/packages", $directory_name,"bin/startup.sh");
    unless ( -f $file_serice_startup ) {
        # body...
        print "ERROR. there is no launcher file ($file_serice_startup) for deployment_daemon\n";
        say LOG_FILE "ERROR. there is no launcher file ($file_serice_startup) for deployment_daemon";
        return;
    }

    system("$file_serice_startup &");
    say LOG_FILE "start service deployment_daemon ......";
    sleep(5);
}


sub start_zookeeper {
    my $directory_zookeeper = "/opt/zookeeper";
    unless ( -d $directory_zookeeper ) {
        # body...
        say LOG_FILE "There is no working directory for zookeeper, don't need to start this service";
        print "There is no working directory for zookeeper, don't need to start this service\n";
        return;
    }
    my $file_zkServer = File::Spec->catfile("$directory_zookeeper", "zookeeper-3.4.6/bin/zkServer.sh");
    my $running_command = "$file_zkServer stop";
    say LOG_FILE "stop zookeeper by command: $running_command";
    system("$running_command");

    my $directory_data_version2 = File::Spec->catfile("$directory_zookeeper", "data/version-2");
    if ( -d $directory_data_version2 ) {
        say LOG_FILE "delete files under data directory ($directory_data_version2)";
        system("rm -rf $directory_data_version2");
    }

    my $directory_logs_version2 = File::Spec->catfile("$directory_zookeeper", "logs/version-2");
    if ( -d $directory_logs_version2 ) {
        say LOG_FILE "delete files under log directory ($directory_logs_version2)";
        system("rm -rf $directory_logs_version2");
    }

    my $file_server_pid = File::Spec->catfile("$directory_zookeeper", "data/zookeeper_server.pid");
    if ( -f $file_server_pid ) {
        say LOG_FILE "delete zookeeper pid file ($file_server_pid)";
        unlink $file_server_pid;
    }

    my $file_zookeeper_cfg = File::Spec->catfile("$directory_zookeeper", "zookeeper.cfg");
    my $file_zoo_cfg = File::Spec->catfile("$directory_zookeeper", "zookeeper-3.4.6/conf/zoo.cfg");
    say LOG_FILE "copy file ($file_zookeeper_cfg) to file ($file_zoo_cfg)";
    system("cp -f $file_zookeeper_cfg $file_zoo_cfg");


    $running_command = "$file_zkServer start &";
    say LOG_FILE "start zookeeper by command: $running_command";
    system("$running_command");

    sleep(5);
    say LOG_FILE "check zookeeper service status";
    my $flag_starup = "false";
    my @tmp_array = undef;
    for (my $tried_times = 0; $tried_times < 3; $tried_times++) {
        say LOG_FILE "try to check zookeeper status $tried_times times";
        my $tmp_results = `netstat -npl | grep 2181 2>&1`;
        chomp($tmp_results);
        @tmp_array = split /\n/, $tmp_results;
        foreach(@tmp_array) {
            if ($_ =~ "java") {
                say LOG_FILE "zookeeper process information: $_";
                $flag_starup = "true";
                last;
            }
        }

        if ( $flag_starup eq "true") {
            last;
        } else {
            say LOG_FILE "zookeeper service is not start up successfully. try to start again by command : $running_command";
            system("$running_command");
            sleep(5);
        }
    }
    if ($flag_starup eq "true") {
        say LOG_FILE "zookeeper service has been startup";
    } else {
        say LOG_FILE "after tried many times, zookeeper can't startup at last";
    }

}



sub prepare_pyd_files {
    my $tmp_results = `lsmod | grep pyd `;
    chomp($tmp_results);
    if ($tmp_results =~ "pyd" ) {
        system("rmmod pyd");
        say LOG_FILE "remove pyd module";
    }

    my $file_pyd_ko = "/opt/pyd/pyd.ko";
    unless ( -f $file_pyd_ko ) {
        # body...
        say LOG_FILE "ERROR: there is no expected pyd ko file($file_pyd_ko)";
        return;
    } else {
        system("insmod $file_pyd_ko nbds_max=16");
        $tmp_results = `cat /sys/module/pyd/version`;
        chomp($tmp_results);
        say LOG_FILE "insmod pyd.ko, and the version is :$tmp_results";
    }

    my $file_pyd_client = "/opt/pyd/pyd-client";
    unless ( -f $file_pyd_client ) {
        # body...
        say LOG_FILE "ERROR: there is no expected pyd client file($file_pyd_client)";
        return;
    } else {
        $tmp_results = (stat "$file_pyd_client")[2];
        unless ( $tmp_results == "33261") {
            # body...
            system("chmod a+x $file_pyd_client");
            say LOG_FILE "add x rights to file $file_pyd_client";
        }
        $tmp_results = (stat "$file_pyd_client")[2];
        say LOG_FILE "Access status of file($file_pyd_client) is(expected value is 33261): $tmp_results";
    }
}


sub check_service_crond {
    my $os_name = `cat /etc/os-release | grep 'PRETTY_NAME' 2>&1`;
    chomp($os_name);
    say LOG_FILE "current host OS information is: $os_name";
    my $tmp_results = undef;
    if ( $os_name =~ "CentOS" || ($os_name =~ "NeoKylin") ) {
        $tmp_results = `systemctl status crond.service`;
        chomp($tmp_results);
        say LOG_FILE "service crond status as follows:\n$tmp_results\n";
        $tmp_results =~ m/Active:(.*)ago/;
        unless ( $1 =~ /running/ ) {
            say LOG_FILE "restart service crond on current  host";
            system("service restart crond.service");
        }
    } elsif ( $os_name =~ "Ubuntu" ) {
        $tmp_results = `service cron status`;
        chomp($tmp_results);
        say LOG_FILE "service crond status as follows:\n$tmp_results\n";
        $tmp_results =~ m/Active:(.*)ago/;
        unless ( $1 =~ /running/ ) {
            say LOG_FILE "restart service crond on current  host";
            system("service cron restart");
        }
    }
}


sub check_host_environments {
    my $tmp_results = `whereis java 2>&1`;
    chomp($tmp_results);
    if ( (split /:/, $tmp_results)[0] eq "") {
        print "There is no java configuration on current host\n";
        say LOG_FILE "ERROR: There is no java configuration on current host";
    } else {
        $tmp_results = `java -version 2>&1 `;
        chomp($tmp_results);
        say LOG_FILE "current host java information: $tmp_results";
    }
}

sub show_step_information {
    (my $message, my $step_index) = @_;
    chomp(my $timestamp=localtime());
    say LOG_FILE "-------------------------------------------------------------------------------";
    print LOG_FILE "step $step_index : $message [$timestamp]\n";
    say LOG_FILE "-------------------------------------------------------------------------------";
    print "step $step_index : $message [$timestamp]\n";
}


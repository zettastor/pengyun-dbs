#!/usr/bin/perl -X
#
# 20191107 - mahaiqing - reconstruction.
# 20220305 - mahaiqing - add crontab_check_service.pl
# 20220317 - mahaiqing - add crontab_check_host_space.pl
# 20220629 - mahaiqing - remove update platform operation.
#                        update platform operation would be done during update_system_config.pl

use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin/../lib/perl5";
use lib "$RealBin";

use Config::Properties;
use File::Basename;
use File::Spec;
use Getopt::Long;
use Net::OpenSSH;
use POSIX ":sys_wait_h";

use Public_storage;

my $script_path = $RealBin;
my $directory_deploy = dirname($script_path);
my $log_directory=File::Spec->catfile($directory_deploy, "logs");
unless ( -d "$log_directory" ) {
    print "\nthere is no directory($log_directory) to save log, create one\n";
    # exit 1;
    system("mkdir -p $log_directory");
}

my $log_file = File::Spec->catfile($log_directory,"storage-deployment-deploy.log");
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
&show_step_information("This is going to do deployment_daemon service operation",$step_index);
my $choice = undef;
my $operation = undef;
my $ignoreConfig = undef;
GetOptions("operation=s" => \$operation, "ignore_config" => \$ignoreConfig);
unless ( defined $operation ) {
    print "\n please input the operation: deploy or wipeout. \n";
    die usage_deploy();
}
$operation = lc($operation);
unless ($operation eq 'deploy' || $operation eq 'wipeout') {
    print "please input the right operation : deploy or wipeout";
    die usage_deploy();
}
say LOG_FILE "This is going to do $operation operation";

unless ( defined $ignoreConfig ) {
    # body...
    print("*** Do you want to update configuration for all services?[y/n] ") and $choice = <STDIN> and chomp $choice until $choice eq 'y' or $choice eq 'n';
    unless ( $choice eq 'n' ) {
        say LOG_FILE "update local packages configuration";
        system ( "perl $script_path/update_system_config.pl" );
        print "--------- update configuration for all services finished ! --------\n";
        say LOG_FILE "--------- update configuration for all services finished ! --------";
    }
} else {
    say LOG_FILE "ignore local packages configuration according to input parameters";
}


my $file_deploy = File::Spec->catfile($directory_deploy, 'config/deploy.properties');
$step_index++;
&show_step_information("This is going to get information from file config/deploy.properties",$step_index);
### load config file deploy.properties

open my $file_handler_deploy, '<', $file_deploy
    or die "unable to open configuration file deploy.properties";

my $deploy_properties = Config::Properties->new();
$deploy_properties->load($file_handler_deploy);
my $config_tree_deploy_properties = $deploy_properties->splitToTree();
close $file_handler_deploy;

my $login_user = $config_tree_deploy_properties->{'remote'}{'user'};
$login_user =~ s/\s//g;
my $login_passwd = $config_tree_deploy_properties->{'remote'}{'password'};
$login_passwd =~ s/\s//g;
my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
say LOG_FILE "from the config file, the login information to hosts is: $login_user(user), $login_passwd(password)";

my $directory_deployment = $config_tree_deploy_properties->{'deployment'}{'directory'};
my $service_name = "deployment_daemon";
# my $service_thread_amount = $config_tree_deploy_properties->{'deployment'}{'thread'}{'amount'};
# $service_thread_amount =~ s/\s//g;
# if ( $service_thread_amount == 0 ) {
#     say LOG_FILE "as the value of deployment.thread.amount is not specified, so use the default value 1. \n";
#     $service_thread_amount = 1;
# }
# In normal case, this parameter isn't needed. deployment_daemon service is seperate from each host.

my $service_deploy_port = $config_tree_deploy_properties->{$service_name}{'deploy'}{'port'};
$service_deploy_port =~ s/\s//g;
my $service_remote_timeout = $config_tree_deploy_properties->{$service_name}{'remote'}{'timeout'};
$service_remote_timeout =~ s/\s//g;
say LOG_FILE "from the config file, the settings related to deployment_daemon as:";
say LOG_FILE "\tdirectory: $directory_deployment\n\tport:$service_deploy_port\n\ttimeout:$service_remote_timeout";


my $hostListStr = $config_tree_deploy_properties->{$service_name}{'deploy'}{'host'}{'list'};
my @array_service_host = &Public_storage::get_ip_array_from_string($hostListStr);
if ( ("$array_service_host[0]" eq "0x0006") or ("$array_service_host[0]" eq "0x0007") ) {
    print "ERROR. ip format is not right to get service($service_name) deploy host list\n";
    say LOG_FILE "ERROR. ip format is not right to get service($service_name) deploy host list";
    return ;
}
my $host_count = scalar(@array_service_host);
say LOG_FILE "from the config file, service($service_name) hosts number($host_count), list information($hostListStr)";


$step_index++;
&show_step_information("This is going to do $service_name $operation operation on all hosts",$step_index);
if ($operation eq 'deploy') {
    &operation_service_deploy();
} elsif ($operation eq 'wipeout') {
    &operation_service_wipeout();
} else {
    print "ERROR. current operation $operation can't deal with right now.\n";
    say LOG_FILE "ERROR. current operation $operation can't deal with right now.";
}


$step_index++;
&show_step_information("This is the end of deployment_daemon service operation",$step_index);
say LOG_FILE "================================================================================";
print "================================================================================\n";
close LOG_FILE;
exit 0;



sub operation_service_wipeout {
    foreach my $each_host (@array_service_host) {
        say LOG_FILE "Try to wipeout $service_name on host $each_host";
        my $ping_result =  &Public_storage::operation_ping($each_host);
        if ( $ping_result eq "fail" ) {
            print "The wipeout operation fail as host $each_host can't be accessed !!!\n";
            say LOG_FILE "The wipeout operation fail as host $each_host can't be accessed !!!\n";
            next;
        }

        my $ssh = Net::OpenSSH->new($each_host, %$ssh_ops);
        $ssh->error and die "Couldn't establish SSH connection:".$ssh->error;
        my $remote_message = &Public_storage::check_remote_path_exists($login_user, $login_passwd, $each_host, File::Spec->catfile($directory_deployment,"bin/deployment-daemon.pl"));
        if ( $remote_message =~ "No such file" ) {
            say LOG_FILE "There is no bin/deployment_daemon.pl under directory $directory_deployment on host $each_host. Maybe has been wipeout berfore, check the next \n";
            next;
        }

        my $running_command = "cd $directory_deployment; /usr/bin/perl bin/deployment-daemon.pl -o wipeout";
        say LOG_FILE "wipeout $service_name on host $each_host by command($running_command)";
        $ssh->system($running_command);
    }

    sleep(10);

    my @array_host_not_clean = ();
    foreach my $each_host (@array_service_host) {
        say LOG_FILE "check $service_name on host $each_host has been wipeout clean or not";
        my $ping_result =  &Public_storage::operation_ping($each_host);
        if ( $ping_result eq "fail" ) {
            print "The wipeout operation fail as host $each_host can't be accessed !!!\n";
            say LOG_FILE "The wipeout operation fail as host $each_host can't be accessed !!!\n";
            push @array_host_not_clean, $each_host;
            next;
        }

        my $ssh = Net::OpenSSH->new($each_host, %$ssh_ops);
        $ssh->error and die "Couldn't establish SSH connection:".$ssh->error;
        my $remote_message = &Public_storage::check_remote_path_exists($login_user, $login_passwd, $each_host, File::Spec->catfile($directory_deployment,"packages"));
        if ( $remote_message eq "directory" ) {
            say LOG_FILE "directory $directory_deployment packages on host $each_host still exists. wipeout operation is failed \n";
            push @array_host_not_clean, $each_host;
            next;
        }

        # dd.Launcher  -- deployment_daemon service
        # dd-launcher  -- deployment_daemon ProcessManager
        ($remote_message, my $err_info) = $ssh->capture2({ timeout => 30 }, "ps -ef | grep deployment_daemon | grep dd.Launcher 2>&1");
        if ($remote_message =~ "java") {
            say LOG_FILE "service $service_name  java process on host $each_host still exists. wipeout operation is failed \n";
            push @array_host_not_clean, $each_host;
            next;
        }

        ($remote_message, my $err_info) = $ssh->capture2({ timeout => 30 }, "netstat -npl | grep $service_deploy_port 2>&1");
        if ($remote_message =~ $service_deploy_port) {
            say LOG_FILE "service $service_name  port $service_deploy_port on host $each_host still exists. wipeout operation is failed \n";
            push @array_host_not_clean, $each_host;
            next;
        }
    }

    if ( scalar(@array_host_not_clean) == 0 ) {
        print "wipeout operation on all hosts are successfully.\n";
        say LOG_FILE "wipeout operation on all hosts are successfully.\n";

    } else {
        print "ERROR.wipeout operation on following hosts: @array_host_not_clean are not successfully.\n";
        say LOG_FILE "ERROR.wipeout operation on following hosts: @array_host_not_clean are not successfully.\n";
    }
}


sub wait_service_come_up {
    my ($deploy_host) = (@_);
    foreach my $try_count ( 1..($service_remote_timeout/2000) ){
        my $ping_result =  &Public_storage::operation_ping($deploy_host);
        if ( $ping_result eq "fail" ) {
            print "Waiting service $service_name fail as host $deploy_host can't be accessed !!!\n";
            say LOG_FILE "Waiting service $service_name fail as host $deploy_host can't be accessed !!!";
            next;
        }

        my $ssh = Net::OpenSSH->new($deploy_host, %$ssh_ops);
        $ssh->error and die "Couldn't establish SSH connection:".$ssh->error;
        my $running_command = "cd $directory_deployment; /usr/bin/perl bin/deployment-daemon.pl -o status";
        say LOG_FILE "check $service_name status by command($running_command)";
        (my $remote_message, my $err_info) = $ssh->capture2({ timeout => 30 }, "$running_command");
        if ($remote_message =~ "ACTIVE") {
            say LOG_FILE "service $service_name on $deploy_host is ACTIVE.";
            last;
        } else {
            print "!!! try $try_count times, status of $service_name on $deploy_host is ACTIVATING. It's expected to ACTIVE !\n";
            say LOG_FILE "!!! try $try_count times, status of $service_name on $deploy_host is ACTIVATING. It's expected to ACTIVE !";
        }
        sleep 2;
    }
}



sub deploy_service_to_host {
    # my ($quote_deploy_hosts, $service_package_name) = (@_);
    my ($deploy_host, $service_package_name) = (@_);
    my $subdir_service_bin           =  File::Spec->catfile($directory_deployment, "bin");
    my $subdir_service_log           =  File::Spec->catfile($directory_deployment, "logs");
    my $subdir_service_tars          =  File::Spec->catfile($directory_deployment, "tars");
    my $subdir_service_untarpackages =  File::Spec->catfile($directory_deployment, "_packages");
    my $subdir_service_packages      =  File::Spec->catfile($directory_deployment, "packages");


    print "deploy $service_name on host $deploy_host \n";
    say LOG_FILE "deploy $service_name on host $deploy_host ";
    my $ping_result =  &Public_storage::operation_ping($deploy_host);
    if ( $ping_result eq "fail" ) {
        print "The deploy operation fail as host $deploy_host can't be accessed !!!\n";
        say LOG_FILE "The deploy operation fail as host $deploy_host can't be accessed !!!\n";
        next;
    }

    my $ssh = Net::OpenSSH->new($deploy_host, %$ssh_ops);
    $ssh->error and die "Couldn't establish SSH connection:".$ssh->error;
    my $os_info = &Public_storage::get_host_os_info($login_user, $login_passwd, $deploy_host);
    say LOG_FILE "remote host $deploy_host OS information is:$os_info\n";
    say LOG_FILE "create necessary directories on host $deploy_host";
    $ssh->system("
        mkdir -p '/opt/storage';
        mkdir -p $directory_deployment;
        mkdir -p $subdir_service_bin;
        mkdir -p $subdir_service_log;
        mkdir -p $subdir_service_tars;
        mkdir -p $subdir_service_untarpackages;
        mkdir -p $subdir_service_packages") or die "remote command create directories failed: " . $ssh->error;
    $ssh->scp_put({recursive => 1}, File::Spec->catfile($script_path, "deployment-daemon.pl"), $subdir_service_bin);
    $ssh->error and die "scp put1 $subdir_service_bin:".$ssh->error;
    $ssh->scp_put({recursive => 1}, File::Spec->catfile($directory_deploy, "packages",$service_package_name), $subdir_service_tars);
    $ssh->error and die "scp put2 $subdir_service_tars:".$ssh->error;
    say LOG_FILE "put file storectl to directory(/opt/storage) on host $deploy_host";
    $ssh->scp_put({recursive => 1}, File::Spec->catfile($RealBin,"storectl.pl"),"/opt/storage");
    $ssh->error and die "scp put3 $RealBin storectl:".$ssh->error;
    $ssh->scp_put({recursive => 1}, File::Spec->catfile($RealBin,"getProcessPM.sh"),"/opt/storage");
    $ssh->error and die "scp put4 $RealBin getProcessPM.sh:".$ssh->error;
    $ssh->scp_put({recursive => 1}, File::Spec->catfile($RealBin,"crontab_check_service.pl"),"/opt/storage");
    $ssh->error and die "scp put5 $RealBin crontab_check_service.pl:".$ssh->error;
    $ssh->scp_put({recursive => 1}, File::Spec->catfile($RealBin,"crontab_check_host_space.pl"),"/opt/storage");
    $ssh->error and die "scp put6 $RealBin crontab_check_host_space.pl:".$ssh->error;

    my $directory_so_files = undef;
    my $value_platform = undef;
    if ( $os_info =~ "CentOS" ) {
        $directory_so_files = File::Spec->catfile($directory_deploy, "resources");
        $value_platform = "x86_64";
    } else {
        $directory_so_files = File::Spec->catfile($directory_deploy, "resources/binary",$os_info);
        $value_platform = $os_info;
    }
    say LOG_FILE "remote host $deploy_host platform information is:$value_platform\n";
    unless (-d $directory_so_files) {
        # body...
        print "ERROR. There is no so files for host $deploy_host which OS is: $os_info";
        say LOG_FILE "ERROR. There is no so files for host $deploy_host which OS is: $os_info";
        next;
    } else {
        say LOG_FILE "put so files under $directory_so_files to  host $deploy_host directory(/usr/lib)";
    }

    opendir(DIR_SO, $directory_so_files);
    my $file_so = undef;
    foreach ( readdir(DIR_SO)) {
        # body...
        if ( $_ eq "." || $_ eq "..") {
            next;
        }
        if ( $_ =~ "libjnotify" ) {
            $file_so = File::Spec->catfile($directory_so_files, $_);
            $ssh->scp_put({recursive => 1}, $file_so, "/usr/lib/libjnotify.so");
            $ssh->error and die "scp put4 $directory_deploy libjnotify:".$ssh->error;
        } elsif ( $_ =~ "liblinux-async-io" ) {
            $file_so = File::Spec->catfile($directory_so_files, $_);
            $ssh->scp_put({recursive => 1}, $file_so, "/usr/lib/liblinux-async-io.so");
            $ssh->error and die "scp put5 $directory_deploy liblinux-async-io:".$ssh->error;
        } elsif ( $_ =~ "libudpServer" ) {
            $file_so = File::Spec->catfile($directory_so_files, $_);
            $ssh->scp_put({recursive => 1}, $file_so, "/usr/lib/libudpServer.so");
            $ssh->error and die "scp put6 $directory_deploy libudpServer:".$ssh->error;
        }
    }
    closedir DIR_SO;

    my $running_command = "cd $directory_deployment; nohup /usr/bin/perl bin/deployment-daemon.pl -o launch > /dev/null 2>&1 ";
    say LOG_FILE "launch $service_name by command: $running_command on host $deploy_host";
    $ssh->system($running_command);

    (my $remote_results, my $err_info) = $ssh->capture2({ timeout => 30 }, "grep 'crontab_check_service' /etc/crontab 2>&1");
    my $crontab_setting_service = "*/2 * * * * root perl /opt/storage/crontab_check_service.pl";
    if ( $remote_results =~ "crontab_check_service" ) {
        $running_command = "sed -i 's#.*crontab_check_service.*#$crontab_setting_service#g' /etc/crontab";
        say LOG_FILE "update crontab settings about service checking [$running_command]";
        $ssh->system($running_command);
    } else {
        $running_command = "sed -i '\$ a $crontab_setting_service' /etc/crontab";
        say LOG_FILE "add crontab settings about service checking [$running_command]";
        $ssh->system($running_command);
        $ssh->system("systemctl enable crond.service");
    }
    ($remote_results, $err_info) = $ssh->capture2({ timeout => 30 }, "grep 'crontab_check_host_space' /etc/crontab 2>&1");
    $crontab_setting_service = "17 03 * * * root perl /opt/storage/crontab_check_host_space.pl";
    if ( $remote_results =~ "crontab_check_host_space" ) {
        $running_command = "sed -i 's#.*crontab_check_host_space.*#$crontab_setting_service#g' /etc/crontab";
        say LOG_FILE "update crontab settings about host space checking [$running_command]";
        $ssh->system($running_command);
    } else {
        $running_command = "sed -i '\$ a $crontab_setting_service' /etc/crontab";
        say LOG_FILE "add crontab settings about host space checking [$running_command]";
        $ssh->system($running_command);
        $ssh->system("systemctl enable crond.service");
    }
    $ssh->system("systemctl restart crond.service");

    return $value_platform;
}


sub operation_service_deploy {
    my $directory_packages = File::Spec->catfile($directory_deploy, "packages");
    unless ( -d $directory_packages ) {
        # body...
        print "ERROR. There is no packages directory under path $directory_deploy\n";
        say LOG_FILE "ERROR. There is no packages directory under path $directory_deploy";
        return;
    }
    opendir(DIR_LOGS, File::Spec->catfile($directory_deploy, "logs"));
    foreach ( readdir(DIR_LOGS)) {
        # body...
        if ( $_ eq "." || $_ eq "..") {
            next;
        }
        if ( $_ =~ "platform_") {
            unlink File::Spec->catfile($directory_deploy, "logs", $_) || print "can't delete file $_";
        }
    }
    closedir DIR_LOGS;

    opendir(DIR, $directory_packages);
    my $service_package_name = undef;
    foreach ( readdir(DIR)) {
        # body...
        unless ( $_ =~ 'tar.gz' ) { next; }
        if ( $_ =~ $service_name ) {
            $service_package_name = $_;
            say LOG_FILE "find service $service_name package file with name: $_";
            last;
        }
    }
    closedir DIR;
    unless (defined $service_package_name) {
        # body...
        print "ERROR. There is no package file match service $service_name \n";
        say LOG_FILE "ERROR. There is no package file match service $service_name";
        return;
    }


    my $host_number_total = scalar(@array_service_host);
    my $host_number_simultaneity = $host_number_total+1;
    my $host_number_ongoing = 0;
    my $host_number_finished = 0;
    my $host_number_timeout = 0;
    # save pid and host ip.  (key : pid, value : host ip)
    my %pid_to_host = ();
    # save pid and start timestamp.  (key : pid, value : start time-seconds)
    my %pid_to_start_time = ();
    $SIG{CHLD} = sub{$host_number_ongoing--};
    for (my $index=0; $index<$host_number_total;$index++) {
        my $pid = fork();
        if ( !defined($pid) ) {
            say LOG_FILE "Error in fork: $!. This is going to deal with host $array_service_host[$index]";
            print "Error in fork: $!. This is going to deal with host $array_service_host[$index]\n";
            exit 1;
        }
        if ( $pid == 0 ) {
            $time_stamp = localtime();
            print "host index $index -- begin to deploy $service_name on host: $array_service_host[$index] at [$time_stamp]\n";
            say LOG_FILE "host index $index -- begin to deploy $service_name on host: $array_service_host[$index] at [$time_stamp]";
            my $each_platform = &deploy_service_to_host($array_service_host[$index],$service_package_name);
            if ( defined $each_platform) {
                # body...
                say LOG_FILE "host index $index -- set remote platform to $each_platform";
                my $file_platform = File::Spec->catfile($directory_deploy, "logs","platform_$index");
                system("echo $each_platform > $file_platform");
            }
            $time_stamp = localtime();
            print "\nhost index $index -- deploy $service_name finished at [$time_stamp], the next step is waiting service start up.\n\n";
            say LOG_FILE "\nhost index $index -- deploy $service_name finished at [$time_stamp], the next step is waiting service start up.\n";
            &wait_service_come_up($array_service_host[$index]);
            exit 0;
        }

        $pid_to_host{$pid} = $array_service_host[$index];
        $pid_to_start_time{$pid} = time;
        $host_number_ongoing++;

        while ( $host_number_ongoing >= $host_number_simultaneity ) {
            $time_stamp = localtime();
            say LOG_FILE "sleep 20s as operation on going number is $host_number_ongoing, limation is $host_number_simultaneity [$time_stamp]";
            print "sleep 20s as operation on going number is $host_number_ongoing, limation is $host_number_simultaneity [$time_stamp]\n";
            sleep(20);
        }

        sleep(2); # sleep is suggested
    }

    my $collect_pid;
    while ( ($host_number_finished+$host_number_timeout) != $host_number_total ) {
        if ( ($collect_pid = waitpid(-1,WNOHANG)) > 0 ) {
            $host_number_finished++;
            $time_stamp = localtime();
            say LOG_FILE "operation on host $pid_to_host{$collect_pid} finished [$time_stamp].";
            print "operation on host $pid_to_host{$collect_pid} finished [$time_stamp].\n";
            if ( exists $pid_to_host{$collect_pid} ) {
                delete $pid_to_host{$collect_pid};
            }
            if ( exists $pid_to_start_time{$collect_pid} ) {
                delete $pid_to_start_time{$collect_pid};
            }
        }

        my $current_time = time;
        $host_number_timeout = 0;
        while ( my ($key, $value) = each %pid_to_start_time ) {
            if ( ($current_time - $pid_to_start_time{$key}) >= $service_remote_timeout ) {
                $time_stamp = localtime();
                say LOG_FILE "operation on host $pid_to_host{$key} is timeout yet[$time_stamp]";
                print "operation on host $pid_to_host{$key}  is timeout yet[$time_stamp]\n";
                $host_number_timeout++;
            }
        }

        say LOG_FILE "sleep 10s to check again...";
        print "sleep 10s to check again...\n";
        sleep(10);
    }

    if ( $host_number_total > 0 ) {
        $time_stamp = localtime();
        while ( my ($key, $value) = each %pid_to_host ) {
            say LOG_FILE "operation on host $pid_to_host{$key} is timeout finally[$time_stamp]!!";
            print "operation on host $pid_to_host{$key} is timeout finally[$time_stamp]!!\n";
        }

    }
}


sub usage_deploy {
    my $usage = "\nUsage:\n";
    $usage = $usage."\t--operation|-o (deploy|wipeout)\n";
    $usage = $usage."\t--ignore_config|-i (ignore local packages configuration)\n";
    return $usage;
}


sub show_step_information {
    (my $message, my $step_index) = @_;
    chomp($time_stamp=localtime());
    say LOG_FILE "-------------------------------------------------------------------------------";
    print LOG_FILE "step $step_index : $message [$time_stamp]\n";
    say LOG_FILE "-------------------------------------------------------------------------------";
    print "step $step_index : $message [$time_stamp]\n";
}



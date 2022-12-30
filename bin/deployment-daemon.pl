#!/usr/bin/perl
#
# 20191107 - mahaiqing - reconfiguration.
#
use strict;
use warnings;
use FindBin qw($RealBin);

use File::Basename;
use File::Spec;
use Getopt::Long;


my $script_path = $RealBin;
my $directory_deployment = dirname($script_path);
my $log_directory=File::Spec->catfile($directory_deployment, "logs");
unless ( -d "$log_directory" ) {
    print "\nthere is no directory($log_directory) to save log, create one\n";
    # exit 1;
    system("mkdir -p $log_directory");
}

my $log_file = File::Spec->catfile($log_directory,"service-deployment-daemon.log");
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


my $service_suffix = "deployment_daemon";
my $operation = undef;
GetOptions("op=s" => \$operation);
unless ( defined $operation) {
    # body...
    die usage();
}
$operation = lc($operation);
$time_stamp = localtime();
say LOG_FILE "========This is the beginning of operation $operation. $time_stamp========";
if ($operation eq 'launch') {
    # &deployment_daemon_check_status();
    &deployment_daemon_operation_stop();
    &environment_prepare();
    &deployment_daemon_operation_startup();
} elsif ($operation eq 'status') {
    &deployment_daemon_check_status();
} elsif ($operation eq 'wipeout') {
    &deployment_daemon_operation_stop();
    &environment_clean();
} else {
    print "ERROR. The operation $operation can't be deal with right now\n";
    say LOG_FILE "ERROR. The operation $operation can't be deal with right now\n";
}

$time_stamp = localtime();
say LOG_FILE "========This is the end of operation $operation. $time_stamp========";
close LOG_FILE;
exit 0;


sub environment_clean {
    opendir(DIR, $directory_deployment);
    foreach ( readdir(DIR)) {
        # body...
        next if ($_ eq "." or $_ eq "..");
        next if ($_ eq "logs");
        my $directory_remove = File::Spec->catfile($directory_deployment, "$_");
        if ( -d $directory_remove) {
            say LOG_FILE "delete directory $directory_remove";
            system("rm -rf $directory_remove");
        }
    }
    closedir DIR;
}


sub environment_prepare {
    say LOG_FILE "check rc.local configuration ";
    my $file_rc_local = "/etc/rc.d/rc.local";
    unless ( -f "$file_rc_local") {
         # body...
         say LOG_FILE "Thers is no file $file_rc_local exists on current host. check file /etc/rc.local";
         if ( (-e "/etc/rc.local") && (! -l "/etc/rc.local") ) {
            $file_rc_local = "/etc/rc.local";
         } else {
            $file_rc_local = "UNCLEAR"
         }
    }
    say LOG_FILE "current host rc.local real location is : $file_rc_local";
    unless ( $file_rc_local eq "UNCLEAR") {
        # body...
        system("chmod a+x $file_rc_local");
        my $tmp_results = `grep 'storectl.pl' $file_rc_local 2>&1 `;
        chomp($tmp_results);
        unless ( $tmp_results eq "" ) {
            # body...
            say LOG_FILE "There is storectl content in rc.local file as : $tmp_results";
         } else {
            $tmp_results = `grep 'exit' $file_rc_local 2>&1 `;
            chomp($tmp_results);
            if ($tmp_results eq "") {
                system("sed -i '\$a\/usr\/bin\/perl  /opt/storage/storectl.pl' $file_rc_local");
            } else {
                system("sed -i '/exit/i\/usr\/bin\/perl  /opt/storage/storectl.pl' $file_rc_local");
            }
            say LOG_FILE "add storectl.pl content to rc.local file";
         }
    }


    my $file_package = undef;
    my $tmp_file = &find_matched_one_file(File::Spec->catfile($directory_deployment, "tars"), "$service_suffix");
    if ($tmp_file =~ "fail") {
        print "ERROR. There is should one package under $directory_deployment tars. environment prepare abort. \n";
        say LOG_FILE "ERROR. There is should one package under $directory_deployment tars. environment prepare abort. ";
        return;
    } else {
        $file_package = File::Spec->catfile($directory_deployment, "tars", $tmp_file);
        say LOG_FILE "get service package name: $file_package";
    }

    my $directory_untar = File::Spec->catfile($directory_deployment, "_packages");
    my $running_command = "tar -xf $file_package -C $directory_untar";
    say LOG_FILE "untar service package by command: $running_command";
    system("$running_command");


    my $directory_service_library = undef;
    my $directory_service_name_version = undef;
    $tmp_file = &find_matched_one_file($directory_untar, $service_suffix);
    if ( $tmp_file =~ "fail" ) {
        print "ERROR. There is should one directory under $directory_untar. environment prepare abort.\n";
        say LOG_FILE "ERROR. There is should one directory under $directory_untar. environment prepare abort.";
        return;
    } else {
        $directory_service_name_version = $tmp_file;
        $directory_service_library = File::Spec->catfile($directory_untar, $directory_service_name_version);
        say LOG_FILE "get service link library path: $directory_service_library";
    }

    my $tmp_index = index($directory_service_name_version, "-");
    my $company_name = substr($directory_service_name_version, 0, $tmp_index);
    my $directory_service_name = "$company_name-$service_suffix";
    my $directory_service_workspace = File::Spec->catfile($directory_deployment, "packages", $directory_service_name);
    unless ( -d $directory_service_workspace ) {
        # body...
        say LOG_FILE "create workspace directory: $directory_service_workspace";
        system("mkdir $directory_service_workspace");
    }

    say LOG_FILE "link service library directories";
    opendir(DIR_LINK, $directory_service_library);
    foreach ( readdir(DIR_LINK)) {
        # body...
        chomp($_);
        next if ($_ eq "." or $_ eq "..");
        next if ($_ eq "logs");
        my $path_src = File::Spec->catfile($directory_service_library, $_);
        my $path_link = File::Spec->catfile($directory_service_workspace, $_);
        if ( -e $path_link ) {
            system("rm -rf $path_link");
        }
        $running_command = "ln -s $path_src $directory_service_workspace";
        system("$running_command");
    }
    closedir DIR_LINK;
}


sub deployment_daemon_get_port {
    my $file_properties = undef;
    my @tmp_files = `find "$directory_deployment"  -name "deployment_daemon.properties"`;
    if ( scalar(@tmp_files) == 0 ) {
        say LOG_FILE "can't find deployment_daemon.properties under directory $directory_deployment. Maybe service has been wipeout";
        return "fail: there is no deployment_daemon.properties file";
    } elsif( scalar(@tmp_files) == 1 ) {
        $file_properties = $tmp_files[0];
        chomp($file_properties);
        say LOG_FILE "find one config file: $file_properties";
    } else {
        say LOG_FILE "there are many files matched deployment_daemon.properties, can't decide which one is right";
        return "fail: more than one config file deployment_daemon.properties under $directory_deployment ";
    }

    my $tmp_results = `grep 'dd.app.port' $file_properties 2>&1 `;
    chomp($tmp_results);
    $tmp_results =~ s/\s//g;
    say LOG_FILE "get results [ $tmp_results ] from config file.";
    my $port_value = undef;
    if ( $tmp_results =~ /.*=(\d+)/ ) {
        $port_value = $1;
    }

    unless (defined $port_value ) {
        return "fail: can't get target value from config file";
    }

    if ( $port_value < 10 ) {
        return "fail: port value from config file seems not valid";
    } else {
        return "$port_value";
    }
}


sub deployment_daemon_valid_spid {
    my ($spid_value) = (@_);
    my $tmp_results = `ps -ef | grep $spid_value`;
    chomp($tmp_results);
    say LOG_FILE "get spid [ $spid_value ] processes information: ---->\n$tmp_results\n<----";
    if ($tmp_results =~ "$service_suffix") {
        return "true";
    } else {
        return "false";
    }
}


sub deployment_daemon_get_spid {
    my $port_value = deployment_daemon_get_port();
    say LOG_FILE "get deployment_daemon service port number: $port_value";
    if ( $port_value =~ "fail" ) {
        return "fail:can't get deployment_daemon service port number";
    }
    chomp($port_value);
    my $tmp_results = `netstat -npl | grep $port_value`;
    chomp($tmp_results);
    say LOG_FILE "get matched port results: \n$tmp_results";
    my $spid_value = undef;
    foreach my $each_line (split(/[\r\n]/, $tmp_results)) {
        chomp($each_line);
        if ( $each_line =~ /.*:$port_value.*\s+\d+\/java/ ) {
            ($spid_value = $each_line) =~ s/.*\s+(\d+)\/java/$1/g;
            $spid_value =~ s/\s//g;
            say LOG_FILE "get value [ $spid_value ] from line: $each_line";
            last;
        }
    }

    if (defined $spid_value) {
        if ( &deployment_daemon_valid_spid($spid_value) eq "true" ) {
            # body...
            say LOG_FILE "get deployment_daemon service spid : [ $spid_value ]";
            return $spid_value;
        } else {
            return "fail: deployment_daemon service pid is not valid"
        }
    } else {
        return "fail: there is no deployment_daemon service";
    }
}


sub process_manager_operation_stop {
    while (1) {
        my $flag_check_again = undef;
        my $running_command = "ps -ef | grep ProcessManager | grep dd-launcher";
        my $tmp_results = `$running_command`;
        chomp($tmp_results);
        say LOG_FILE "check ProcessManager by command: $running_command, and results as follows:\n$tmp_results\n";
        foreach (split(/[\r\n]/, $tmp_results)) {
            chomp($_);
            next if ($_ =~ /ps -ef/);
            next unless ( $_ =~ "java");
            my $pid_value = `echo $_ | awk '{print \$2}' `;
            chomp($pid_value);
            say LOG_FILE "ProcessManager pid is : $pid_value";
            if ($pid_value =~ /^\d+$/) {
                system("kill -9 $pid_value");
                $flag_check_again = "true";
            }
        }
        unless ( defined $flag_check_again ) {
            say LOG_FILE "ProcessManager has been stopped.";
            last;
        }
    }
}


sub deployment_daemon_operation_startup {
    my $tmp_file = &find_matched_one_file(File::Spec->catfile($directory_deployment, "packages"), "$service_suffix");
    if ($tmp_file =~ "fail") {
        print "ERROR. There is no packages directory under $directory_deployment. startup operation abort. \n";
        say LOG_FILE "ERROR. There is no packages directory under $directory_deployment. startup operation abort.";
        return;
    }

    my $directory_service = File::Spec->catfile($directory_deployment, "packages",$tmp_file);

    my $running_command = "cd $directory_service; nohup bash bin/startup.sh &";
    say LOG_FILE "startup deployment_daemon service by command: $running_command";
    system("$running_command");
}


sub deployment_daemon_operation_stop {
    &process_manager_operation_stop();
    my $spid_value = &deployment_daemon_get_spid();
    if ( $spid_value =~ "fail" ) {
        say LOG_FILE "can't stop deployment_daemon service by kill pid";
        return;
    }
    say LOG_FILE "kill service process [ $spid_value ]";
    system("kill -9 $spid_value");
}


sub deployment_daemon_check_status {
    my $spid_value = &deployment_daemon_get_spid();
    if ($spid_value =~ "fail") {
        print "current status is UNCLEAR\n" and return
    } else {
        print "current status is ACTIVE\n" and return;
    }
}




sub find_matched_one_file {
    my ($directory_path, $matched_string) = (@_);
    unless ( -d "$directory_path" ) {
         # body...
         return "fail: there is not input directory $directory_path";
    }

    my @array_file_name = ();
    opendir(DIR_FIND, $directory_path);
    foreach ( readdir(DIR_FIND)) {
        # body...
        next if ($_ eq "." or $_ eq "..");
        if ($_ =~ $matched_string) {
            push @array_file_name, $_;
        }
    }
    closedir DIR_FIND;

    if ( scalar(@array_file_name) == 0 ) {
        say LOG_FILE "can't find any file matched $matched_string under directory $directory_path";
        return "fail: there is no matched file";
    } elsif( scalar(@array_file_name) == 1 ) {
        say LOG_FILE "find one file $array_file_name[0] as wanted under $directory_path";
        return $array_file_name[0];
    } else {
        say LOG_FILE "there are many files matched $matched_string . It shoulb be only one!!";
        return "fail: there are more than one matched file, match string is not clear";
    }
}

sub usage {
    my $usage = "Usage: \n";
    $usage = $usage."\t--option|-o (launch|status|wipeout)\n";
    return $usage;
}



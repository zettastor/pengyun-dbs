#!/usr/bin/perl
#
# This script is used to check storage host status(space, memory and so on) 
# 20190808 - mahaiqing - first version
# 20220317 - mahaiqing - refactoring.

use strict;
use warnings;
use File::Basename;
use File::Spec;


my $log_directory= "/var/log";
unless ( -d "$log_directory" ) {
    print "\nthere is no directory($log_directory) to save log, please make sure all the files are in right path\n";
    # exit 1;
    system("mkdir -p $log_directory");
}


my $log_file=File::Spec->catfile($log_directory,"storage-host-space-check.log");
my $time_stamp = localtime();
if (-e "$log_file") {
    print "the log file for check storage hosts periodly exists already. Check the file size ...\n";
    my $file_size = (stat "$log_file")[7];
    if ( $file_size >= 1048576 ) {
        system("echo -e 'clear old logs at $(time_stamp) to avoid log file too big' > $log_file");
    }
}

# this is used to set Filesystem Mount Point's max Usage.
# The mount point and useage could be get by command df -lh
# only the usage larger than threshold, files older than specify time will be deleted
my %disk_mounted_To_Use_threshold = (
    "/" => "75",
    "/var/testing" => "70",
    );

# old file's max size. file size larger than this threshold will be deleted. 1048576=1M
my $older_file_max_size_bytes = 10485760;
# this is used to list which files could be deleted. only the file  size larager than threshold will be deleted
my %directory_files_To_keepped_days = (
    "/tmp" => "10",
    "/var/log" => "30",
    "/opt/zookeeper/logs" => "30",
    );

my @checking_directory = keys %directory_files_To_keepped_days;

# flag to show storage service log need to be deleted or not
my $clean_flag_service_log = "false";
# flag to show host system log need to be deleted or not. system log directory are listed in %directory_files_To_keepped_days
my $clean_flag_system_log = "false";

# these are log file need to be limited size less than $older_file_max_size_bytes
my @observed_log_file = (
    "/root/.targetcli/log.txt",
);

system("touch $log_file");
open(LOG_FILE, '>>', "$log_file");
$| = 1;
my $step_index = 1;
&show_step_information("check host local Filesystem usage ",$step_index++);
my $tmp_value = `df -lh`;
chomp($tmp_value);
say LOG_FILE "host all disk usage as: \n$tmp_value\n";
my @local_filesystem_usage = split /\n/, $tmp_value;
foreach ( @local_filesystem_usage ) {
    my @tmp_array = split /\s+/, $_;
    my ($tmp_usage, $tmp_mount_point) = ($tmp_array[-2], $tmp_array[-1]);
    if ( exists $disk_mounted_To_Use_threshold{$tmp_mount_point} ) {
        say LOG_FILE "check point ($tmp_mount_point) current usage is ($tmp_usage), threshold value is $disk_mounted_To_Use_threshold{$tmp_mount_point}";
        $tmp_usage =~ s/%//g;
        if ( $tmp_usage >= $disk_mounted_To_Use_threshold{$tmp_mount_point} ) {
            say LOG_FILE "It seems some files should be deleted as ($tmp_mount_point) is bigger than threshold usage";
            if ( $tmp_mount_point eq "/var/testing" ) {
                $clean_flag_service_log = "true";
                say LOG_FILE "some log files under directory(/var/testing) should be deleted";
            } else {
                $clean_flag_system_log = "true";
                say LOG_FILE "some log files under directory among in [ @checking_directory ] should  be deleted";
            }
        }
    } else {
        say LOG_FILE "Filesystem mount point ($tmp_mount_point) with current usage ($tmp_usage)"
    }
}


&show_step_information("check whether need to delete some system log files ",$step_index++);
if ($clean_flag_system_log eq "true") {
    say LOG_FILE "It is going to delete system log files among in [ @checking_directory ] ";
    &clean_system_log_files();
} else {
    say LOG_FILE "there is not necessary to delete system log files among in [ @checking_directory ] ";
}


&show_step_information("check whether need to delete some storage log files ",$step_index++);
if ($clean_flag_service_log eq "true") {
    say LOG_FILE "It is going to delete storage service log files under directory /var/testing";
    &clean_storage_service_log_files();
} else {
    say LOG_FILE "there is not necessary to delete storage service log files under directory /var/testing ";
}


&show_step_information("check observed log file size ",$step_index++);
foreach (@observed_log_file) {
    # body...
    unless ( -f $_) {
        # body...
        say LOG_FILE "there is no log file [$_] on current host.";
        next;
    }
    my $file_size = (stat "$_")[7];
    if ( $file_size >= $older_file_max_size_bytes ) {
        say LOG_FILE "set file[$_] content to null as it's size is bigger than $older_file_max_size_bytes";
        system("echo  > $_ ");
    } else {
        say LOG_FILE "file[$_] size is $file_size";
    }
}


# these are file under /var/testing/packages directory need to find and check size
my @file_need_to_find_check = (
    "MegaSAS.log",
);
&show_step_information("find and check some file under /var/testing/packages ",$step_index++);
foreach my $tmp_file_name ( @file_need_to_find_check ) {
    my $tmp_value = `find /var/testing/packages -maxdepth 2 -name $tmp_file_name -print`;
    say LOG_FILE "find files under (/var/testing/packages) named ($tmp_file_name) as follow: \n$tmp_value";
    my @tmp_array = split /\n/, $tmp_value;
    foreach(@tmp_array) {
        my $file_size = (stat "$_")[7];
        if ( $file_size >= $older_file_max_size_bytes ) {
            say LOG_FILE "clean file($_) as size is bigger than $older_file_max_size_bytes";
            system(" echo -e '' > $_ ");
        }
    }
}


# these are directory name under /var/lib directory need to find and remove file some created some days ago
my @directory_need_to_find_check = (
    "xlog_archive",
    "pg_xlog",
);
&show_step_information("find and check some directory under /var/lib ",$step_index++);
foreach my $tmp_directory_name ( @directory_need_to_find_check ) {
    my $tmp_value = `find /var/lib -name $tmp_directory_name -print`;
    say LOG_FILE "find directory under (/var/lib) named ($tmp_directory_name) as follow: \n$tmp_value";
    my @tmp_array = split /\n/, $tmp_value;
    foreach(@tmp_array) {
        &remove_file_older_bigger($_, 60, 0);
    }
}



&show_step_information("check local host Filesystem space",$step_index++);
foreach ( @local_filesystem_usage ) {
    my @tmp_array = split /\s+/, $_;
    my ($tmp_usage, $tmp_mount_point) = ($tmp_array[-2], $tmp_array[-1]);
    if ( exists $disk_mounted_To_Use_threshold{$tmp_mount_point} ) {
        say LOG_FILE "After clean up, ($tmp_mount_point) current usage is ($tmp_usage), threshold value is $disk_mounted_To_Use_threshold{$tmp_mount_point}";
        $tmp_usage =~ s/%//g;
        if ( $tmp_usage >= $disk_mounted_To_Use_threshold{$tmp_mount_point} ) {
            say LOG_FILE "WARNING!!! ($tmp_mount_point) current usage is still bigger than threshold usage";
        }
    } else {
        say LOG_FILE "Filesystem mount point ($tmp_mount_point) with current usage ($tmp_usage)"
    }
}

&show_step_information("This is the end of check storage host",$step_index++);
say LOG_FILE "================================================================================";
print "================================================================================\n";
close LOG_FILE;
exit 0;



sub show_step_information {
    (my $message, my $step_index) = @_;
    chomp(my $timestamp=localtime());
    say LOG_FILE "-------------------------------------------------------------------------------";
    say LOG_FILE "step $step_index : $message [$timestamp]";
    say LOG_FILE "-------------------------------------------------------------------------------";
    print "step $step_index : $message [$timestamp]\n";
}


#clean log under directory which defined in directory_files_To_keepped_days
sub clean_system_log_files {
    while ( (my $directory_name, my $keepped_days) = each %directory_files_To_keepped_days ) {
        unless ( -d $directory_name ) {
            # body...
        say LOG_FILE "there is directory $directory_name on current host.";
            next;
        }
        &remove_file_older_bigger($directory_name, $keepped_days, $older_file_max_size_bytes);
    }
}

#remove files which created some days before and size is out of rang
sub remove_file_older_bigger {
    (my $directory_name, my $keepped_days, my $file_max_size_bytes) = @_;

    my $tmp_value = `find $directory_name -ctime +$keepped_days -print`;
    say LOG_FILE "find files under ($directory_name) created ($keepped_days) days before as follow: \n$tmp_value";
    my @tmp_array = split /\n/, $tmp_value;
    foreach(@tmp_array) {
        my $file_size = (stat "$_")[7];
        if ( $file_size >= $file_max_size_bytes ) {
            say LOG_FILE "delete file($_) created $keepped_days ago and size is bigger than $file_max_size_bytes";
            system("unlink $_");
        }
    }
}


#clean log under directory(/var/testing)
# client  -- pyd has already limit log size
# EventData - SystemDaemon service will do record cleaning
# packages -- service log4j.properties will limit log file number and size
sub clean_storage_service_log_files {
    say LOG_FILE "/var/testing/client  -- pyd has already limit log size";
    say LOG_FILE "/var/testing/EventData - SystemDaemon service will do record cleaning";
    say LOG_FILE "/var/testing/packages -- service log4j.properties will limit log file number and size";
}
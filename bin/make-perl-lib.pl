#!/usr/bin/perl
# this script is used to prepare perl lib environment on current host
# 20200202 - mahaiqing - reconstruction.
# 20200321 - mahaiqing - add local perl lib checking.
# 20211101 - mahaiqing - add OS support besides CentOS/RedHat.
# 20220629 - mahaiqing - add OS support [kylin 4.19.90-24.4.v2101.ky10.aarch64  and UOS20 4.19.0-loongson-3-server ].

use strict;
use warnings;
use FindBin '$RealBin';
use File::Basename;
use File::Spec;


my $script_path = $RealBin;
my $directory_deploy = dirname($script_path);
my $log_directory=File::Spec->catfile($directory_deploy, "logs");
unless ( -d "$log_directory" ) {
    print "\nthere is no directory($log_directory) to save log, create one\n";
    # exit 1;
    system("mkdir -p $log_directory");
}

my $log_file = File::Spec->catfile($log_directory,"prepare-perl-library.log");
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
my $step_index = 1;
&show_step_information("This is going to prepare perl library for product operation", $step_index);


$step_index++;
&show_step_information("Check necessary package for library installation", $step_index);
my $tmp_result = `rpm -version 2>&1`;
if (defined $tmp_result) {
    chomp($tmp_result);
    say LOG_FILE "command check results: $tmp_result";
} else {
    $tmp_result = "command not found";
}

if ($tmp_result =~ "command not found") {
    say LOG_FILE "Maybe current host's OS doesn't support rpm command";
} else {
    $tmp_result = `rpm -qa | grep perl-ExtUtils-MakeMaker 2>&1`;
    chomp($tmp_result);
    say LOG_FILE "package check results: $tmp_result";
    if ($tmp_result =~ "perl-ExtUtils-MakeMaker") {
        say LOG_FILE "package perl-ExtUtils-MakeMaker.rpm has been installed";
    } elsif ($tmp_result eq "") {
        print "Please check perl-ExtUtils-MakeMaker has been installed or not\n";
        say LOG_FILE "It seems package perl-ExtUtils-MakeMaker hasn't been installed";
        exit 1;
    }
}


$step_index++;
&show_step_information("Check command perldoc available or not", $step_index);
$tmp_result = `perldoc -l Net::OpenSSH 2>&1`;
chomp($tmp_result);
say LOG_FILE "perldoc command check results: $tmp_result";
my $flag_command_perldoc = "available";
if ($tmp_result =~ "need to install the perl-doc package") {
    say LOG_FILE "command perldoc is not available on current host";
    $flag_command_perldoc = "unavailable";
}


$step_index++;
&show_step_information("get required perl library information", $step_index);
my $directory_library_resource = File::Spec->catfile($directory_deploy, "lib_src");
my $directory_library_local_perl5 = File::Spec->catfile($directory_deploy, "lib", "perl5");

my @library_list = qw(Class-Accessor Config-Properties IO-Tty Expect JSON Log-Log4perl Net-OpenSSH Net-SSH-Expect);
my $library_module_name = undef;

foreach ( @library_list ) {
    if ( /-/ ) {
        my @tmp_array = split /-/, $_;
        $library_module_name = join "::",@tmp_array;
    } else {
        $library_module_name = $_;
    }
    $step_index++;
    &show_step_information("prepare perl library module [$library_module_name] begin ",$step_index);
    my $results_message = &check_perl_library_by_name($library_module_name);
    unless ( $results_message eq "true" ) {
        say LOG_FILE "try to install perl library : $_";
        $results_message = &install_perl_library_by_name($_, $library_module_name);
        if ($results_message =~ "fail") {
            say LOG_FILE "prepare perl library module [$library_module_name] failed!!";
            print "prepare perl library module [$library_module_name] failed!!\n";
            exit 1;
        } else {
            say LOG_FILE "module [$library_module_name] has been installed successfully.";
        }
    } else {
        say LOG_FILE "module [$library_module_name] has been installed already.";
    }
    &show_step_information("prepare perl library module [$library_module_name] finished. ",$step_index);
}


$step_index++;
&show_step_information("This is the end of prepare perl library ",$step_index);
say LOG_FILE "================================================================================";
print "================================================================================\n";
close LOG_FILE;
exit 0;


sub show_step_information {
    (my $message, my $step_index) = @_;
    chomp($time_stamp=localtime());
    say LOG_FILE "-------------------------------------------------------------------------------";
    print LOG_FILE "step[make-perl-lib] $step_index : $message [$time_stamp]\n";
    say LOG_FILE "-------------------------------------------------------------------------------";
    print "step[make-perl-lib] $step_index : $message [$time_stamp]\n";
}


sub check_perl_library_by_name {
    (my $module_name) = @_;

    if ($flag_command_perldoc eq "unavailable") {
        return "unclear";
    }
    my $running_command = "perldoc -l $module_name 2>&1";
    chomp($tmp_result=`cd $directory_deploy; $running_command `);
    say LOG_FILE "check results in public directory as: $tmp_result";
    if ($tmp_result eq "" or $tmp_result =~ "No documentation found") {
        say LOG_FILE "can't find perl library module [$module_name] in public directory!!";
    } else {
        say LOG_FILE "module [$library_module_name] file name is : $tmp_result [public directory]";
        return "true";
    }

    if ( -d $directory_library_local_perl5 ) {
        chomp($tmp_result=`cd $directory_library_local_perl5; $running_command`);
        say LOG_FILE "check results in local directory[$directory_library_local_perl5] as: $tmp_result";
        if ($tmp_result eq "" or $tmp_result =~ "No documentation found") {
            say LOG_FILE "can't find perl library module [$module_name] in local directory!!";
        } else {
            say LOG_FILE "module [$library_module_name] file name is : $tmp_result [$directory_library_local_perl5]";
            return "true";
        }

        opendir  LOCAL_LIB_PERL, $directory_library_local_perl5;
        foreach my $local_file (readdir LOCAL_LIB_PERL) {
            next if ($local_file eq "." or $local_file eq "..");
            my $tmp_directory = File::Spec->catfile($directory_library_local_perl5, $local_file);
            my $file_links = (stat "$tmp_directory")[3];
            if ( $file_links == "1" ) {
                say LOG_FILE "skip file $local_file";
                next;
            } else {
                say LOG_FILE "get directory [ $local_file ] under $directory_library_local_perl5";
            }
            chomp($tmp_result=`cd $tmp_directory; $running_command`);
            say LOG_FILE "check results in local directory[$tmp_directory] as: $tmp_result";
            if ($tmp_result eq "" or $tmp_result =~ "No documentation found") {
                # say LOG_FILE "can't find perl library module [$module_name] in local directory[$local_file]!!";
            } else {
                say LOG_FILE "module [$library_module_name] file name is : $tmp_result [local perl directory: $local_file] ";
                return "true";
            }
        }
        closedir LOCAL_LIB_PERL;
    } else {
        say LOG_FILE "this is no local lib directory : $directory_library_local_perl5";
    }
    return "false";
}


sub check_perl_library_by_check_pm_file {
    (my $module_name) = @_;
    my $module_filename = undef;
    my $module_dirname = undef;
    if ( $module_name =~ "::" ) {
        ($module_dirname, $module_filename) = (split /:/, $module_name)[0,-1];
        $module_filename = $module_filename.".pm";
    } else {
        $module_filename = $module_name.".pm";
    }

    say LOG_FILE "check [$module_name] pm file under [$directory_library_local_perl5] or not";
    my $target_file = undef;
    if ( defined $module_dirname ) {
        if ( $module_name eq "Net::SSH::Expect" ) {
            $target_file = File::Spec->catfile($directory_library_local_perl5, "Net/SSH/Expect.pm");
        } else {
            $target_file = File::Spec->catfile($directory_library_local_perl5, $module_dirname, $module_filename);
        }
    } else {
        $target_file = File::Spec->catfile($directory_library_local_perl5, $module_filename);
    }
    say LOG_FILE "check file [$target_file] exists or not";

    if ( -f "$target_file" ) {
        return "true";
    } else {
        say LOG_FILE "check file [$target_file] under x86_64-linux-gnu-thread-multi ";
        $target_file = File::Spec->catfile($directory_library_local_perl5, "x86_64-linux-gnu-thread-multi",$module_dirname, $module_filename);
    }

    if ( -f "$target_file" ) {
        return "true";
    } else {
        return "false";
    }
}


sub install_perl_library_by_name {
    (my $one_library, my $module_name) = @_;

    my $library_file_name = undef;
    opendir(DIR_LIB_SRC, $directory_library_resource);
    foreach ( readdir(DIR_LIB_SRC)) {
        # body...
        say LOG_FILE "check file: $_";
        if ( $_ eq "." || $_ eq "..") { next; }
        unless ( $_ =~ "tar.gz" ) { next; }
        if ( $_ =~ "^$one_library" ) {
            $library_file_name = $_;
            last;
        }
    }
    closedir DIR_LIB_SRC;

    unless ( defined $library_file_name) {
        # body...
        say LOG_FILE "can't find tar.gz file matched [ $one_library ]";
        return "fail: can't find tar.gz file matched [ $one_library ] ";
    } else {
        say LOG_FILE "find resource file [$library_file_name] in local directory";
    }

    my $library_full_name = File::Spec->catfile($directory_deploy, "lib_src", $library_file_name);
    my $running_command = "tar -zxf $library_full_name -C /tmp";
    system("$running_command");
    say LOG_FILE "untar by command: [$running_command]";
    my $library_dir_name = substr($library_file_name,0,length($library_file_name)-7);
    my $tmp_directory = File::Spec->catfile("/tmp", $library_dir_name);
    unless ( -d $tmp_directory ) {
        # body...
        say LOG_FILE "file $library_file_name untar to $tmp_directory failed !";
        print "file $library_file_name untar to $tmp_directory failed !\n";
        return "fail: file untar filed";
    } else {
        say LOG_FILE "file $library_file_name untar to $tmp_directory successfully!";
    }
    chdir($tmp_directory);
    print "\nInstall perl module [$module_name], please wait some time\n";
    $running_command = "/usr/bin/perl Makefile.PL INSTALL_BASE=$directory_deploy 2>&1";
    say LOG_FILE "Install perl module [$module_name] to local directory by command [$running_command]";
    system("$running_command");
    system("make 2>&1 ");
    system("make install 2>&1 ");
    chdir($directory_deploy);
    print "sleep 3 seconds after installation to check again\n";
    sleep(3);
    if (-d $tmp_directory ) {
        system("rm -rf $tmp_directory");
    }


    my $results_message = &check_perl_library_by_name($module_name);
    if ( $results_message eq "true" ) {
        say LOG_FILE "prepare perl library module [$module_name] success";
        return "success";
    } elsif ( $results_message eq "unclear" ) {
        print "Don't need to check library installed or not by command perldoc\n";
    }

    $results_message = &check_perl_library_by_check_pm_file($module_name);
    if ( $results_message eq "true" ) {
        say LOG_FILE "find module [$module_name] pm file under [$directory_library_local_perl5]";
        return "success";
    } else {
        return "fail: not find module file after installation";
    }
}


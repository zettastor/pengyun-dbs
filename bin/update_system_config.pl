#!/usr/bin/perl
#
# 20220819 - haiqinma - refactor for open source
# 
use strict;
use warnings;
use FindBin '$RealBin';
use lib "$RealBin";
use lib "$RealBin/../lib/perl5";

use Config::Properties;
use Data::Dumper;
use File::Basename;
use File::Spec;
use Getopt::Long;
use Net::OpenSSH;
use XML::Simple;

use Public_storage;


my $script_path = $RealBin;
my $directory_deploy = dirname($script_path);
my $log_directory=File::Spec->catfile($directory_deploy, "logs");
unless ( -d "$log_directory" ) {
    print "\nthere is no directory($log_directory) to save log, create one\n";
    system("mkdir -p $log_directory");
}

my $log_file = File::Spec->catfile($log_directory,"update-local-packages.log");
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
&show_step_information("This is going update local packages according to configuration",$step_index);
my $string_usage = "";
print &usage_update_local_packages();


$step_index++;
&show_step_information("Get necessary information from config/deploy.properties ",$step_index);
my $file_deploy_properties = File::Spec->catfile($directory_deploy, 'config/deploy.properties');

open my $file_handler_deploy, '<', $file_deploy_properties
    or die "unable to open configuration file deploy.properties";

my $deploy_properties = Config::Properties->new();
$deploy_properties->load($file_handler_deploy);
my $config_tree_deploy_properties = $deploy_properties->splitToTree();
close $file_handler_deploy;


$step_index++;
&show_step_information("get platform type and update flag",$step_index);
my $platform_update = $config_tree_deploy_properties->{'platform'}{'update'};
unless ( defined $platform_update ) {
    $platform_update = "false";
}
my $remote_platform = $config_tree_deploy_properties->{'remote'}{'platform'};
unless (defined $remote_platform) {
    $remote_platform = "x86_64";
} else {
    $remote_platform =~ s/\s//g;
    $remote_platform = lc($remote_platform);
}
if ($platform_update eq "false") {
    say LOG_FILE "there is no need to check platform type[current setting: $remote_platform]";
    print "there is no need to check platform type[current setting: $remote_platform]\n";
} else {
    &check_update_platform_type();
}


$step_index++;
&show_step_information("check platform kernel files",$step_index);
my $directory_so_files = File::Spec->catfile($directory_deploy, "resources");
unless ( $remote_platform eq "x86_64") {
    $directory_so_files = File::Spec->catfile($directory_deploy, "resources/binary",$remote_platform);
}
unless ( -d $directory_so_files ) {
    # body...
    print "\nthere is no specify so directory [$directory_so_files] for platform [$remote_platform]\n";
    say LOG_FILE "there is no specify so directory [$directory_so_files] for platform [$remote_platform]";
    close LOG_FILE;
    exit 0;
}


$step_index++;
&show_step_information("update special so and jar file for platform",$step_index);
my $directory_packages   = File::Spec->catfile($directory_deploy, "packages");
unless ( $remote_platform eq "x86_64") {
     # body...
    say LOG_FILE "Once these files updated,  them can't be changed back to x86_64 platform automatically";
    print "Once these files updated, them can't be changed back to x86_64 platform automatically\n";
    my $tmp_results = &update_platform_so_jar_files();
    if ( $tmp_results =~ "fail" ) {
        close LOG_FILE;
        exit 0;
    }
} else {
    say LOG_FILE "no file need to update for $remote_platform platform";
    print "no file need to update for $remote_platform platform\n";
}


my $xml_file = File::Spec->catfile($directory_deploy, "config/module_settings.xml");
$step_index++;
&show_step_information("get properties from configuration[$xml_file]",$step_index);
my $xml_simple = XML::Simple->new();
my $properties_tree = $xml_simple->XMLin($xml_file, KeyAttr=>{project=>'name',file=>'name',property=>'name'}, ForceArray=>['project','file','property']);

foreach my $item_project(keys %{$properties_tree->{'project'}}) {
    foreach my $item_file(keys %{$properties_tree->{'project'}{$item_project}{'file'}}) {
        foreach my $item_property(keys %{$properties_tree->{'project'}{$item_project}{'file'}{$item_file}{'property'}}) {
            my $item_value = $properties_tree->{'project'}{$item_project}{'file'}{$item_file}{'property'}{$item_property}{'value'};
            my $item_range = $properties_tree->{'project'}{$item_project}{'file'}{$item_file}{'property'}{$item_property}{'range'};

            if (defined $item_value && defined $item_range) {
                my $tmp_results = &check_property_value_among_range($item_value,$item_range);
                if ($tmp_results  =~ "fail") {
                    say LOG_FILE "property[$item_property] value [$item_value] is out of range[$item_range] on file [$item_file] in project[$item_project]";
                    print  "property[$item_property] value [$item_value] is out of range[$item_range] on file [$item_file] in project[$item_project]\n";
                    close LOG_FILE;
                    exit 1;
                }
            }
        }
    }
}


$step_index++;
&show_step_information("update configuration of local packages",$step_index);
my $service_name = undef;
GetOptions ("s:s" => \$service_name);
unless (defined $service_name) {
    # body...
    $service_name = "all";
    say LOG_FILE "all product service packages will be updated";
} else {
    say LOG_FILE "Only service matched [$service_name] will be updated";
}
# sort by name - lower case
my @array_service_name = (
    'console',
    'coordinator',
    'datanode',
    'deployment_daemon',
    'drivercontainer',
    'infocenter',
    'instancehub',
    );
if ( $service_name ne "all") {
    unless (grep {$_ eq $service_name} @array_service_name) {
        say LOG_FILE "service name[$service_name] is not among [@array_service_name]";
        print "service name[$service_name] is not among [@array_service_name]\n";
        close LOG_FILE;
        exit 1;
    }
}

my $running_command = undef;
if ( $service_name eq "all" ) {
    foreach (@array_service_name) {
        &update_config_properties_of_service($_);
    }
} else {
    &update_config_properties_of_service($service_name);
}



$step_index++;
&show_step_information("This is the end of update local packages according to configuration",$step_index);
say LOG_FILE "================================================================================";
print "================================================================================\n";
close LOG_FILE;

exit 0;

&generate_local_packages_directory($service_name);


$step_index++;
&show_step_information("remove old product service tar.gz packages for update properties",$step_index);
opendir(DIR_PACKAGES, $directory_packages);
chdir($directory_packages);
foreach ( readdir(DIR_PACKAGES) ) {
    # body...
    if ( $_ eq "." || $_ eq ".." ) { next;}
    unless ( $_ =~ 'tar.gz' ) {
        say LOG_FILE "skip file or directory: $_";
        next;
    }
    if ( $_ =~ "zookeeper") {
        say LOG_FILE "skip zookeeper file : $_";
        next;
    }
    if ( $service_name ne "all" ) {
        unless ($_ =~ "$service_name" ) {
            next;
        }
    }
    my $file_tmp = File::Spec->catfile($directory_packages, $_);
    unlink $file_tmp || print "can't delete file $$file_tmp";
    say LOG_FILE "delete $_ under packages directory";

}
closedir DIR_PACKAGES;



sub update_config_properties_under_directory {
    (my $service_update, my $directory_name_untar) = @_;

    my $update_properties_tree = undef;
    foreach my $item_project (keys %{$properties_tree->{'project'}}) {
        if ($item_project eq "*") {
            foreach my $item_file (keys %{$properties_tree->{'project'}{$item_project}{'file'}}) {
                # body...
                say LOG_FILE "get common file [$item_file] configuration";
                foreach my $item_property (keys %{$properties_tree->{'project'}{$item_project}{'file'}{$item_file}{'property'}}) {
                    my $item_value = $properties_tree->{'project'}{$item_project}{'file'}{$item_file}{'property'}{$item_property}{'value'};
                    $update_properties_tree->{'file'}{$item_file}{'property'}{$item_property}{'value'} = $item_value;
                    say LOG_FILE "get common property[$item_property] value [$item_value]";
                }
            }
        }
    }

    #specify property will overwrite common configuration
    foreach my $item_project (keys %{$properties_tree->{'project'}}) {
        if ($item_project =~ $service_update) {
            say LOG_FILE "get specify project [$item_project]";
            foreach my $item_file (keys %{$properties_tree->{'project'}{$item_project}{'file'}}) {
                # body...
                say LOG_FILE "get specify project file [$item_file] configuration";
                foreach my $item_property (keys %{$properties_tree->{'project'}{$item_project}{'file'}{$item_file}{'property'}}) {
                    my $item_value = $properties_tree->{'project'}{$item_project}{'file'}{$item_file}{'property'}{$item_property}{'value'};
                    $update_properties_tree->{'file'}{$item_file}{'property'}{$item_property}{'value'} = $item_value;
                    say LOG_FILE "get specify project property[$item_property] value [$item_value]";
                }
            }
        }
    }

    foreach my $update_file (keys %{$update_properties_tree->{'file'}}) {
        my $tmp_directory = File::Spec->catfile($directory_packages, $directory_name_untar);
        $running_command = "find $tmp_directory -name $update_file 2>&1";
        my $tmp_results = `$running_command`;
        chomp($tmp_results);
        my @array_tmp = (split /\n/, $tmp_results);
        my $tmp_file = undef;
        foreach (@array_tmp) {
            if ($update_file eq (basename $_)) {
                $tmp_file = $_;
                last;
            }
        }
        unless (defined $tmp_file) {
            say LOG_FILE "there is no file[$update_file] for service[$service_update]\n";
            next;
        }
        say LOG_FILE "update properties of file[$tmp_file]";
        print "----update service[$service_update] file[$update_file]\n";

        open my $file_handler_properties_read, '<', $tmp_file || die "unable to open configuration file $tmp_file";
        my $checking_properties_tree = Config::Properties->new();
        $checking_properties_tree->load($file_handler_properties_read);
        $checking_properties_tree->format('%s=%s');
        foreach my $update_property (keys %{$update_properties_tree->{'file'}{$update_file}{'property'}}) {
            my $update_value = $update_properties_tree->{'file'}{$update_file}{'property'}{$update_property}{'value'};
            my $config_value = $checking_properties_tree->getProperty($update_property);
            unless (defined $config_value) {
                say LOG_FILE "----ADD----property [$update_property]; value [$update_value]\n";
                print "----ADD----property [$update_property]; value [$update_value]\n";
                $checking_properties_tree->setProperty($update_property, $update_value);
            } else {
                if ( $config_value eq $update_value) {
                    say LOG_FILE "----KEEP----property [$update_property]; value [$update_value]";
                } else {
                    say LOG_FILE "----CHANGE----property [$update_property]; value from [$config_value] to [$update_value]";
                    print "----CHANGE----property [$update_property]; value from [$config_value] to [$update_value]\n";
                    $checking_properties_tree->setProperty($update_property, $update_value);
                }
            }
        }
        close($file_handler_properties_read);
        sleep(1);

        open my $file_handler_properties_write, '>', $tmp_file || die "unable to open configuration file $tmp_file to update";
        $checking_properties_tree->format('%s=%s');
        $checking_properties_tree->store($file_handler_properties_write);    
        close($file_handler_properties_write);
    }
}



sub untar_package_file {
    (my $service_update) = @_;
    
    my $file_name_matched = "";
    my $directory_name_untar = "";
    opendir(DIR_PACKAGES, $directory_packages);
    foreach ( readdir(DIR_PACKAGES) ) {
        # body...
        if ( $_ eq "." || $_ eq "..") { next;}
        if ( (/zookeeper/) ) {next;}
        unless (/tar.gz/) {next;}
        my $tmp_results = (split /-/, $_)[1];
        if ($tmp_results eq $service_update) {
            $file_name_matched = $_;
            say LOG_FILE "find matched package file: $file_name_matched";
            last;
        }
    }
    closedir DIR_PACKAGES;
    if ($file_name_matched eq "") {
        say LOG_FILE "Don't find package file matched [$service_update]";
        return ($file_name_matched, $directory_name_untar);
    }
    my $tmp_file = File::Spec->catfile($directory_packages, $file_name_matched);
    $running_command = "tar -xf $tmp_file -C $directory_packages";
    unless ( system("$running_command") == 0 ) {
        say LOG_FILE "ERROR! untar packages by command [$running_command] failed";
        return ($file_name_matched, $directory_name_untar);
    } else {
        unlink $tmp_file || die "can't delete file $tmp_file";
        say LOG_FILE "after untar operation, delete $tmp_file under packages directory";
    }

    opendir(DIR_PACKAGES, $directory_packages);
    foreach ( readdir(DIR_PACKAGES) ) {
        # body...
        if ( $_ eq "." || $_ eq "..") { next;}
        if ( (/zookeeper/) ) {next;}
        if (/tar.gz/) {next;}
        my $tmp_results = (split /-/, $_)[1];
        if ($tmp_results eq $service_update) {
            $directory_name_untar = $_;
            say LOG_FILE "find matched package directory: $directory_name_untar";
            last;
        }
    }
    closedir DIR_PACKAGES;
    return ($file_name_matched, $directory_name_untar);
}


sub update_config_properties_of_service {
    (my $service_update) = @_;

    print "========update configuration for service [$service_update]========\n";
    say LOG_FILE "update configuration for service [$service_update]";
    my $file_name_matched = undef;
    my $directory_name_untar = undef;
    ($file_name_matched, $directory_name_untar) = &untar_package_file($service_update);
    if ( ($file_name_matched eq "") || ($directory_name_untar) eq "" ) {
        print "untar package file before update configuration failed\n";
        say LOG_FILE "untar package file before update configuration failed";
        close LOG_FILE;
        exit 1;
    }

    &update_config_properties_under_directory($service_update,$directory_name_untar);

    say LOG_FILE "package file $file_name_matched will be generated after update configuration";
    chdir($directory_packages);
    $running_command = "tar -zcf $file_name_matched $directory_name_untar";
    unless ( system("$running_command") == 0 ) {
        print "ERROR! generate package file by command [$running_command] failed\n";
        say LOG_FILE "ERROR! generate package file by command [$running_command] failed";
        close LOG_FILE;
        exit 1;
    } else {
        system("rm -rf $directory_name_untar");
    }
    say LOG_FILE "update package file $file_name_matched finished";
    print "update package file $file_name_matched finished\n";
}


sub check_property_value_among_range {
    (my $tmp_value, my $tmp_range) = @_;
    my @array_tmp = split /;/, $tmp_range;
    if ( grep {$_ eq $tmp_value} @array_tmp ) {
        return "pass";
    } else {
        return "fail: out of range";
    }
}


# this function is used to check platform type and update if necessary
# 
#
sub check_update_platform_type {
    my $center_dih_list = $config_tree_deploy_properties->{'DIH'}{'center'}{'host'}{'list'};
    my @array_tmp = &Public_storage::get_ip_array_from_string($center_dih_list);
    my $center_dih_host = $array_tmp[0];

    my $ping_result = &Public_storage::operation_ping($center_dih_host);
    if ($ping_result eq "fail" ) {
        say LOG_FILE "DIH center host : $center_dih_host can't be accessed !!!";
        close LOG_FILE;
        die "DIH center host : $center_dih_host can't be accessed !!!\n";
    }

    my $login_user = $config_tree_deploy_properties->{'remote'}{'user'};
    my $login_passwd = $config_tree_deploy_properties->{'remote'}{'password'};
    say LOG_FILE "get login info($login_user/$login_passwd) from file($file_deploy_properties)";

    my $os_info = &Public_storage::get_host_os_info($login_user, $login_passwd, $center_dih_host);
    if ($os_info =~ "fail") {
        say LOG_FILE "get host [center_dih_host] OS information with message : $os_info";
    } else {
        say LOG_FILE "OS information on host[ $center_dih_host ] is:$os_info";
    }
    my $type_platfrom = "x86_64";
    if ( $os_info =~ "CentOS" ) {
        $type_platfrom = "x86_64";
    } else {
        $type_platfrom = $os_info;
    }

    if ( $type_platfrom eq $remote_platform ) {
        say LOG_FILE "Don't need to update remote.platform [$remote_platform] in file $file_deploy_properties";
    } else {
        say LOG_FILE "update remote.platform from $remote_platform to $type_platfrom in file $file_deploy_properties";
        $remote_platform = $type_platfrom;
        system ("sed -i 's#^remote.platform=.*#remote.platform=$type_platfrom#' $file_deploy_properties ");
    }
}


# this function is used to update specify so and jar file to directory pack_libs/lib/
#
sub update_platform_so_jar_files {
    opendir(DIR_SO, $directory_so_files);
    closedir DIR_SO;
    return "success";
}

sub usage_update_local_packages {
    $string_usage = "\nUsage:\n";
    $string_usage = $string_usage."\t--service|-s (service name like: console, datanode, instancehub and so on)\n";
    $string_usage = $string_usage."example:\n";
    $string_usage = $string_usage."\tbin/update_system_config.pl (all local packages will be updated)\n";
    $string_usage = $string_usage."\tbin/update_system_config.pl -s console (only console package will be updated)\n\n";
    return $string_usage;
}

sub show_step_information {
    (my $message, my $tmp_index) = @_;
    chomp($time_stamp=localtime());
    say LOG_FILE "-------------------------------------------------------------------------------";
    print LOG_FILE "step[update-system-config] $tmp_index : $message [$time_stamp]\n";
    say LOG_FILE "-------------------------------------------------------------------------------";
    print "step[update-system-config] $tmp_index : $message [$time_stamp]\n";
}






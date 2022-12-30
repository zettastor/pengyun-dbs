#!/usr/bin/perl
# this script is used to make package

# 20221229 - haiqinma - refactor for open source

use strict;
use warnings;

use FindBin qw($RealBin);
use lib "$RealBin";
use lib "$RealBin/../lib/perl5";

use Data::Dumper;
use File::Basename;
use File::Spec;
use Getopt::Long;
use POSIX;
use XML::Simple;

use Public_storage;

my $company_name="pengyun";
$company_name =~ s/\s//g;

my $target_directory = undef;
my $package_type = "OS";
my $platform_type = "x86";
my $value_md5 = undef;
GetOptions ("d:s"   => \$target_directory,
            "v=s" => \$package_type,
            "p:s" => \$platform_type,
            "m+"=>\$value_md5
            );
unless ( defined $target_directory ) {
    $target_directory = "/tmp";
    print "the target directory is not specified. Using the default location ($target_directory)\n";
}

$package_type = lc($package_type);
# my @array_product_avaliable_type = qw{internal release os};
# unless ( grep {$_ eq $package_type} @array_product_avaliable_type) {
#   print "the specified package type [$package_type] is not supported\n";
#   &usage();
#   exit 1;
# }
if ( $package_type ne "os" ) {
    print "the specified package type should be 'OS' or 'os' for opensource product\n";
    &usage();
    exit 1;
}

$platform_type = lc($platform_type);
my @array_package_suitable_type = qw{x86 all kylin uos};
unless ( grep {$_ eq $platform_type} @array_package_suitable_type) {
  print "the specified platform type [$platform_type] is not supported\n";
  &usage();
  exit 1;
}

my $xml_simple = XML::Simple->new();
my $tmp_file = File::Spec->catfile($RealBin, "../pom.xml");
my $properties_tree = $xml_simple->XMLin($tmp_file);
my $package_version = $properties_tree->{'parent'}{'version'};

my $step_index = 1;
print "step[create package] $step_index : package type: $package_type; package version: $package_version; platform: $platform_type\n";


my $running_command = undef;
$step_index++;
chomp(my $time_stamp=localtime());
print "step[create package] $step_index : prepare package directory($target_directory)\n";
my $directory_name_package_deploy = File::Spec->catfile($target_directory, "$company_name-deploy");
if ( -e $directory_name_package_deploy ) {
    print "clear file or directory($directory_name_package_deploy)";
    $running_command = "rm -rf $directory_name_package_deploy";
    (system($running_command) == 0) or die "ERROR: cannot remove directory $directory_name_package_deploy\n";
}
$running_command = "mkdir -p $directory_name_package_deploy";
(system($running_command) == 0) or die "ERROR: cannot create directory $directory_name_package_deploy\n";


my $tmp_source_directory = $RealBin;
my $tmp_target_directory = File::Spec->catfile($directory_name_package_deploy, "bin");
$step_index++;
print "step[create package] $step_index : prepare files under directory[$company_name-deploy/bin]\n";
$running_command = "mkdir -p $tmp_target_directory";
(system($running_command) == 0) or die "ERROR: cannot create directory $tmp_target_directory\n";
# sort by name - lower case
my @file_list_bin = (
    "crontab_check_host_space.pl",
    "crontab_check_service.pl",
    "daemonClient.pl",
    "deploy.pl",
    "deployment-daemon.pl",
    "getProcessPM.sh",
    "make-perl-lib.pl",
    "update_system_config.pl",
    "Public_storage.pm",
    "storectl.pl",
    "zookeeper.pl",
);
foreach ( @file_list_bin ) {
    $tmp_file = File::Spec->catfile($tmp_source_directory, $_);
    $running_command = "cp -a $tmp_file $tmp_target_directory";
    (system($running_command) == 0) or die "ERROR: cannot copy file $_ to directory [bin] \n";
}

if ($package_type eq "release") {
    $tmp_file = File::Spec->catfile($RealBin, "../pengyun-utils/target/Deployment-release.jar");
} else {
    $tmp_file = File::Spec->catfile($RealBin, "../pengyun-utils/target/Deployment.jar");
}
$running_command = "cp -a $tmp_file $tmp_target_directory";
(system($running_command) == 0) or die "ERROR: cannot copy file $tmp_file to directory [bin] \n";


$tmp_source_directory = File::Spec->catfile($RealBin, "../resources/config");
$tmp_target_directory = File::Spec->catfile($directory_name_package_deploy, "config");
$step_index++;
print "step[create package] $step_index : prepare files under directory[$company_name-deploy/config]\n";
$running_command = "mkdir -p $tmp_target_directory";
(system($running_command) == 0) or die "ERROR: cannot create directory $tmp_target_directory\n";
# sort by name - lower case
my @file_list_config = (
    "deploy.properties",
    "module_settings.xml",
    "zookeeper.properties",
);
foreach ( @file_list_config ) {
    $tmp_file = File::Spec->catfile($tmp_source_directory, $_);
    $running_command = "cp -a $tmp_file $tmp_target_directory";
    (system($running_command) == 0) or die "ERROR: cannot copy file $_ to directory [config] \n";
}


$tmp_source_directory = File::Spec->catfile($RealBin, "../resources/lib_src");
$tmp_target_directory = File::Spec->catfile($directory_name_package_deploy, "lib_src");
$step_index++;
print "step[create package] $step_index : prepare files under directory[$company_name-deploy/lib_src]\n";
$running_command = "mkdir -p $tmp_target_directory";
(system($running_command) == 0) or die "ERROR: cannot create directory $tmp_target_directory\n";
$running_command = "cp -a $tmp_source_directory/* $tmp_target_directory";
(system($running_command) == 0) or die "ERROR: cannot copy lib source file to directory [lib_src] \n";


$tmp_target_directory = File::Spec->catfile($directory_name_package_deploy, "logs");
$step_index++;
print "step[create package] $step_index : prepare files under directory[$company_name-deploy/logs]\n";
$running_command = "mkdir -p $tmp_target_directory";
(system($running_command) == 0) or die "ERROR: cannot create directory $tmp_target_directory\n";


$tmp_target_directory = File::Spec->catfile($directory_name_package_deploy, "packages");
$step_index++;
print "step[create package] $step_index : prepare files under directory[$company_name-deploy/packages]\n";
$running_command = "mkdir -p $tmp_target_directory";
(system($running_command) == 0) or die "ERROR: cannot create directory $tmp_target_directory\n";

# module name => directory name where to get module package
# sorted by module name
my %module_to_directory_name = (
    console => 'pengyun-console',
    coordinator => 'pengyun-coordinator',
    datanode => 'pengyun-datanode',
    deployment_daemon => 'pengyun-deployment_daemon',
    drivercontainer => 'pengyun-drivercontainer',
    infocenter => 'pengyun-infocenter',
    utils => 'pengyun-utils',
);

foreach my $module_name (sort keys %module_to_directory_name) {
    $tmp_source_directory = File::Spec->catfile($RealBin, "../$module_to_directory_name{$module_name}","target");
    $running_command = "find $tmp_source_directory -name '*.tar.gz' 2>&1";
    my $tmp_results = `$running_command`;
    my @tmp_array = split /\n/, $tmp_results;
    $tmp_file = undef;
    foreach (@tmp_array) {
        my $filename = (split /\//, $_)[-1];
        # print "check file: $filename\n";
        if ( ($package_type eq "os") && ( $filename =~ "OS" ) ) {
            $tmp_file = $_;
            last;
        }elsif ( ( $filename !~ "OS" ) && ( $filename =~ "$package_type" ) ) {
            $tmp_file = $_;
            last;
        }
    }
    if (defined $tmp_file) {
        print "copy file $tmp_file to directory [packages]\n";
        $running_command = "cp -a $tmp_file $tmp_target_directory";
        (system($running_command) == 0) or die "ERROR: cannot copy $module_name package file to directory [packages] \n";
    }
}

$tmp_source_directory = File::Spec->catfile($RealBin, "../resources/third_party_packages");
# sort by name - lower case
my @file_list_third_party_packages = (
    "zookeeper-3.4.6.tar.gz",
);
foreach ( @file_list_third_party_packages ) {
    $tmp_file = File::Spec->catfile($tmp_source_directory, $_);
    $running_command = "cp -a $tmp_file $tmp_target_directory";
    (system($running_command) == 0) or die "ERROR: cannot copy third_party_package file $_ to directory [packages] \n";
}

$tmp_source_directory = File::Spec->catfile($RealBin, "../resources/service_components");
# sort by name - lower case
my @array_service_components = (
    "instancehub",
);
my $package_version_only_number = (split /-/, $package_version)[0];
my $dih_expected_file_name = "pengyun-instancehub-$package_version_only_number-OS-release.tar.gz";
$tmp_file = File::Spec->catfile($tmp_source_directory, $dih_expected_file_name);
unless ( -f $tmp_file) {
    print "there is no expected file[$dih_expected_file_name] under directory[$tmp_source_directory]\n";
    print "The download may take several minutes, depending on your network speed...\n";
    my $url_location = "https://github.com/zettastor/dbs/releases/download/$package_version_only_number/pengyun-instancehub-$package_version_only_number-OS-release.tar.gz";
    print "You may down file[$url_location] manually, and put it under directory $tmp_source_directory\n";
    $running_command = "cd $tmp_source_directory; wget $url_location; cd -";
    system($running_command);
}

opendir(DIR, $tmp_source_directory) || die "ERROR: cannot open directory [$tmp_source_directory] \n";
my @tmp_array = readdir(DIR);
closedir(DIR);
foreach ( @tmp_array ) {
    # print "check file: $_\n";
    $tmp_file = undef;
    unless(/tar.gz/) {
        next;
    }
    (my $module_name, my $module_version )= (split /-/, $_)[1,2];
    unless (grep {$_ eq $module_name} @array_service_components) {
        next;
    }
    unless ($module_version eq $package_version_only_number) {
        print "skip file[$_] as version[$module_version] is not as expected[$package_version_only_number]\n";
        next;
    }

    if ( ($package_type eq "os") && (/OS/) ) {
        $tmp_file = File::Spec->catfile($tmp_source_directory, $_);
    }elsif ( ($_ !~ "OS" ) && (/$package_type/) ) {
        $tmp_file = File::Spec->catfile($tmp_source_directory, $_);
    }
    if (defined $tmp_file) {
        print "copy service_components file $tmp_file to directory [packages]\n";
        $running_command = "cp -a $tmp_file $tmp_target_directory";
        (system($running_command) == 0) or die "ERROR: cannot copy service_components file $_ to directory [packages]\n";
    }
}


if ( ($platform_type eq "x86") || ($platform_type eq "all") ) {
    $tmp_source_directory = File::Spec->catfile($RealBin, "../resources/kernel_file");
} else {
    $tmp_source_directory = undef;
}
$tmp_target_directory = File::Spec->catfile($directory_name_package_deploy, "resources");
$step_index++;
print "step[create package] $step_index : prepare files under directory[$company_name-deploy/resources]\n";
$running_command = "mkdir -p $tmp_target_directory";
(system($running_command) == 0) or die "ERROR: cannot create directory $tmp_target_directory\n";
# sort by name - lower case
my @file_list_resources = (
    "libjnotify.so",
    "liblinux-async-io.so",
    "libudpServer.so",
);
foreach ( @file_list_resources ) {
    unless ( defined $tmp_source_directory ) {
        die "ERROR: cannot get correct kernel files as specified platform type ($platform_type)\n";
        last;
    }
    $tmp_file = File::Spec->catfile($tmp_source_directory, $_);
    $running_command = "cp -a $tmp_file $tmp_target_directory";
    (system($running_command) == 0) or die "ERROR: cannot copy file $_ to directory [resources] \n";
}


$step_index++;
print "step[create package] $step_index : All files are ready. Create deploy package now......\n";

my $timestamp_package = strftime("%Y-%m-%d_%H-%M-%S", localtime);
my $deploy_package_name = "$company_name-deploy-$package_version_only_number-OS-[$timestamp_package].tar.gz";
print "package name: $deploy_package_name\n";

$running_command = "cd $target_directory; tar zcf $deploy_package_name $company_name-deploy ";
(system($running_command) == 0) or die "ERROR: cannot create package file $deploy_package_name \n";
$tmp_file = File::Spec->catfile($target_directory, $deploy_package_name);
if (-f $tmp_file) {
    print "deploy package is ready: $tmp_file\n";
}
if (defined $value_md5) {
    my $filename_md5 = $deploy_package_name.".md5";    
    $running_command = "cd $target_directory; md5sum $deploy_package_name > $filename_md5 ";
    system($running_command);
    $tmp_file = File::Spec->catfile($target_directory, $filename_md5);
    if (-f $tmp_file) {
        print "deploy package MD5SUM file: $tmp_file\n";
    } else {
        die "ERROR: cannot generate package MD5SUM file $tmp_file \n";
    }
}

$step_index++;
print "step[create package] $step_index : Create deploy package done.\n";
print "----------------------------------------------------------------\n";
exit 0;


sub usage {
    print "input like this : perl bin/CreateDeployPackage.pl -d package_location -v [OS/release/internal]\n";
    print "if you want to get value_md5 value of package, add -m option.\n";
    print "if package would used on other platform besides x86, add  -p [all/Kylin_V10_kernel4.19.90_aarch64/UOS20_kernel4.19.0_mips64] option.\n";
    print "For example:  \n";
    print "    perl bin/CreateDeployPackage.pl -d /tmp     #generate package for opensource under directory /tmp \n";
    print "    perl bin/CreateDeployPackage.pl -d /tmp -m     #generate package under directory /tmp  with md5 check file\n";
    print "    perl bin/CreateDeployPackage.pl -v release -p all     #generate package with proguard and suitable for all platform \n";
}


#!/usr/bin/perl
# script name: proguard
# @auther zjm
#

use strict;
use warnings;
use FindBin '$RealBin';

my $my_script_dir = $RealBin;
#my $proguard = "$my_script_dir/proguard/lib/proguard.jar";
my $proguard = "$my_script_dir/../resources/third_party_packages/proguard.jar";
my $main_dir = "$my_script_dir/..";

my $group = "pengyun";
my $jar_postfix = ".jar";
my $release_jar_postfix = "release.jar";
my $internal_tar_postfix = "internal.tar.gz";
my $release_tar_postfix = "release.tar.gz";
my $internal_postfix = "internal";
my $release_postfix = "release";
my $tar_postfix = "tar.gz";

my %service_name = (
    console => "console",
    infocenter => "infocenter",
    controlcenter => "controlcenter",
    coordinator => "coordinator",
    drivercontainer => "drivercontainer",
    instancehub => "instancehub",
    datanode => "datanode",
    ddserver => "deployment_daemon",
    utils => "utils",
    monitorserver => "monitor_server",
    sysdaemon => "system_daemon",
    fs_server => "fs_server",
    fs_fuse => "fs_fuse"
);

my %lib_name = (
    models => "models",
    dnmodel => "dnmodel",
    dncore => "datanode_core",
    dnservice => "datanode_service",
    dnservice_impl => "datanode_service_impl",
    models_related => "models_related",
    core => "core",
    iscsi => "iscsi",
    license => "license",
    querylog => "query_log",
    driver_core => "driver_core",
    coordinator => "coordinator",
    database_core => "database_core",
    fs_core => "fs_core",
    instancehub_service => "instancehub_service",
);

my $argv_count = @ARGV;
if ($argv_count eq 0 || $argv_count gt 3) {
   die &usage();
}

if ($ARGV[0] eq 'off') {
   die "\n\n========================= proguard has been disabled ==========================\n\n";
}

my $version = $ARGV[2];


if ($ARGV[1] eq 'all') {
    foreach (keys %service_name) {
        my $service_name_key = $_;
        &obfuscate_some_service($service_name{$service_name_key});
    }
} elsif ($ARGV[1] eq $service_name{"console"}) {
    &obfuscate_some_service($service_name{"console"});
} elsif ($ARGV[1] eq $service_name{"infocenter"}) {
    &obfuscate_some_service($service_name{"infocenter"});
} elsif ($ARGV[1] eq $service_name{"controlcenter"}) {
    &obfuscate_some_service($service_name{"controlcenter"});
} elsif ($ARGV[1] eq $service_name{"coordinator"}) {
    &obfuscate_some_service($service_name{"coordinator"});
} elsif ($ARGV[1] eq $service_name{"instancehub"}) {
    &obfuscate_some_service($service_name{"instancehub"});
} elsif ($ARGV[1] eq $service_name{"datanode"}) {
    &obfuscate_some_service($service_name{"datanode"});
} elsif ($ARGV[1] eq $service_name{"ddserver"}) {
    &obfuscate_some_service($service_name{"ddserver"});
} elsif ($ARGV[1] eq $service_name{"utils"}) {
    &obfuscate_some_service($service_name{"utils"});
} elsif ($ARGV[1] eq $service_name{"drivercontainer"}) {
    &obfuscate_some_service($service_name{"drivercontainer"});
} elsif ($ARGV[1] eq $service_name{"monitorserver"}) {
      &obfuscate_some_service($service_name{"monitorserver"});
} elsif ($ARGV[1] eq $service_name{"sysdaemon"}) {
    &obfuscate_some_service($service_name{"sysdaemon"});
} elsif ($ARGV[1] eq $service_name{"fs_server"}) {
    &obfuscate_some_service($service_name{"fs_server"});
} elsif ($ARGV[1] eq $service_name{"fs_fuse"}) {
        &obfuscate_some_service($service_name{"fs_fuse"});
} else {
    die &usage();
}

sub usage() {
    print "----> $argv_count\n";
    my $services = "";
    foreach my $service_name_key(keys %service_name) {
        $services = $services." | ".$service_name{$service_name_key};
    }
    return "Usage: ./proguard on/off all$services version\n";
}

sub obfuscate_some_service {
    my ($service_name) = @_;

    print("### Going to obfuscate service $service_name\n");

    print("\n### Step 1: untar service target package\n");
    my $service_dir = get_service_dir($service_name);

    print("\n########service_dir $service_dir \n");
    chdir("$main_dir/$service_dir/target");
    my $internal_tar = get_internal_tar($service_name);

    print("\n#######internal_tar $internal_tar \n");
    system("tar -xf $internal_tar ");

    print("\n### Step 2: remove testing classes\n");
    my $untar_dir = get_untar_dir($service_name);

    print("\n########untar_dir $untar_dir \n");

    if ($service_name eq $service_name{"console"}) {
        chdir("$main_dir/$service_dir/target/$untar_dir/tomcat/webapps/ROOT/WEB-INF/lib/");
    } else {
        chdir("$main_dir/$service_dir/target/$untar_dir/lib");
    }
    system("rm pengyun*test*.jar");

=pop
    if ($service_name eq $service_name{"datanode"}) {
        die "*** Please make sure done datanode perl script obfuscation! ***\n" unless -e "/tmp/dn_scripts_obs/success123456789";
        open IGNORE, "<$main_dir/$service_dir/ignorable_scripts";
        my @ignorable_scripts = ();
        foreach my $ignorable_script(<IGNORE>) {
            chomp($ignorable_script);
            push @ignorable_scripts, $ignorable_script;
        }
        close IGNORE;
        opendir SCRIPT_DIR, "$main_dir/$service_dir/target/$untar_dir/bin";
        my @scripts = readdir(SCRIPT_DIR);
        closedir SCRIPT_DIR; 

        chdir("$main_dir/$service_dir/target/$untar_dir/bin");
        foreach my $script(@scripts) {
            if (grep(/^$script$/, @ignorable_scripts)) {
                print("rm $script\n");
                system("rm $script");
            }
        }
        chdir("/tmp/dn_scripts_obs");
        foreach my $script(@scripts) {
            if (grep(/^$script$/, @ignorable_scripts)) {
                print("rm $script\n");
                system("rm $script");
            }
        }
        system("perl -pi -e \'tr[\\r][]d\' *");
        system("cp -f * $main_dir/$service_dir/target/$untar_dir/bin");
    }
=cut

    print("\n### Step 3: obfuscate service with proguard\n");
    chdir("$main_dir/$service_dir");
    (system("java -Dproject.version=$version -jar $proguard \@proguard.conf ") == 0) or die "*** ERR: something wrong during proguard ***";

    print("\n### Step 4: remove original service jar file\n");
    if ($service_name eq $service_name{"console"}) {
        chdir("$main_dir/$service_dir/target/$untar_dir/tomcat/webapps/ROOT/WEB-INF/lib/");
        foreach (keys %lib_name) {
            my $lib_key = $_;
            my $jar = get_jar($lib_name{$lib_key});
            my $release_jar = get_release_jar($lib_name{$lib_key});
            print("removing original lib $jar\n");
            system("mv $release_jar $jar");
        }
        chdir("$main_dir/$service_dir/target/$untar_dir/tomcat/webapps/ROOT/WEB-INF/");
        print("removing original classes\n");
        system("rm -r classes");
        system("mv classes-release classes");
    } else {
        chdir("$main_dir/$service_dir/target/$untar_dir/lib");
        foreach (keys %lib_name) {
            my $lib_key = $_;
            my $jar = get_jar($lib_name{$lib_key});
            my $release_jar = get_release_jar($lib_name{$lib_key});
            print("removing original lib $jar\n");
            system("mv $release_jar $jar");
        }
        my $service_jar = get_jar($service_name);
        my $service_release_jar = get_release_jar($service_name);
        print("removing original $service_jar\n");
        system("mv $service_release_jar $service_jar");

        if ($service_name eq $service_name{"utils"}) {
            my @utils = ("instance_viewer", "deployment");
            my %main_classes = (
                instance_viewer => "py.utils.dih.Launcher",
                deployment      => "py.deployment.client.OperationHandler"
            );
            my %jar_name = (
                instance_viewer => "instances_viewer-release.jar",
                deployment      => "Deployment-release.jar"
            );
            my %origin_jar_name = (
                instance_viewer => "instances_viewer.jar",
	        deployment      => "Deployment.jar"
	    );
            foreach my $util(@utils) {
                chdir("$main_dir/$service_dir/target/$untar_dir/lib");
                print("create $util in version release\n");
                my $utils_lib_tmp = "/tmp/utils-lib/";
                my $utils_classes_tmp = "/tmp/utils-classes/";
                system("rm -r $utils_lib_tmp") if -e $utils_lib_tmp;
                system("mkdir $utils_lib_tmp");
                system("cp -rf * $utils_lib_tmp");

                chdir("$utils_lib_tmp");
                opendir(DES_DIR, "$utils_lib_tmp") or die $!;
                my @jars_list = readdir(DES_DIR);
                foreach my $jar(@jars_list) {
                    system("jar -xf $jar") if $jar =~ m/.*.jar/;
                }
                closedir(DES_DIR);

                opendir(DES_DIR, "$utils_lib_tmp");
                my @items_list = readdir(DES_DIR);
                system("rm -r thrift-model");
                system("rm -r META-INF");
                foreach my $item(@items_list) {
                    $item =~ s/\n//g;
                    next if $item eq "\.\.";
                    next if $item eq "\.";
                    system("rm $item") if $item =~ m/.*.jar/; 
                }
                closedir(DES_DIR);

                my $manifest_file = "MANIFEST.MF";
                open(MANIFEST, ">>$manifest_file") or die $!;
                print MANIFEST "Main-Class: ".$main_classes{$util}."\n";
                close(MANIFEST);

		chdir("$main_dir/$service_dir/target/");
		my $internal_jar_unziped_dir = "$main_dir/$service_dir/target/internal"; 
                print "---------------->current origin jar file name is :". $origin_jar_name{$util}."\n";
		system("unzip -d $internal_jar_unziped_dir $origin_jar_name{$util}");
		system("rm -rf $internal_jar_unziped_dir/py");
		system("cp -r $utils_lib_tmp/py $internal_jar_unziped_dir/");
		system("cp -r $utils_lib_tmp/somanyclasses $internal_jar_unziped_dir");

		chdir($internal_jar_unziped_dir);
                my $new_jar = $jar_name{$util};
                system("jar -cmf ./META-INF/$manifest_file $new_jar *");
                system("cp $new_jar $main_dir/$service_dir/target");
 
		chdir("$main_dir/$service_dir/target/");
		system("rm -rf $internal_jar_unziped_dir");
            }
        }
    }

    print("\n### Step 5: compress obfuscated service jar files to release version\n");
    chdir("$main_dir/$service_dir/target");
    my $release_tar = get_release_tar($service_name);
    system("tar -zcf $release_tar $untar_dir");
    system("rm -r $untar_dir");
}

sub get_jar {
    my ($service_name) = @_;
    if ($service_name eq $lib_name{"iscsi"}) {
        return "target-2.5.1-SNAPSHOT.jar";
    }
    return $group.'-'.$service_name.'-'.$version.$jar_postfix;
}

sub get_release_jar {
    my ($service_name) = @_;
    if ($service_name eq $lib_name{"iscsi"}) {
        return "target-2.5.1-SNAPSHOT-release.jar";
    }
    return $group.'-'.$service_name.'-'.$version.'-'.$release_jar_postfix;
}

sub get_internal_tar {
    my ($service_name) = @_;

    if (($service_name eq $service_name{"coordinator"}) || ($service_name eq $service_name{"fs_server"})) {
        my $service_dir = get_service_dir($service_name);
        opendir(DES_DIR, "$main_dir/$service_dir/target");
        my @items_list = readdir(DES_DIR);
        foreach my $item(@items_list) {
            if ($item =~ m/$group\-$service_name.*tar\.gz/) {
                closedir(DES_DIR);
                my $timestamp = substr($item, length($item)-21, 14);
                print("\nget_internal_tar $timestamp");
                return $group.'-'.$service_name.'-'.$version.'-'.$internal_postfix.'-'.$timestamp.'.'.$tar_postfix;
            }
        }
        print("\n coordinator package fail please check!");
        closedir(DES_DIR);
    }

    return $group.'-'.$service_name.'-'.$version.'-'.$internal_tar_postfix;
}

sub get_release_tar {
    my ($service_name) = @_;

         if (($service_name eq $service_name{"coordinator"}) || ($service_name eq $service_name{"fs_server"})) {
            my $service_dir = get_service_dir($service_name);
            opendir(DES_DIR, "$main_dir/$service_dir/target");
            my @items_list = readdir(DES_DIR);
            foreach my $item(@items_list) {
                if ($item =~ m/$group\-$service_name.*tar\.gz/) {
                    closedir(DES_DIR);
                    my $timestamp = substr($item, length($item)-21, 14);
                    print("\n get_release_tar $timestamp");
                    return $group.'-'.$service_name.'-'.$version.'-'.$release_postfix.'-'.$timestamp.'.'.$tar_postfix;
                }
            }
            print("\n coordinator package fail please check!");
            closedir(DES_DIR);
        }

    return $group.'-'.$service_name.'-'.$version.'-'.$release_tar_postfix;
}

sub get_service_dir {
    my ($service_name) = @_;
    return $group.'-'.$service_name;
}

sub get_untar_dir {
    my ($service_name) = @_;
    return $group.'-'.$service_name.'-'.$version;
}

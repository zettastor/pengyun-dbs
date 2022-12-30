#!/usr/bin/perl
# this script is used to update the code version and timestamp in files  pengyun-*/src/main/resources/config/*.properties
# author Ma Haiqing
# version information as follows :
# 20151015 - first version
# 20151118 - fix the bug sometimes these adding information are not on a new line
# 20160507 - haiqinma - add pengyun-system_monitor
# 20160509 - tyr - refactor : 
#                  change name from update_version_and_timestamp.pl to manifest.pl
#                  get the latest commit from git and save it to a manifest file which will be delievered to remote, we do not use the properties file any more

use strict;
use warnings;

use FindBin '$Bin';
use File::Spec;
use File::Basename;
use Cwd;

use constant MANIFEST_PATH => "src/main/resources/";

my %manifest_information = (
	current_branch  => "unknown",
	last_commit => "unknown",
    git_status => "unknown",
	build_timestamp => "unknown",
);


print "---------------updating manifest------------------\n";
# validate that the script is being run in a right dir
&validate_current_dir;

# get current time, last commit and current branch
my $current_time = &get_current_time_stamp();
my $last_commit = &get_last_commit;
my $git_status = `git status`;
my $current_branch = &get_current_branch;

$manifest_information{"git_status"} = $git_status;
$manifest_information{"last_commit"} = $last_commit;
$manifest_information{"build_timestamp"} = $current_time;
$manifest_information{"current_branch"} = $current_branch;

# create or update manifest file 
my $manifest_file;
if (cwd() =~ /pengyun-console/) {
    my $console_manifest_path = "pengyun-console-$ARGV[0]";
    $manifest_file = File::Spec->catfile(cwd(), $console_manifest_path, "manifest.mf");
} else {
    $manifest_file = File::Spec->catfile(cwd(), MANIFEST_PATH, "manifest.mf");
}
`touch $manifest_file` unless -e $manifest_file;
open (MANIFEST, ">$manifest_file") or die ("cannot open file $manifest_file");
foreach my $key (keys(%manifest_information)) {
    print MANIFEST "$key :\n{\n";
    my $value = $manifest_information{$key};
    my @value_lines = split(/\n/, $value);
    foreach (@value_lines) {
        chomp($_);
        print MANIFEST "\t$_\n";
    }
    print MANIFEST "}\n";
}
close (MANIFEST);

print "\n====update timestamp and branch information finished ! ==== \n";
exit 0;

# functions
sub get_current_branch() {
    my @branch_information = `git branch`;
	my $line;
	foreach  $line (@branch_information) {
		chomp($line);
		if ( $line =~ /^\*\s.*/) {
			($current_branch = $line) =~ s/^\*\s(\w+)/$1/g; 
			#print "The current branch information is : $current_branch \n";
			last;
		}
	}
	return $current_branch;
}

sub get_current_time_stamp {
    my $current_time = time();
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($current_time);
    $year += 1900;
    $mon ++;
    $min  = '0'.$min  if length($min)  < 2;
    $sec  = '0'.$sec  if length($sec)  < 2;
    $mon  = '0'.$mon  if length($mon)  < 2;
    $mday = '0'.$mday if length($mday) < 2;
    $hour = '0'.$hour if length($hour) < 2;
    my $weekday = ('Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday')[$wday];
    return "$year-$mon-$mday-$hour:$min:$sec-$weekday";
}

sub get_last_commit {

    my $last_commit = &get_git_log;

    if (cwd() =~ /pengyun-datanode/) {
        my $cwd = cwd();
        chdir("$cwd/../pengyun-datanode_binary");
        my $binary_commit = "binary commit : \n\n".&get_git_log;
        $last_commit = $last_commit.$binary_commit;
        chdir($cwd);
    }

    return $last_commit;
}

sub get_git_log {
    open(GIT_LOG, "git log |") or die ("can not get git log");
    my $git_log = "";
    my $commitId = <GIT_LOG>;
    $git_log = $git_log.$commitId;
    my $tmpLine;
    while($tmpLine = <GIT_LOG>) {
        last if ($tmpLine =~ /^commit/);
        $git_log = $git_log.$tmpLine;
    }
    close(GIT_LOG);
    return $git_log;
}

sub validate_current_dir {
    my $current_dir = basename(cwd());
    print("you are compiling [$current_dir]\n");
    open(GIT_REMOTE, "git remote -v |") or die ("you are not in a git dir ?");
    my $remote_version;
    while($remote_version = <GIT_REMOTE>) {
        chomp($remote_version);
        die ("you are in a wrong dir") unless $remote_version =~ /$current_dir/;
    }
}


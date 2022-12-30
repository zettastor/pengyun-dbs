#!/usr/bin/perl
package Public_storage;
use strict;
use warnings;
use File::Spec;
use FindBin qw($Bin);
use POSIX qw(strftime);



# this function is used to get software list from ini file
# 2018-06-24
sub get_software_required_list {
    (my $file_fullname, my $tag) = @_;
    # print "filename: $file_fullname, tag: $tag\n";
    my @package_list=();
    my $find_tag="false";
    open(FILE, '<', "$file_fullname");
    while(<FILE>) {
        chomp;
        if (/^\s*$/ or /^;/) {
            next;
        } elsif (/^\[(.*)\]/) {
            if ( $tag eq $1 ) {
                $find_tag="true";
            } else {
                $find_tag="false";
            }
            next;
        }
        if ($find_tag eq "true" ) {
            push @package_list, $_;
        }
    }
    # print "get package list @package_list\n";
    return @package_list;
}


# this function is used to get an array of ip address from a string, which is split by ',' or ';'
#input 192.168.1.3:192.168.1.6,192,168,1,9
#output [192.168.1.3 192.168.1.4 192.168.1.5 192.168.1.6 192.168.1.9]
#output [0x0006] ip format error
#output [0x0007] ip range error, like 192.168.1.3:192.168.2.3
# 2018-06-26
sub get_ip_array_from_string () {
    (my $hostListStr) = @_;
    my @hosts;
    my @ip_split_by_comma = split(',',$hostListStr);
    foreach my $string_split_by_comma(@ip_split_by_comma) {
        if ( $string_split_by_comma =~ /:/ ) {
            my @tmp_array=&get_continuous_hosts($string_split_by_comma);
            if ("$tmp_array[0]" eq "0x0006") {
                @hosts=("0x0006");
                return @hosts;
            } elsif ("$tmp_array[0]" eq "0x0007") {
                @hosts=("0x0007");
                return @hosts;
            }
            push @hosts, @tmp_array;
        } else {
            my $tmp_str=&check_ip_format($string_split_by_comma);
            if ($tmp_str eq "0x0006") {
               @hosts=("0x0006");
               return @hosts;
            }
            push @hosts, &check_ip_format($string_split_by_comma);
        }
    }

    my %count = ();
    my @uniq_hosts = grep { ++$count{$_}<2; } @hosts;
    return sort @uniq_hosts;
}


# this function is used to remove repeate ip address from a string
#input ip string
#output: ip string
# 2018-08-03
sub remove_repeate_ip_from_string () {
    (my $hostListStr) = @_;
    my @array_host_ip = &get_ip_array_from_string($hostListStr);
    my $hostListStr_uniq = join ",",@array_host_ip;
    return $hostListStr_uniq;
}



#this function is used to get an array of ip address from a string
#input 192.168.1.3:192.168.1.6
#output [192.168.1.3 192.168.1.4 192.168.1.5 192.168.1.6]
#
sub get_continuous_hosts () {
    my $hostListStr = $_[0];
    my @hostParaArray = split(':',$hostListStr);
    my @continuous_host;

    my $lower_ip = $hostParaArray[0];
    $lower_ip = &check_ip_format($lower_ip);
    if ( $lower_ip eq "0x0006" ) {
        @continuous_host=("0x0006");
        return @continuous_host;
    }
    $lower_ip =~ m/(\b((([01]?\d\d?|2[0-4]\d|25[0-5])\.){3})([01]?\d\d?|2[0-4]\d|25[0-5]))\b/;
    my $prefix_lower_ip = $2;
    my $suffix_lower_ip = $5;

    my $upper_ip = $hostParaArray[1];
    $upper_ip = &check_ip_format($upper_ip);
    if ( $upper_ip eq "0x0006" ) {
        @continuous_host=("0x0006");
        return @continuous_host;
    }
    $upper_ip =~ m/(\b((([01]?\d\d?|2[0-4]\d|25[0-5])\.){3})([01]?\d\d?|2[0-4]\d|25[0-5]))\b/;
    my $prefix_upper_ip = $2;
    my $suffix_upper_ip = $5;

    if ( $prefix_upper_ip ne $prefix_lower_ip ) {
        print "ip $lower_ip to ip $upper_ip is cross $prefix_lower_ip"."255 or $prefix_upper_ip"."0. Please modify it!!\n";
        @continuous_host=("0x0007");
        return @continuous_host;
    }

    if ( $suffix_upper_ip < $suffix_lower_ip ) {
        my $tmp = $suffix_lower_ip;
        $suffix_lower_ip = $suffix_upper_ip;
        $suffix_upper_ip = $tmp;

        $tmp = $lower_ip;
        $lower_ip = $upper_ip;
        $upper_ip = $tmp;
    }

    push @continuous_host, $lower_ip;
    for (my $index = $suffix_lower_ip+1; $index < $suffix_upper_ip; $index++ ) {
        push @continuous_host, $prefix_lower_ip.$index;
    }
    push @continuous_host, $upper_ip;

    return @continuous_host;
}


#this function is used to ip information as ip address format or not
#input  : string
#output : ip address  - means format is right
#         0x0006  - ip format is not right
#
sub check_ip_format () {
    my ($ip_str) = (@_);
    $ip_str =~ s/\s//g;
    if ($ip_str =~ /(\b((([01]?\d\d?|2[0-4]\d|25[0-5])\.){3})([01]?\d\d?|2[0-4]\d|25[0-5]))\b/ ) {
        return $ip_str;
    } else {
        print "the format ip address $ip_str is not right!\n";
        return "0x0006";
    }
}


#this function is used to test given ip could be ping
#input  : host ip
#output : fail  - ping operation can't be accessed
#         ok    - ping operation could be accessed
#
sub operation_ping {
    my $ping_results = "fail";
    my $ping = `ping -i 0.5 -c 6 $_[0] | grep transmitted `;
    $ping =~ /packets transmitted,(.*)received/;
    my $received_count = $1;
    $received_count =~ s/\s//g;
    if ( $received_count >= 2 ) {
        $ping_results = "ok";
    } else {
        print "can't access host $_[0] or the net connection does not work well\n";
    }
    return $ping_results;
}


#this function is used to test given ip could be login by ssh
#input  : host ip
#output : ssh_fail  - default value
#         ssh_ok    - ssh ok
#         ssh_fail_command    - can't execute command
#         ssh_fail_user       - login don't as "root"
#
sub operation_ssh {
    (my $login_user, my $login_passwd, my $host_ip) = @_;

    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
    my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);

    $ssh->error and return "ssh_fail";
    (my $user_who, my $err_info) = $ssh->capture2({ timeout => 30 }, "whoami ");
    $ssh->error and return "ssh_fail_command";
    chomp($user_who);
    if ($user_who ne "root") {
        return "ssh_fail_user";
    }
    return "ssh_ok";
}


#this function is used to remove one ip from strings
#input  : remove ip and ip string
#output : ip string which have remove special ip
#
sub remove_special_ip_from_string {
    (my $remove_ip, my $hostListStr) = @_;
    my @array_host_all = &get_ip_array_from_string($hostListStr);
    if ( grep {$_ eq $remove_ip} @array_host_all) {
        my @array_host_new = ();
        foreach (@array_host_all) {
            if ($_ eq $remove_ip) {
                next;
            } else {
                push @array_host_new, $_;
            }
        }
        my $hostListStr_new = join ",",@array_host_new;
        return $hostListStr_new;
    } else {
        return $hostListStr;
    }
}


# this function used to get mask info like string
# input: bitnumber like 24
# output: sting like "255.255.255.0"
sub mask_info_bitnumber2string {
    (my $netmask_bitnumber) = @_;
    my $index_up = int($netmask_bitnumber/8);
    my $index_compute = $netmask_bitnumber % 8;
    my @array_bitvalue=qw{128 64 32 16 8 4 2 1};
    my $value_compute=0;
    for (my $index=0; $index<$index_compute;$index++) {
        $value_compute += $array_bitvalue[$index];
    }
    my @array_mask=qw{0 0 0 0};
    for (my $index=0; $index<$index_up;$index++) {
        $array_mask[$index]=255;
    }
    $array_mask[$index_up]=$value_compute;
    return join ".", @array_mask;
}


# this function used to get property valume from xml file
# input: property name , xml file
# output: property value
sub get_property_value_from_xml {
    (my $property_name, my $file) = @_;
    chomp(my $tmp_line = `sed -n '/property name=\"$property_name\"/p' $file`);
    my @tmp_array = split /\n/, $tmp_line;
    unless ( scalar(@tmp_array) == 1 ) {
        # body...
        return "null";
    }

    $tmp_line =~ s/\s+//g;
    $tmp_line =~ /value=\"(.+)\"/;
    unless ( defined $1) {
         # body...
         return "";
    }
    return $1;
}


# this function used to check file or directory exists or not on remote host
# input: login info and remoute
# output: file  directory or fail
sub check_remote_path_exists {
    (my $login_user, my $login_passwd, my $host_ip, my $remote_path) = @_;
    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
    my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);
    $ssh->error and return "fail: cann't access by ssh";
    $remote_path  =~ s/\s+//g;

    (my $remote_message, my $err_info) = $ssh->capture2({ timeout => 30 }, "stat $remote_path  2>&1");
    if ($remote_message =~ "No such file or directory") {
        return "fail: No such file or directory"
    }

    my @array_tmp = split /\n/, $remote_message;
    if ( $array_tmp[1] =~ "regular.* file") {
        return "file";
    } elsif( $array_tmp[1] =~ "directory") {
        return "directory";
    } else {
        return "fail: unclear";
    }
}


# this function used to delete file or directory on remote host
# input: login info and remoute
# output: success or fail
sub delete_remote_path {
    (my $login_user, my $login_passwd, my $host_ip, my $remote_path) = @_;
    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
    my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);
    $ssh->error and return "fail: cann't access by ssh";
    $remote_path  =~ s/\s+//g;

    (my $remote_message, my $err_info) = $ssh->capture2({ timeout => 30 }, "stat $remote_path  2>&1");
    if ($remote_message =~ "No such file or directory") {
        return "success";
    }

    my @array_tmp = split /\n/, $remote_message;
    if ( $array_tmp[1] =~ "regular.* file") {
        $ssh->system("unlink $remote_path");
        return "success";
    } elsif( $array_tmp[1] =~ "directory") {
        my $tmp_results = &delete_remote_directory($login_user, $login_passwd, $host_ip, $remote_path);
        return $tmp_results;
    } else {
        return "fail: unclear $remote_path";
    }
}


# this function used to delete directory on remote host
# input: login info and remoute
# output: success or fail
sub delete_remote_directory {
    (my $login_user, my $login_passwd, my $host_ip, my $remote_directory) = @_;
    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
    my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);
    $ssh->error and return "fail: cann't access by ssh";
    $remote_directory  =~ s/\s+//g;

    while(1) {
        (my $remote_message, my $err_info) = $ssh->capture2({ timeout => 30 }, "ls $remote_directory  2>&1");
        if ( $remote_message eq "") {
            $ssh->system("rmdir $remote_directory");
            # print "\ndelete directory $remote_directory";
            last;
        }
        my @array_remote = split /\s+/, $remote_message;
        foreach (@array_remote) {
            my $tmp_file = File::Spec->catfile($remote_directory,$_);
            # print "\n check: $tmp_file";
            (my $tmp_message, $err_info) = $ssh->capture2({ timeout => 30 }, "stat $tmp_file  2>&1");
            my @array_tmp = split /\n/, $tmp_message;
            if ( $array_tmp[1] =~ "regular.* file") {
                # print "\n delete file: $tmp_file";
                $ssh->system("unlink $tmp_file");
            } elsif( $array_tmp[1] =~ "directory") {
                # print "\n try delete directory: $tmp_file";
                &delete_remote_directory($login_user, $login_passwd, $host_ip, $tmp_file);
            } else {
                return "fail: unclear $tmp_file";
            }
        }
    }
    return "success";
}



# this function used to get files or sub directories on specify path
# input: specify path
# output: array(file or dirctory)
sub get_local_path_content {
    (my $local_path) = @_;
    my @path_content_list = ();
    opendir(DIR_SPECIFY, $local_path);
    foreach ( readdir(DIR_SPECIFY)) {
        # body...
        if ( $_ eq "." || $_ eq "..") { next; }
        push @path_content_list, $_;
    }
    closedir DIR_SPECIFY;
    return @path_content_list;
}



# this function used to check hostname has configured in /etc/hosts file or not
# input: login info and hostname
# output: true - hostname is in /etc/hosts file
#         fail: **** - hostname is not in /etc/hosts file
sub check_hostname_configured_in_hosts_file {
    (my $login_user, my $login_passwd, my $host_ip, my $hostname_str) = @_;
    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
    my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);
    $ssh->error and return "fail: cann't access by ssh";

    my $flag_hostname = "false";
    (my $remote_message, my $err_info) = $ssh->capture2({ timeout => 30 }, "grep $hostname_str /etc/hosts 2>&1");
    chomp($remote_message);
    my @tmp_array = split /\n/, $remote_message;
    foreach(@tmp_array) {
        my $tmp_line = (split /\s+/, $_)[-1];
        if ( $tmp_line eq $hostname_str) {
            $flag_hostname = "true";
            last;
        }
    }

    if ( $flag_hostname eq "false" ) {
        return "fail: no string $hostname_str found in hosts file";
    } else {
        return "true";
    }
}


# this function used to add [ipaddress hostname] to /etc/hosts file
# expected "/home/test" instead of "/home/test/" and "/home/test   "
# input: host login info and adding message
# return value:
#       success   - OK
#       fail:XXXX - fail reason
sub add_hostname_configured_in_hosts_file {
    (my $login_user, my $login_passwd, my $host_ip, my $add_hostip, my $add_hostname) = @_;

    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
    my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);
    $ssh->error and return "fail: cann't access by ssh";

    (my $remote_message, my $err_info) = $ssh->capture2({ timeout => 30 }, "grep $add_hostname /etc/hosts 2>&1 ");
    # $ssh->error and return "fail: remote command get content  /etc/hosts failed.";
    chomp($remote_message);
    if ($remote_message eq "") {
        $ssh->system("echo $add_hostip $add_hostname >> /etc/hosts");
        return "success";
    }

    my $flag_hostname = "false";
    my @tmp_array = split /\n/, $remote_message;
    foreach(@tmp_array) {
        my $tmp_hostip = (split /\s+/, $_)[0];
        my $tmp_hostname = (split /\s+/, $_)[-1];
        if ( ($tmp_hostip eq $add_hostip) && ($tmp_hostname eq $add_hostname) ) {
            $flag_hostname = "true";
            last;
        }
    }
    unless ( $flag_hostname eq "true" ) {
        # body...
        $ssh->system("echo $add_hostip $add_hostname >> /etc/hosts");
    }

    return "success";
}



# this function used to get specify service's status by command systemctl status ***
# input: service
# return value: unclear - there is no such service
#               ****    - active(running) or inactive(dead) and other values
sub get_service_status_by_systemctl {
    (my $service_name) = @_;
    my $status_value = "unclear";
    my $tmp_results = undef;
    chomp($tmp_results=`systemctl status $service_name`);
    my @tmp_array = split /\n/, $tmp_results;
    foreach ( @tmp_array ) {
        if ( /Active:/ ) {
            print "service [$service_name] status is : $_\n";
            if ( /since/ ) {
                $_ =~ m/Active:(.*)since/;
                $status_value = $1;
            } else {
                $_ =~ m/Active:(.*)/;
                $status_value = $1;
            }
            last;
        }
    }
    return $status_value;
}





# this function used to get remote host OS type and version  ***
# input: login information and host ip
# return value:
#         fail - os type can't deal with right now
#         CentOS7_1611 - version is CentOS7.3.1611
#         CentOS7_1908 - version is CentOS7.7.1908
#         CentOS8_1905 - version is CentOS8.0.1905
#         openSUSE_150 - version is openSUSE Leap 15.0
#         RedHat8_0    - version is Red Hat Enterprise Linux 8
#
# other platform:   OS-version_kernel-version-platform
#         Kylin_4.0.2_kernel4.15.0_aarch64 - TaiShan Kunpeng
#         Kylin_4.0.2_kernel4.4.58_aarch64 - PHYTIUM
#         NeoKylin_7.0_kernel4.14.0_aarch64 - TaiShan Kunpeng
sub get_host_os_info {
    (my $login_user, my $login_passwd, my $host_ip) = @_;

    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
    my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);
    $ssh->error and return "fail: cann't access by ssh";

    (my $os_type, my $err_info) = $ssh->capture2({ timeout => 30 }, "cat /etc/os-release | grep 'PRETTY_NAME' ");
    $ssh->error and return "fail: remote command get os version failed.";
    my $tmp_value = undef;
    my $os_info = undef;
    chomp($os_type);
    if ( $os_type =~ "CentOS") {
        ($tmp_value, $err_info) = $ssh->capture2({ timeout => 30 }, "cat /etc/centos-release 2>&1 ");
        $ssh->error and return "fail: remote command get os information on centos[$host_ip] failed.";
        chomp($tmp_value);
        $tmp_value =~ /((\d+.)+\d+)/g;
        $os_info="$1";
        my $os_release = (split /\./, $os_info)[0];
        my $os_version = (split /\./, $os_info)[2];
        $os_info = "CentOS".$os_release."_".$os_version;
    } elsif ( $os_type =~ "Kylin" ) {
        ($tmp_value, $err_info) = $ssh->capture2({ timeout => 30 }, "cat /etc/os-release | grep 'VERSION_ID' 2>&1 ");
        $ssh->error and return "fail: remote command get os information on Kylin or NeoKylin [$host_ip] failed.";
        chomp($tmp_value);
        if ( $os_type =~ "NeoKylin" ) {
            $tmp_value =~ /VERSION_ID=\"V(.*)\"/g;
            $os_info = "NeoKylin_".$1;
        } else {
            $tmp_value =~ /VERSION_ID=\"(.*)\"/g;
            $os_info = "Kylin_".$1;
        }
    } elsif ( $os_type =~ "Loongson" ) {
        ($tmp_value, $err_info) = $ssh->capture2({ timeout => 30 }, "cat /etc/os-release | grep 'VERSION_ID' 2>&1 ");
        $ssh->error and return "fail: remote command get os information on Loongson[$host_ip] failed.";
        chomp($tmp_value);
        $tmp_value =~ /VERSION_ID=(.*)/g;
        $os_info="$1";
        my $os_release = (split /\./, $os_info)[0];
        my $os_version = (split /\./, $os_info)[1];
        $os_info = "Loongson".$os_release."_".$os_version;
    } elsif ( $os_type =~ "openSUSE" ) {
        ($tmp_value, $err_info) = $ssh->capture2({ timeout => 30 }, "cat /etc/os-release | grep 'VERSION_ID' 2>&1 ");
        $ssh->error and return "fail: remote command get os information on openSUSE[$host_ip] failed.";
        chomp($tmp_value);
        $tmp_value =~ /VERSION_ID=\"(.*)\"/g;
        $os_info="$1";
        my $os_release = (split /\./, $os_info)[0];
        my $os_version = (split /\./, $os_info)[1];
        $os_info = "openSUSE".$os_release."_".$os_version;
        # $os_info =~ s/\.//g;
        # my $os_version = $os_info;
        # $os_info = "openSUSE"."_".$os_version;
    } elsif ( $os_type =~ "Red Hat" ) {
        ($tmp_value, $err_info) = $ssh->capture2({ timeout => 30 }, "cat /etc/os-release | grep 'VERSION_ID' 2>&1 ");
        $ssh->error and return "fail: remote command get os information on openSUSE[$host_ip] failed.";
        chomp($tmp_value);
        $tmp_value =~ /VERSION_ID=\"(.*)\"/g;
        $os_info="$1";
        my $os_release = (split /\./, $os_info)[0];
        my $os_version = (split /\./, $os_info)[1];
        $os_info = "RedHat".$os_release."_".$os_version;
    } elsif ( $os_type =~ "Ubuntu" ) {
        $tmp_value = (split / /, $os_type)[1];
        (my $os_release = $tmp_value) =~ s/\./_/g;
        $os_info = "Ubuntu".$os_release;
    } elsif ( $os_type =~ "uos" ) {
        ($tmp_value, $err_info) = $ssh->capture2({ timeout => 30 }, "cat /etc/os-release | grep 'VERSION_ID' 2>&1 ");
        $ssh->error and return "fail: remote command get os information on UOS[$host_ip] failed.";
        chomp($tmp_value);
        $tmp_value =~ /VERSION_ID=\"(.*)\"/g;
        my $os_release="$1";
        $os_release =~ s/\s//g;
        $os_info = "UOS".$os_release;
    } elsif ( $os_type =~ "UnionTech" ) {
        ($tmp_value, $err_info) = $ssh->capture2({ timeout => 30 }, "cat /etc/os-release | grep 'VERSION_ID' 2>&1 ");
        $ssh->error and return "fail: remote command get os information on UOS[$host_ip] failed.";
        chomp($tmp_value);
        $tmp_value =~ /VERSION_ID=\"(.*)\"/g;
        my $os_release="$1";
        $os_release =~ s/\s//g;
        $os_info = "UOS".$os_release;
    } else {
        return "fail: os type on host[$host_ip] can't deal with right now.";
    }
    print "OS type on host[$host_ip] is:$os_type, OS version is: [$os_info]\n";
    unless ( defined $os_info ) {
        # body...
        return "fail: os type on host[$host_ip] can't deal with right now.";
    }

    ($tmp_value, $err_info) = $ssh->capture2({ timeout => 30 }, "lscpu | grep Architecture 2>&1 ");
    $ssh->error and return "fail: remote command get CPU  Architecture failed.";
    chomp($tmp_value);
    $tmp_value =~ s/\s//g;
    my $cpu_architecture = (split /:/, $tmp_value)[1];
    if ( $cpu_architecture ne "x86_64" ) {
        (my $kernel_version, $err_info) = $ssh->capture2({ timeout => 30 }, "uname -r | cut -d '-' -f 1 2>&1 ");
        $ssh->error and return "fail: remote command get Linux Kernel Version failed.";
        chomp($kernel_version);
        $os_info = $os_info."_kernel"."$kernel_version"."_"."$cpu_architecture";
        print "whole platform information on host[$host_ip] is: [$os_info]\n";
    }

    return "$os_info";
}



# this function used to get current host OS type and version  ***
# input: null
# return value: these return value should be same with function get_host_os_info
#         ...
#
sub get_current_host_os_info {
    my $tmp_value = undef;
    my $os_info = undef;
    my $os_release = undef;
    my $os_version = undef;

    my $os_type = `cat /etc/os-release | grep 'PRETTY_NAME' 2>&1 `;
    chomp($os_type);
    if ( $os_type =~ "CentOS") {
        $tmp_value = `cat /etc/centos-release 2>&1 `;
        chomp($tmp_value);
        $tmp_value =~ /((\d+.)+\d+)/g;
        $os_info="$1";
        $os_release = (split /\./, $os_info)[0];
        $os_version = (split /\./, $os_info)[2];
        $os_info = "CentOS".$os_release."_".$os_version;
    } elsif ( $os_type =~ "Kylin" ) {
        $tmp_value = `cat /etc/os-release | grep 'VERSION_ID' 2>&1 `;
        chomp($tmp_value);
        if ( $os_type =~ "NeoKylin" ) {
            $tmp_value =~ /VERSION_ID=\"V(.*)\"/g;
            $os_info = "NeoKylin_".$1;
        } else {
            $tmp_value =~ /VERSION_ID=\"(.*)\"/g;
            $os_info = "Kylin_".$1;
        }
    } elsif ( $os_type =~ "Loongson" ) {
        $tmp_value = `cat /etc/os-release | grep 'VERSION_ID' 2>&1 `;
        chomp($tmp_value);
        $tmp_value =~ /VERSION_ID=(.*)/g;
        $os_info="$1";
        $os_release = (split /\./, $os_info)[0];
        $os_version = (split /\./, $os_info)[1];
        $os_info = "Loongson".$os_release."_".$os_version;
    } elsif ( $os_type =~ "NeoKylin" ) {
        $tmp_value = `cat /etc/os-release | grep 'VERSION_ID' 2>&1 `;
        chomp($tmp_value);
        $tmp_value =~ /VERSION_ID=\"V(.*)\"/g;
        $os_info = "NeoKylin_".$1;
    } elsif ( $os_type =~ "openSUSE" ) {
        $tmp_value = `cat /etc/os-release | grep 'VERSION_ID' 2>&1 `;
        chomp($tmp_value);
        $tmp_value =~ /VERSION_ID=\"(.*)\"/g;
        $os_info="$1";
        $os_release = (split /\./, $os_info)[0];
        $os_version = (split /\./, $os_info)[1];
        $os_info = "openSUSE".$os_release."_".$os_version;
    } elsif ( $os_type =~ "Red Hat" ) {
        $tmp_value = `cat /etc/os-release | grep 'VERSION_ID' 2>&1 `;
        chomp($tmp_value);
        $tmp_value =~ /VERSION_ID=\"(.*)\"/g;
        $os_info="$1";
        $os_release = (split /\./, $os_info)[0];
        $os_version = (split /\./, $os_info)[1];
        $os_info = "RedHat".$os_release."_".$os_version;
    } elsif ( $os_type =~ "Ubuntu" ) {
        $tmp_value = (split / /, $os_type)[1];
        (my $os_release = $tmp_value) =~ s/\./_/g;
        $os_info = "Ubuntu".$os_release;
    } elsif ( $os_type =~ "uos" ) {
        $tmp_value = `cat /etc/os-release | grep 'VERSION_ID' 2>&1 `;
        chomp($tmp_value);
        $tmp_value =~ /VERSION_ID=\"(.*)\"/g;
        $os_release="$1";
        $os_info = "UOS".$os_release;
    } else {
        return "fail: os type on current host can't deal with right now.";
    }
    print "OS type on current host is:$os_type, version is: [$os_info]\n";
    unless ( defined $os_info ) {
        # body...
        return "fail: os type on current host can't deal with right now.";
    }

    $tmp_value = `lscpu | grep Architecture 2>&1 `;
    chomp($tmp_value);
    $tmp_value =~ s/\s//g;
    my $cpu_architecture = (split /:/, $tmp_value)[1];
    if ( $cpu_architecture ne "x86_64" ) {
        my $kernel_version = `uname -r | cut -d '-' -f 1 2>&1 `;
        chomp($kernel_version);
        $os_info = $os_info."_kernel"."$kernel_version"."_"."$cpu_architecture";
        print "whole platform information on current host is: [$os_info]\n";
    }

    return "$os_info";
}



# this function used to get OS software management way dpkg or rpm  ***
# input: operating system information
# return value: these return value should be same with function get_host_os_info
#         dpkg - Debian/Ubuntu distribution used this way(dpkg , apt-get)
#         rpm - Red Hat/Fedora/CentOS distribution used this way(rpm , yum)
#         unknown - can't reconginze from input information

sub get_os_software_management_way {
    (my $os_info) = @_;
    $os_info = lc $os_info;
    if (($os_info =~ "centos") || ($os_info =~ "red hat") || ($os_info =~ "redhat") ) {
        return "rpm";
    } elsif ( $os_info =~ "loongson" ) {
        return "rpm";
    } elsif ( $os_info =~ "kylin" ) {
        if ( ($os_info eq "kylin_v10_kernel4.19.90_aarch64" ) || ( $os_info eq "neokylin_7.0_kernel4.14.0_aarch64") ) {
            return "rpm";
        } else {
            return "dpkg";
        }
    } elsif (($os_info =~ "ubuntu") || ($os_info =~ "uos") ) {
        return "dpkg";
    }

    return "unknown";
}

# this function used to get OS sync timestamp way :
# local_chrony - need to configure chrony among cluster
# Inernet_chrony - sync time by chrony for Inernet
# default_ntpdate - ntpdate way.
# configured_mode - deceide by config file.
sub get_os_sync_timestamp_way {
    (my $os_info) = @_;
    if ( $os_info eq "CentOS7_1611") {
        return "default_ntpdate";
    } elsif ( $os_info eq "CentOS8_1905" ) {
        return "local_chrony";
    } elsif ( $os_info eq "Kylin_V10_kernel4.19.90_aarch64" ) {
        return "chrony"
    } elsif ( $os_info eq "UOS20_kernel4.19.0_mips64" ) {
        return "Inernet_chrony"
    }
    return "configured_mode";
}



# this function used to remove space and last character in one string
# this is almost used for directory or file path.
# expected "/home/test" instead of "/home/test/" and "/home/test   "
# input: string
# return value: string
sub remove_last_particuar_character {
    my @array_character = qw(/ ;);
    (my $original_string) = @_;
    $original_string =~ s/\s+//g;
    my $last_char = substr($original_string,-1,1);
    unless ( grep {$_ eq $last_char}  @array_character) {
        # body...
        return $original_string;
    }
    return substr($original_string, 0, length($original_string)-1);
}


# this function used to get chrony server list from cluster host /etc/chrony.conf settings
# this function only used in chrony way to sync time
# input: login information and cluster ip information
# return value: chrony server array
sub get_chronyserver_list_from_cluster {
    (my $login_user, my $login_passwd, my $nodes_ip_all) = @_;

    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};
    my @array_host_all = &get_ip_array_from_string($nodes_ip_all);
    if ( "$array_host_all[0]" eq "0x0006" or "$array_host_all[0]" eq "0x0007") {
        print "ip format is not right to get all hosts ip address";
        return qw();
    }

    my %chronyserver_ip_to_times = ();
    foreach my $host_ip(@array_host_all) {
        my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);
        $ssh->error and  print "Couldn't establish SSH connection to $host_ip\n";
        if ($ssh->error) {
            say LOG_FILE "can't get chrony setting from [$host_ip] as it can't be accessed";
            next;
        }
        (my $tmp_value, my $err_info) = $ssh->capture2({ timeout => 30 }, "grep 'server ' /etc/chrony.conf");
        my @tmp_array = split /\n/, $tmp_value;
        foreach my $tmp_line(@tmp_array) {
            my $server_ip = (split /\s+/, $tmp_line)[1];
            print "--debug: get server ip $server_ip from host[$host_ip]\n";
            if (exists $chronyserver_ip_to_times{$server_ip}) {
                $chronyserver_ip_to_times{$server_ip}++;
            } else {
                $chronyserver_ip_to_times{$server_ip} = 1;
            }
            print "chrony server ip[$server_ip], count[$chronyserver_ip_to_times{$server_ip}]\n";
        }
    }


    my @chronyserver_list = ();
    my $max_count = (reverse sort values %chronyserver_ip_to_times)[0];
    # print "---debug: max count is [$max_count]\n";
    while ( (my $key, my $value) = each %chronyserver_ip_to_times ) {
        if ($value == $max_count) {
            push @chronyserver_list, $key;
        }
    }
    if ( scalar(@chronyserver_list) == 0 ) {
        print "Can't find any chrony server in cluster [$nodes_ip_all] !! \n";
        return @chronyserver_list;
    }

    my @chronyserver_ok_list = ();
    foreach my $host_ip(@chronyserver_list) {
        my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);
        $ssh->error and  print "Couldn't establish SSH connection to $host_ip to check chrony server status\n";
        if ($ssh->error) {
            print "can't get chrony server setting from [$host_ip] as it can't be accessed\n";
            next;
        }
        # there is no effective way to check whether chrony server works well 2020-02-26
        push @chronyserver_ok_list, $host_ip;
    }

    if ( scalar(@chronyserver_ok_list) == 0 ) {
        print "Can't find available ntp server in cluster [@chronyserver_ok_list] !! ";
    }

    return @chronyserver_ok_list;
}


# this function used to get ntp server list from cluster host /etc/crontab settings
# this function only used in ntpdate way to sync time
# input: login information and cluster ip information
# return value: ntp server array
sub get_ntpserver_list_from_cluster {
    (my $login_user, my $login_passwd, my $nodes_ip_all) = @_;

    my $ssh_ops = {user => $login_user, password => $login_passwd, master_opts => [-o => "UserKnownHostsFile=/dev/null", -o => "StrictHostKeyChecking=no"]};

    my @array_host_all = &get_ip_array_from_string($nodes_ip_all);
    if ( "$array_host_all[0]" eq "0x0006" or "$array_host_all[0]" eq "0x0007") {
        print "ip format is not right to get all hosts ip address";
        return qw();
    }

    my %ntpserver_ip_to_times = ();
    foreach my $host_ip(@array_host_all) {
        my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);
        $ssh->error and  print "Couldn't establish SSH connection to $host_ip\n";
        if ($ssh->error) {
            say LOG_FILE "can't get ntpdate setting from [$host_ip] as it can't be accessed";
            next;
        }
        (my $tmp_value, my $err_info) = $ssh->capture2({ timeout => 30 }, "grep 'ntpdate' /etc/crontab");
        my @tmp_array = split /\n/, $tmp_value;
        foreach my $tmp_line(@tmp_array) {
            $tmp_line =~ s/\s+//g;
            $tmp_line =~ /ntpdate(.+)/;
            my $server_ip = $1;
            # print "--debug: get server ip $server_ip from host[$host_ip]\n";
            if (exists $ntpserver_ip_to_times{$server_ip}) {
                $ntpserver_ip_to_times{$server_ip}++;
            } else {
                $ntpserver_ip_to_times{$server_ip} = 1;
            }
            # print "ntp server ip[$server_ip], count[$ntpserver_ip_to_times{$server_ip}]\n";
        }
    }


    my @ntpserver_list = ();
    my $max_count = (reverse sort values %ntpserver_ip_to_times)[0];
    # print "---debug: max count is [$max_count]\n";
    while ( (my $key, my $value) = each %ntpserver_ip_to_times ) {
        if ($value == $max_count) {
            push @ntpserver_list, $key;
        }
    }
    if ( scalar(@ntpserver_list) == 0 ) {
        print "Can't find any ntp server in cluster [$nodes_ip_all] !! \n";
        return @ntpserver_list;
    }

    my @ntpserver_ok_list = ();
    foreach my $host_ip(@ntpserver_list) {
        my $ssh = Net::OpenSSH->new($host_ip, %$ssh_ops);
        $ssh->error and  print "Couldn't establish SSH connection to $host_ip to check ntp server status\n";
        if ($ssh->error) {
            print "can't get ntp server setting from [$host_ip] as it can't be accessed\n";
            next;
        }
        (my $tmp_value, my $err_info) = $ssh->capture2({ timeout => 30 }, "ntpq -p");
        if($tmp_value =~ "LOCAL") {
            print "host [$host_ip] run as ntp server are running well\n";
            push @ntpserver_ok_list, $host_ip;
        }
    }

    if ( scalar(@ntpserver_ok_list) == 0 ) {
        print "Can't find available ntp server in cluster [@ntpserver_ok_list] !! ";
    }

    return @ntpserver_ok_list;
}



# this function used to set local repository on openSUSE host
# input: directory path, repository name
sub set_local_repository_on_openSUSE {
    (my $directory_path, my $repository_name) = @_;
    system("zypper rr $repository_name");
    system("zypper clean");
    system("zypper modifyrepo -d -a");
    system("zypper ar file://$directory_path $repository_name");
    system("zypper modifyrepo -e  file://$directory_path");
}



1;

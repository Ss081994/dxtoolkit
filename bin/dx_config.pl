#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright (c) 2015,2020 by Delphix. All rights reserved.
#
# Program Name : dx_config.pl
# Description  : Convert dxtools.conf file from and to csv
# Author       : Marcin Przepiorowski
# Created      : 22 Apr 2015 (v2.0.0)
#


use strict;
use warnings;
use JSON;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev); #avoids conflicts with ex host and help
use File::Basename;
use Pod::Usage;
use FindBin;
use Data::Dumper;
use POSIX qw/strftime/;
use File::Copy;

my $abspath = $FindBin::Bin;

use lib '../lib';
use Engine;

my $version = $Toolkit_helpers::version;
my $host_exists;


GetOptions(
'help|?' => \( my$help),
'debug' => \(my $debug),
'convert=s' => \(my $convert),
'csvfile|f=s' => \(my $csvfile),
'append' => \(my $append),
'text|c=s' => \(my $conf_param_file),
'configfile|c=s' => \(my $configfile),
'version|v' => \(my $print_version)
) or pod2usage(-verbose => 1, -output=>\*STDERR);

pod2usage(-verbose => 2, -output=>\*STDERR) && exit if $help;
die  "$version\n" if $print_version;

if (! ( defined ($convert) && (defined($csvfile) || defined($conf_param_file)) && defined($configfile) ) ) {
	print "Parameter convert is required.\n";
	pod2usage(-verbose => 1, -output=>\*STDERR);
	exit;
}

if (! (( $convert eq 'tocsv') || ($convert eq 'todxconf')) ) {
	print "Parameter convert has to possible value tocsv and todxconf\n";
	pod2usage(-verbose => 1, -output=>\*STDERR);
}

if ( $convert eq 'tocsv' ) {
	convert_tocsv($csvfile, $configfile);
}

if ( ($convert eq 'todxconf' ) &&  (defined(($csvfile)) ) ) {
	convert_todxconf($csvfile, $configfile);
}

if ( ($convert eq 'todxconf')  &&  (defined($conf_param_file)))  {
	convert_text_todxconf($conf_param_file, $configfile, $append);
}



############################################################################

sub convert_todxconf {
	my $csvfile = shift;
	my $configfile = shift;

  open(my $FD,$csvfile) || die "Can't open file: $csvfile \n";

  my @engine_list;

  while (my $line = <$FD>) {

    chomp $line;

		if  ( ! ($line =~ m/^\#/g ) ) {

			my ( $hostname, $ip_address, $port, $username, $password, $default, $protocol, $clientid, $clientsecret ) = split(',',$line);

			if ( ! ( defined($hostname) && defined($ip_address) && defined($port) && defined($username) && defined($password) && ((defined($username) && defined($password)) || (defined($clientid) && defined($clientsecret)) )
        && defined($default) )) {
				print "There is a problem with line $line \n";
				print "Not all fields defined. Exiting\n";
				exit 1;
			}

      if (($username ne '') && (defined($clientid)) && ($clientid ne '')) {
        print "There is a problem with line $line \n";
        print "username and clientid are mutually exclusive\n";
        exit 1;
      }

      my %engine;

      if ($username ne '') {
        %engine = (
    		    hostname => $hostname,
    		    username => $username,
    		    ip_address => $ip_address,
    		    password => $password,
    		    port => $port,
    		    default => $default,
            protocol => $protocol
    		);
    } else {
        %engine = (
    		    hostname => $hostname,
    		    clientid => $clientid,
    		    ip_address => $ip_address,
    		    clientsecret => $clientsecret,
    		    port => $port,
    		    default => $default,
            protocol => $protocol
    		);
      }


			push (@engine_list, \%engine);
    }
  }


	my $time = strftime('%Y-%m-%d-%H-%M-%S',localtime);

	if ( -e $configfile ) {
		my $backupfile = $configfile . "." . $time;
		copy ( $configfile, $backupfile ) or die ("Can't generate backup file $backupfile");
		print "Old config file backup file name is $backupfile \n";
	}

	my %engine_json = (
       data => \@engine_list
	);

	open (my $fh, ">", $configfile) or die ("Can't open new config file $configfile for write");
	print $fh to_json(\%engine_json, {pretty=>1});
	close $fh;
  print "New config file $configfile created.\n";
}

sub convert_text_todxconf {
	my $conf_param_file = shift;
	my $configfile = shift;
    my $append = shift;
	my @engine_list;
	chomp $conf_param_file;


	if  ( ! ($conf_param_file =~ m/^\#/g ) ) {
		my ( $hostname, $ip_address, $port, $username, $password, $default, $protocol, $clientid, $clientsecret ) = split(',',$conf_param_file);
		if ( ! ( defined($hostname) && defined($ip_address) && defined($port) && ((defined($username) && defined($password)) || (defined($clientid) && defined($clientsecret)) )
             && defined($default) )) {
			print "There is a problem with line $conf_param_file \n";
			print "Not all fields defined. Exiting\n";
			exit 1;
		}

    if (($username ne '') && (defined($clientid)) && ($clientid ne '')) {
      print "There is a problem with line $conf_param_file \n";
      print "username and clientid are mutually exclusive\n";
      exit 1;
    }

	if (defined($append)) {
		if (! -e $configfile ) {
			print("Config file must exist for append option\n");
			exit 1;
		}
		my $engine_obj = new Engine ('1.4');
		$engine_obj->load_config($configfile);
		for my $en ($engine_obj->getAllEngines()) {
			my $eng = $engine_obj->getEngine($en);
			foreach (keys %{$eng}) {
 			   delete $eng->{$_} unless defined $eng->{$_};
			}
			push(@engine_list, $eng);
		}
	}


	my %engine;

    if ($username ne '') {
      %engine = (
  		    hostname => $hostname,
  		    username => $username,
  		    ip_address => $ip_address,
  		    password => $password,
  		    port => $port,
  		    default => $default,
          protocol => $protocol
  		);
    } else {
      %engine = (
  		    hostname => $hostname,
  		    clientid => $clientid,
  		    ip_address => $ip_address,
  		    clientsecret => $clientsecret,
  		    port => $port,
  		    default => $default,
          protocol => $protocol
  		);
    }

		push (@engine_list, \%engine);
	}



	my $time = strftime('%Y-%m-%d-%H-%M-%S',localtime);

	if ( -e $configfile ) {
		my $backupfile = $configfile . "." . $time;
		copy ( $configfile, $backupfile ) or die ("Can't generate backup file $backupfile");
		print "Old config file backup file name is $backupfile \n";
	}

	my %engine_json = (
       data => \@engine_list
	);

	open (my $fh, ">", $configfile) or die ("Can't open new config file $configfile for write");
	print $fh to_json(\%engine_json, {pretty=>1});
	close $fh;
    print "New config file $configfile created.\n";
}


sub convert_tocsv {
	my $csvfile = shift;
	my $configfile = shift;


	my $engine_obj = new Engine ('1.4');
	$engine_obj->load_config($configfile);

    open(my $FD, ">", $csvfile) || die "Can't open file: $csvfile for write \n";

    print $FD "# engine nick name, engine ip/hostname, port, username, password, default, protocol, clientid, clientsecret \n";


    for my $engine_name ( $engine_obj->getAllEngines() ) {
    	my $engine = $engine_obj->getEngine($engine_name);

      my $line;
      if (defined($engine->{clientid})) {
        $line = $engine_name . "," . $engine->{ip_address} . "," . $engine->{port} . ",,," . $engine->{default} . "," . $engine->{protocol} . "," . $engine->{clientid} . "," . $engine->{clientsecret} ."\n";
      } else {
        $line = $engine_name . "," . $engine->{ip_address} . "," . $engine->{port} . "," . $engine->{username} . "," . $engine->{password} . "," . $engine->{default} . "," . $engine->{protocol} . ",," . "\n";
      }

    	print $FD $line;

    }

    close $FD;

    print "New csv file $csvfile created.\n";
}


__END__


=head1 SYNOPSIS

 dx_config -convert todxconf|tocsv -csvfile file.csv|-text params_list -configfile dxtools.conf [-help] [-version]


=head1 DESCRIPTION

Convert a csv file or list of parameters into DXTOOLKIT configuration file (dxtools.conf) or convert configuration file into csv file.
Existing configuration file will be copy into backup file.

ex.

 dx_config -convert todxconf -csvfile dxtools.csv -configfile dxtools.conf

=head1 ARGUMENTS

=over 3

=item B<-convert todxconf|tocsv>
Specify a conversion direction

=item B<-csvfile file.csv>
CSV file name

=item B<-text parameter_list>
Create a new config file from input. Parameter list is comma separated list of values in the following order:


hostname, ip_address, port, username, password, default, protocol, clientid, clientsecret

Only one pair is required: username and password or clientid and clientsecret

=item B<-configfile dxtools.conf>
config file name

=back


=head1 OPTIONS

=over 2

=item B<-help>
Print this screen

=item B<-debug>
Turn on debugging

=back

=head1 EXAMPLES

Create CSV from dxtools.conf

 dx_config -convert tocsv -csvfile new.csv -configfile dxtools.conf
 New csv file new.csv created.

Create dxtools.conf from CSV file

 dx_config -convert todxconf -csvfile new.csv -configfile dxtools.conf
 New config file dxtools.conf created.

Create dxtools.conf from command line

 dx_config -convert todxconf -text hostname,192.168.1.100,443,username,password,N,https -configfile new.conf
 Old config file backup file name is new.conf.2020-05-01-10-28-07
 New config file new.conf created.

=cut

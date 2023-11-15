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
# Copyright (c) 2014,2016 by Delphix. All rights reserved.
#
# Program Name : dx_get_audit.pl
# Description  : Get Delphix Engine audit
# Author       : Edward de los Santos
# Created      : 30 Jan 2014 (v1.0.0)
#
# Modified     : 20 Jul 2015 (v2.0.0) Marcin Przepiorowski
# 

use strict;
use warnings;
use JSON;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev); #avoids conflicts with ex host and help
use File::Basename;
use Pod::Usage;
use FindBin;
use Data::Dumper;

my $abspath = $FindBin::Bin;

use lib '../lib';
use Engine;
use Formater;
use Toolkit_helpers;
use Action_obj;

my $version = $Toolkit_helpers::version;


GetOptions(
  'help|?' => \(my $help), 
  'd|engine=s' => \(my $dx_host), 
  'st=s' => \(my $st), 
  'et=s' => \(my $et), 
  'state=s' => \(my $state),
  'type=s' => \(my $type),
  'username=s' => \(my $username),
  'outdir=s' => \(my $outdir),
  'format=s' => \(my $format), 
  'all' => (\my $all),
  'dever=s' => \(my $dever),
  'version' => \(my $print_version),
  'nohead' => \(my $nohead),
  'debug:i' => \(my $debug),
  'configfile|c=s' => \(my $config_file)
) or pod2usage(-verbose => 1,  -input=>\*DATA);

pod2usage(-verbose => 2,  -input=>\*DATA) && exit if $help;
die  "$version\n" if $print_version;   

my $engine_obj = new Engine ($dever, $debug);
$engine_obj->load_config($config_file);


if (defined($all) && defined($dx_host)) {
  print "Option all (-all) and engine (-d|engine) are mutually exclusive \n";
  pod2usage(-verbose => 1,  -input=>\*DATA);
  exit (1);
}


if (defined($state) && ( ! ( (uc $state eq 'COMPLETED') || (uc $state eq 'FAILED') || (uc $state eq 'WAITING') ) ) ) {
  print "Option state can have only COMPLETED, WAITING and FAILED value\n";
  pod2usage(-verbose => 1,  -input=>\*DATA);
  exit (1);
}


# this array will have all engines to go through (if -d is specified it will be only one engine)
my $engine_list = Toolkit_helpers::get_engine_list($all, $dx_host, $engine_obj); 

my $output = new Formater();


$output->addHeader(
    {'Appliance',   20},
    {'StartTime',   30},
    {'State',       12},
    {'User or Policy',20},
    {'Type',        20},
    {'Details',     80}
);

my $ret = 0;

for my $engine ( sort (@{$engine_list}) ) {
  # main loop for all work
  if ($engine_obj->dlpx_connect($engine)) {
    print "Can't connect to Dephix Engine $dx_host\n\n";
    $ret = $ret + 1;
    next;
  };


  my $st_timestamp;

  if (! defined($st_timestamp = Toolkit_helpers::timestamp($st, $engine_obj))) {
    print "Wrong start time (st) format \n";
    pod2usage(-verbose => 1,  -input=>\*DATA);
    exit (1);  
  }

  my $et_timestamp;

  if (defined($et)) {
    if (! defined($et_timestamp = Toolkit_helpers::timestamp($et, $engine_obj))) {
      print "Wrong end time (et) format \n";
      pod2usage(-verbose => 1,  -input=>\*DATA);
      exit (1);  
    } 
  }
  
  if (defined($state)) {
    $state = uc $state;
  }

  my $actions = new Action_obj($engine_obj, $st_timestamp, $et_timestamp, $state, undef, $debug);
  $actions->loadActionList();

  for my $actionitem ( @{$actions->getActionList('asc', $type, $username)} ) {

    $output->addLine(
      $engine,
      $actions->getStartTimeWithTZ($actionitem),
      $actions->getState($actionitem),
      $actions->getUserName($actionitem),
      $actions->getActionType($actionitem),
      $actions->getDetails($actionitem)
    )

  }
}

if (defined($outdir)) {
  Toolkit_helpers::write_to_dir($output, $format, $nohead,'audit',$outdir,1);
} else {
  Toolkit_helpers::print_output($output, $format, $nohead);
}

exit $ret;

__DATA__

=head1 SYNOPSIS

 dx_get_audit    [ -engine|d <delphix identifier> | -all ] [ -configfile file ] 
                 [-st timestamp] 
                 [-et timestamp] 
                 [-state state] 
                 [-type type] 
                 [-username username]
                 [-format csv|json ]  
                 [-outdir path]
                 [ --help|? ] [ -debug ]

=head1 DESCRIPTION

Get the list of actions from Delphix Engine.

=head1 ARGUMENTS

Delphix Engine selection - if not specified a default host(s) from dxtools.conf will be used.

=over 10

=item B<-engine|d>
Specify Delphix Engine name from dxtools.conf file

=item B<-all>
Run script for all Delphix Engines from config file

=item B<-configfile file>
Location of the configuration file.
A config file search order is as follow:
- configfile parameter
- DXTOOLKIT_CONF variable
- dxtools.conf from dxtoolkit location

=back

=head2 Filters

Filter faults using one of the following filters

=over 4

=item B<-state>
Action state - COMPLETED / WAITING / FAILED

=item B<-type>
Action type ex. HOST_UPDATE, SOURCES_DISABLE, etc,

=item B<-username>
Display only action performed by user

=back

=head1 OPTIONS

=over 3


=item B<-st timestamp>
Start time for faults list - default value is 7 days

=item B<-et timestamp>
End time for faults list 

=item B<-format>                                                                                                                                            
Display output in csv or json format
If not specified pretty formatting is used.

=item B<-outdir path>                                                                                                                                            
Write output into a directory specified by path.
Files names will include a timestamp and type name

=item B<-help>          
Print this screen

=item B<-debug>
Turn on debugging

=item B<-nohead>
Turn off header output

=back

=head1 EXAMPLES

Display audit logs

 dx_get_audit -d Landshark5

 Appliance            StartTime                      State        User                 Type                 Details
 -------------------- ------------------------------ ------------ -------------------- -------------------- --------------------------------------------------------------------------------
 Landshark5           2016-11-08 12:27:35 GMT        COMPLETED    delphix_admin        USER_LOGIN           Log in as user "delphix_admin" from IP "172.16.180.1".
 Landshark5           2016-11-08 12:27:42 GMT        COMPLETED    delphix_admin        MASKINGJOB_FETCH     Fetching all Masking Jobs from the local Delphix Masking Engine instance.
 Landshark5           2016-11-08 12:28:49 GMT        CANCELED     delphix_admin        DB_PROVISION         Provision virtual database "VOra_744".
 Landshark5           2016-11-08 12:28:53 GMT        COMPLETED    delphix_admin        POLICY_APPLY         Apply policy "sss/log" on target "VOra_744".
 Landshark5           2016-11-08 12:29:03 GMT        COMPLETED    delphix_admin        JOB_CANCEL           Cancel job "Provision virtual database "VOra_744".".
 Landshark5           2016-11-08 12:29:03 GMT        COMPLETED    delphix_admin        SOURCE_DISABLE       Disable dataset "VOra_744".
 Landshark5           2016-11-08 12:29:07 GMT        COMPLETED    delphix_admin        SOURCE_STOP          Stop dataset "VOra_744".
 Landshark5           2016-11-08 12:32:21 GMT        COMPLETED    delphix_admin        DB_DELETE            Delete dataset "VOra_744".
 Landshark5           2016-11-08 12:32:22 GMT        COMPLETED    delphix_admin        CAPACITY_RECLAMATION Space is being reclaimed.
 Landshark5           2016-11-08 12:39:17 GMT        COMPLETED    delphix_admin        USER_LOGIN           Log in as user "delphix_admin" from IP "172.16.180.1".

Extract audit to file 

 dx_get_audit -d Landshark5 -outdir /tmp
 Data exported into /tmp/audit-20161108-15-00-28.txt

=cut




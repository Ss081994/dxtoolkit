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
# Copyright (c) 2022 by Delphix. All rights reserved.
#
# Program Name : dx_get_vdbsize.pl
# Description  : Get combined VDB size
# Author       : Marcin Przepiorowski
# Created      : 06 Apr 2022 (v2.4)
#

use strict;
use warnings;
use JSON;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev); #avoids conflicts with ex host and help
use File::Basename;
use Pod::Usage;
use FindBin;
use Data::Dumper;
use warnings;
use strict;
use version;
use List::MoreUtils qw(uniq);

my $abspath = $FindBin::Bin;

use lib '../lib';
use Engine;
use Formater;
use Toolkit_helpers;
use Databases;
use Timeflow_obj;
use Toolkit_helpers qw (logger);
use Capacity_obj;


my $version = $Toolkit_helpers::version;


GetOptions(
  'help|?' => \(my $help),
  'd|engine=s' => \(my $dx_host),
  'name=s' => \(my $dbname),
  'group=s' => \(my $group),
  'host=s' => \(my $host),
  'dsource=s' => \(my $dsource),
  'envname=s' => \(my $envname),
  'instance=n' => \(my $instance),
  'instancename=s' => \(my $instancename),
  'reponame=s' => \(my $repositoryname),
  'primary' => \(my $primary),
  'snapname' => \(my $snapname),
  'parent' => \(my $parent),
  'forcerefresh' => \(my $forcerefresh),
  'all' => (\my $all),
  'format=s' => \(my $format),
  'version' => \(my $print_version),
  'dever=s' => \(my $dever),
  'nohead' => \(my $nohead),
  'debug:i' => \(my $debug),
  'configfile|c=s' => \(my $config_file)
) or pod2usage(-verbose => 1,  -input=>\*DATA);

pod2usage(-verbose => 2,  -input=>\*DATA) && exit if $help;
die  "$version\n" if $print_version;

my $engine_obj = new Engine ($dever, $debug);
$engine_obj->load_config($config_file);


if (defined($all) && defined($dx_host)) {
  print "Options all (-all) and engine (-d|engine) are mutually exclusive \n";
  pod2usage(-verbose => 1,  -input=>\*DATA);
  exit (1);
}



# this array will have all engines to go through (if -d is specified it will be only one engine)
my $engine_list = Toolkit_helpers::get_engine_list($all, $dx_host, $engine_obj);
my $output = new Formater();

if (defined($parent)) {

  $output->addHeader(
      {'Appliance',             10},
      {'Group',                 15},
      {'Database',              30},
      {'Timeflow name',         30},
      {'VDB size',              15},
      {'Parent DB',             30},
      {'Parent Timeflow',       30},
      {'Parent snapshot',       30},
      {'Parent snap size',      20},
      {'Total dSource size',    20},
      {'Locked snapshots size', 20},
      {'Total size',            20},
  );

} else {

  $output->addHeader(
      {'Appliance',             10},
      {'Group',                 15},
      {'Database',              30},
      {'Timeflow name',         30},
      {'VDB size',              15},
      {'dSource name',          30},
      {'dSource snapshot',      30},
      {'dSource snap size',     20},
      {'Total dSource size',    20},
      {'Locked snapshots size', 20},
      {'Total size',            20},
  );


}

my $ret = 0;

for my $engine ( sort (@{$engine_list}) ) {
  # main loop for all work
  if ($engine_obj->dlpx_connect($engine)) {
    print "Can't connect to Dephix Engine $dx_host\n\n";
    $ret = $ret + 1;
    next;
  };





  logger($debug, "Checking size for engine $engine", 2);

  my $timezone = $engine_obj->getTimezone();

  # build hierarchy of timeflow for engine
  my $databases = new Databases( $engine_obj, $debug);

  my $groups = new Group_obj($engine_obj, $debug);
  my $timeflows = new Timeflow_obj($engine_obj, undef, $debug);
  my $hier = $timeflows->generateHierarchy(undef, undef, $databases);

  my $hierc = $databases->generateHierarchy(undef, undef);



  my $db_list = Toolkit_helpers::get_dblist_from_filter('VDB', $group, $host, $dbname, $databases, $groups, $envname, $dsource, $primary, $instance, $instancename, undef, $repositoryname, $debug);
  if (! defined($db_list)) {
    print "There is no DB selected to process on $engine . Please check filter definitions. \n";
    $ret = $ret + 1;
    next;
  }

  my %snapshot_sizes;



  for my $dbitem ( @{$db_list} ) {


    my $totalsize = 0;

    my $dbobj = $databases->getDB($dbitem);
    my $groupname = $groups->getName($dbobj->getGroup());

    my $capacity = new Capacity_obj($engine_obj, $debug);

    if (defined($forcerefresh)) {
      if ($capacity->forcerefesh()) {
        print "Problem with forcerefesh. Skipping results for engine $engine\n";
        next;
      }
    }

    $capacity->LoadDatabases();

    my $capacity_hash = $capacity->getDetailedDBUsage($dbitem, undef);
    if ((defined($capacity_hash->{snapshots_shared})) && ($capacity_hash->{snapshots_shared} eq 0) && ($capacity_hash->{snapshots_total} eq 0)) {
      # storage info not found - maybe database is deleted
      # skipping it
      #next;
      print Dumper "No capacity for VDB";
      exit;
    }



    my ($dSourceref, $childc) = $databases->finddSource($dbitem, $hierc, 1);

    # convert to MB for tests
    my $dbsize = $capacity_hash->{totalsize} * 1024;

    $totalsize = $totalsize + $dbsize;



    my $dsourcename;
    my $ds_size;
    my $locked_snaps;

    if ($dSourceref ne 'notlocal') {
      # normal replication
      $dsourcename = ($databases->getDB($dSourceref))->getName();
      logger($debug, "normal replication for $dsourcename",2);
      my $capacity_hash = $capacity->getDetailedDBUsage($dSourceref, undef);
      $ds_size = $capacity_hash->{totalsize} * 1024;
      $totalsize = $totalsize + $ds_size;
      $locked_snaps = sprintf("%12.2f", $capacity_hash->{descendantSpace} * 1024);

    } else {
      logger($debug, "SDD replica",2);
      $dsourcename = 'notlocal';
      my $held_array = $capacity->getStorageContainers();
      my $held_hash;
      my $held_size = 0;
      my $held_snapshot = 0;
      if (scalar(@{$held_array}) > 0) {
        # as don't know which held space belongs to what ( lack of storage container translation )
        # we need to sum all
        for my $hs (@{$held_array}) {

          $held_hash = $capacity->getDetailedDBUsage($hs, undef);
          $held_snapshot = $held_snapshot + $held_hash->{snapshots_total};
          $held_size = $held_size + $held_hash->{totalsize};
        }
      }

      $ds_size = $held_size*1024;
      $totalsize = $totalsize + $ds_size;
      $locked_snaps = sprintf("%12.2f", $capacity_hash->{descendantSpace} * 1024);
    }

    my $snapshots = new Snapshot_obj( $engine_obj, $dbobj->getParentContainer(), undef, $debug);


    # going into timeflow list


    for my $dbtimeflow ( sort { Toolkit_helpers::sort_by_number($b,$a) } @{$timeflows->getTimeflowsForContainer($dbitem)}) {

      # for each timeflow - find a dSource snapshot
      # to update a global view

      my ($dsourcetf, $topchildtf) = $timeflows->finddSource( $dbtimeflow, $hier, 1);

      my $dsourcesnapshot;
      my $dsourcesnapshot_size;
      my $dsourcesnapshot_name;
      if ($dSourceref ne 'notlocal') {
        logger($debug, "normal replication",2);
        $dsourcesnapshot = $timeflows->getParentSnapshot($topchildtf);
        if ($dsourcesnapshot eq '') {
          logger($debug, "parent snapshot deleted ( possible on replica engine)",2);
          $dsourcesnapshot = 'N/A';
          $dsourcesnapshot_name = 'unowned space';
          $dsourcesnapshot_size = 'N/A';
        } else {
          logger($debug, "load and read snapshot data",2);
          ($dsourcesnapshot_name, $dsourcesnapshot_size) = get_snapshot_data($snapshots, \%snapshot_sizes, $dsourcesnapshot, $snapname);
        }
      } else {
        logger($debug, "SDD replication - there will be parent snapshot - held space",2);
        $dsourcesnapshot = 'N/A';
        $dsourcesnapshot_name = 'N/A';
        $dsourcesnapshot_size = 'heldspace';

      }



      if (defined($parent)) {
        # this should only go with parent flag


          my $timeflow_list = $timeflows->returnParentHier($dbtimeflow, $hier);

          my $parentdbname;
          my $parentsnap_name;
          my $parentsnap_size;
          my $parent_db;
          my $parenttf;
          my $timeflowname;



          # print Dumper "list my timeflows to go through";
          # print Dumper \@{$timeflow_list};

          for my $tf (@{$timeflow_list}) {
            my $currobj = $databases->getDB($timeflows->getContainer($tf->{ref}));

            if ($currobj->getType() eq 'VDB') {
              my $parentsnap = $timeflows->getParentSnapshot($tf->{ref});

              logger($debug, "snap from timeflow " . Dumper $parentsnap , 2);


              if ($parentsnap ne '') {
                ($parentsnap_name, $parentsnap_size, $parent_db, $parenttf) = get_snapshot_data($snapshots, \%snapshot_sizes, $parentsnap, $snapname);

                logger($debug, "parent snapshot exists", 2);

                $totalsize = $totalsize + $parentsnap_size;
                $timeflowname = $timeflows->getName($parenttf);
                $parentdbname = $databases->getDB($parent_db)->getName();

                if ($databases->getDB($parent_db)->getType() eq 'dSource') {
                     #&& ($databases->getDB($parent_db)->isReplica() eq 'YES')) {
                  my $capacity_hash = $capacity->getDetailedDBUsage($parent_db, undef);
                  if ((defined($capacity_hash->{snapshots_shared})) && ($capacity_hash->{snapshots_shared} eq 0) && ($capacity_hash->{snapshots_total} eq 0)) {
                    # storage info not found - maybe database is deleted
                    # skipping it
                    #next;
                    print("Capacity data not found. Try with -forcerefesh option\n");
                    $ret = $ret + 1;
                    next;
                  }

                  $ds_size = $capacity_hash->{totalsize} * 1024;
                  #$locked_snaps = sprintf("%12.2f", $capacity_hash->{descendantSpace} * 1024);
                  #$totalsize = $totalsize + $ds_size;
                }

              } else {
                # fail back to print a parent database from current database not snapshot
                $parent_db = $dbobj->getParentContainer();
                if ($parent_db eq '') {
                  $parentdbname = 'N/A';
                } else {
                  $parentdbname = $databases->getDB($parent_db)->getName();
                }



                $timeflowname = 'N/A';

                logger($debug, "type of timeflow",2);
                logger($debug, $tf->{ref}, 2);
                logger($debug, $timeflows->isReplica($tf->{ref}), 2);
                logger($debug, $timeflows->getName($tf->{ref}), 2);

                if ($timeflows->isReplica($tf->{ref}) eq 'YES') {
                  $parentsnap_size = 'heldspace';
                  $parentsnap_name = 'not local';

                  logger($debug, "GET HELD SPACE SIZE",2);
                  my $held_array = $capacity->getStorageContainers();
                  my $held_hash;
                  my $held_size = 0;
                  if (scalar(@{$held_array}) > 0) {
                    # as don't know which held space belongs to what ( lack of storage container translation )
                    # we need to sum all
                    for my $hs (@{$held_array}) {

                      $held_hash = $capacity->getDetailedDBUsage($hs, undef);
                      #print Dumper $held_hash;

                      $held_size = $held_size + $held_hash->{totalsize};
                    }
                  }
                  #$locked_snaps = sprintf("%12.2f", $capacity_hash->{descendantSpace} * 1024);
                  $ds_size = $held_size*1024;
                  #$totalsize = $totalsize + $ds_size;

                } else {
                  logger($debug, "parent snapshot deleted - find a parent time point", 2);
                  my $parenttime = $timeflows->getParentPointTimestampWithTimezone($tf->{ref}, $dbobj->getTimezone());

                  $parentsnap_name = 'deleted - ' . $parenttime;

                  if ($dSourceref ne 'notlocal') {
                    logger($debug, "normal replication with deleted snapshot", 2);
                    my $capacity_hash = $capacity->getDetailedDBUsage($dSourceref, undef);
                    $ds_size = $capacity_hash->{totalsize} * 1024;
                    $parentsnap_size = $capacity_hash->{unownedSnapshotSpace} * 1024;
                    $locked_snaps = sprintf("%12.2f", $capacity_hash->{descendantSpace} * 1024) ;
                    #$totalsize = $totalsize + $ds_size;
                  } else {

                    logger($debug, "SDD with deleted snapshot", 2);
                    my $held_array = $capacity->getStorageContainers();
                    my $held_hash;
                    my $held_size = 0;
                    my $held_snapshot = 0;
                    if (scalar(@{$held_array}) > 0) {
                      # as don't know which held space belongs to what ( lack of storage container translation )
                      # we need to sum all
                      for my $hs (@{$held_array}) {

                        $held_hash = $capacity->getDetailedDBUsage($hs, undef);
                        #print Dumper $held_hash;
                        $held_snapshot = $held_snapshot + $held_hash->{snapshots_total};
                        $held_size = $held_size + $held_hash->{totalsize};
                      }
                    }

                    $parentsnap_size = sprintf("%12.2f",$held_snapshot * 1024);
                    $locked_snaps = 0;
                    $ds_size = $held_size*1024;
                    #$totalsize = $totalsize + $ds_size;


                  }
                }
              }

              $output->addLineRev(
                  '',
                  '',
                  '',
                  '',
                  '',
                  $parentdbname,
                  $timeflowname,
                  $parentsnap_name,
                  $parentsnap_size,
                  '',
                  '',
                  ''
              )

            }

          }

      }

      if (defined($parent)) {
        $output->addLineRev(
            $engine,
            $groupname,
            $dbobj->getName(),
            $timeflows->getName($dbtimeflow),
            sprintf("%12.2f", $dbsize),
            '',
            '',
            '',
            '',
            sprintf("%12.2f", $ds_size),
            $locked_snaps,
            sprintf("%12.2f", $totalsize)
        )
      } else {
          $output->addLineRev(
              $engine,
              $groupname,
              $dbobj->getName(),
              $timeflows->getName($dbtimeflow),
              sprintf("%12.2f", $dbsize),
              $dsourcename,
              $dsourcesnapshot_name,
              $dsourcesnapshot_size,
              sprintf("%12.2f", $ds_size),
              $locked_snaps,
              sprintf("%12.2f", $totalsize)
            );

        }

        logger($debug, "end of timeflow loop",2);

    }



  }
}


Toolkit_helpers::print_output($output, $format, $nohead);

exit $ret;


sub get_snapshot_data {
  my $snapshots = shift;
  my $snapshot_sizes = shift;
  my $snapref = shift;
  my $snapname = shift;

  my $snapsize;

  my $parentdb;

  my $snapshotname;

  my $parenttf;

  my $parentstart;

  if (!defined($snapshot_sizes->{$snapref})) {
    $snapshots->getSnapshotPerRef($snapref);
    $snapshotname = $snapshots->getSnapshotName($snapref);
    if (!defined($snapshotname)) {
      $snapshotname = "deleted";
      $snapsize = 'N/A';
    } else {
      $parentdb = $snapshots->getSnapshotContainer($snapref);
      $snapsize = $snapshots->getSnapshotSize($snapref);
      $parenttf = $snapshots->getSnapshotTimeflow($snapref);
      $parentstart = $snapshots->getStartPointwithzone($snapref);
      if (defined($snapsize)) {
        $snapsize = sprintf("%12.2f", $snapsize/1024/1024);
      } else {
        $snapsize = 'N/A';
      }
    }
    $snapshot_sizes->{$snapref} = {
      'snapsize'=>$snapsize,
      'snapname'=>$snapshotname,
      'parent'=>$parentdb,
      'parenttf'=>$parenttf,
      'parentstart'=>$parentstart
    }
  } else {
    $snapsize = $snapshot_sizes->{$snapref}->{snapsize};
    $snapshotname = $snapshot_sizes->{$snapref}->{snapname};
    $parentdb = $snapshot_sizes->{$snapref}->{parent};
    $parenttf = $snapshot_sizes->{$snapref}->{parenttf};
    $parentstart = $snapshot_sizes->{$snapref}->{parentstart};
  }

  my $retsnap;

  if (defined($snapname)) {
    $retsnap = $snapshotname;
  } else {
    $retsnap = $parentstart;
  }

  return ($retsnap, $snapsize, $parentdb, $parenttf);

}

__DATA__

=head1 SYNOPSIS

 dx_get_vdbsize   [-engine|d <delphix identifier> | -all ]
                  [-format csv|json ]
                  [-group group_name | -name db_name | -host host_name | -type dsource|vdb | -instancename instname
                   |-reponame repository_name\-primary]
                  [-parent]
                  [-snapname]
                  [-forcerefresh]
                  [-format csv|json ]
                  [-nohead]
                  [-help|? ]
                  [ -debug ]

=head1 DESCRIPTION

Display a list of VDB's with corresponding size of the VDB and parent dSource.
Parameter -parent will add a list of the timeflows and its dependency

=head1 ARGUMENTS

Delphix Engine selection - if not specified a default host(s) from dxtools.conf will be used.

=over 10

=item B<-engine|d>
Specify Delphix Engine name from dxtools.conf file

=item B<-all>
Display databases on all Delphix appliance

=item B<-configfile file>
Location of the configuration file.
A config file search order is as follow:
- configfile parameter
- DXTOOLKIT_CONF variable
- dxtools.conf from dxtoolkit location

=back

=head2 Filters

Filter databases using one of the following filters

=over 4

=item B<-group>
Group Name

=item B<-name>
Database Name

=item B<-host>
Host Name

=item B<-type>
Type (dsource|vdb)

=item B<-envname>
Environment name

=item B<-dsource dsourcename>
Dsource name

=item B<-instancename instname>
Instance name (Oracle)

=item B<-reponame repository_name>
Filter using repository_name ( Oracle Home, MS SQL instance, etc)

=back

=head2 Options

=over 4

=item B<-parent>
Display a list of all timeflows with depended snapshots

=item B<-format>
Display output in csv or json format
If not specified pretty formatting is used.

=item B<-help>
Print this screen

=item B<-debug>
Turn on debugging

=item B<-nohead>
Turn off header output

=back

=head1 COLUMNS

Columns description

=over 1

=item B<Appliance> - Delphix Engine name from dxtools.conf file

=item B<Group> - Group name

=item B<Database> - Database name ( dSource or VDB )

=item B<Timeflow name> - Name of the timeflow generated by Delphix

=item B<VDB size> - Size of the unique blocks used by VDB

=item B<Parent DB> - Name of the parent database

=item B<Parent Timeflow> - Name of the parent timeflow

=item B<Parent snapshot> - Name or time of the parent (locked) snapshot of the timeflow

=item B<Parent snap size> - Size of the parent snapshot ( amount of space to release if snapshot is deleted)

=item B<Total dSource size'> - Total size of the dSource ( current size plus all snapshots )

=item B<Locked snapshots size> - Size of snapshots locked by other objects and not deleted due to dependency

=item B<Total size> - Total storage footprint of the VDB and all parent objects including dSource

=item B<dSource name> - dSource name for a VDB

=item B<dSource snapshot> - dSource snapshot locked by a VDB or chain of VDBs

=item B<dSource snapshot size> - dSource snapshot size locked by a VDB or chain of VDBs


=back

=head1 EXAMPLES


 dx_get_vdbsize -d 613

 Appliance  Group           Database                       Timeflow name                  VDB size        dSource name                   dSource snapshot               dSource snap size    Total dSource size   Locked snapshots siz Total size
 ---------- --------------- ------------------------------ ------------------------------ --------------- ------------------------------ ------------------------------ -------------------- -------------------- -------------------- --------------------
 613        Untitled        oratest                        DB_REFRESH@2022-04-08T14:25:36       129.79    test19                         2022-04-01 11:31:07 IST               12.77              1373.18                12.77              1502.97
 613        Untitled        clonik                         CAPACITY_DELETE_DEPENDENCIES@2       109.42    test19                         2022-04-01 11:31:07 IST               12.77              1373.18                12.77              1482.60
 613        Untitled        TEST2                          DB_REFRESH@2022-03-30T11:13:11         0.71    AdventureWorks2012             2022-03-30 10:30:18 BST                0.14                75.54                 0.14                76.24


 dx_get_vdbsize -d 613 -parent

 Appliance  Group           Database                       Timeflow name                  VDB size        Parent DB                      Parent Timeflow                Parent snapshot                Parent snap size     Total dSource size   Locked snapshots siz Total size
 ---------- --------------- ------------------------------ ------------------------------ --------------- ------------------------------ ------------------------------ ------------------------------ -------------------- -------------------- -------------------- --------------------
 613        Untitled        oratest                        DB_REFRESH@2022-04-08T14:25:36       129.79                                                                                                                           1373.18                12.77              1515.74
                                                                                                          test19                         default                        2022-04-01 11:31:07 IST               12.77
 613        Untitled        clonik                         CAPACITY_DELETE_DEPENDENCIES@2       109.42                                                                                                                           1373.18                12.77              1511.23
                                                                                                          oratest                        DB_REFRESH@2022-04-08T14:25:36 2022-04-08 17:14:05 IST               15.86
                                                                                                          test19                         default                        2022-04-01 11:31:07 IST               12.77
 613        Untitled        TEST2                          DB_REFRESH@2022-03-30T11:13:11         0.71                                                                                                                             75.54                 0.14                76.38
                                                                                                          AdventureWorks2012             MSSql-Timeflow-1               2022-03-30 10:30:18 BST                0.14

=cut

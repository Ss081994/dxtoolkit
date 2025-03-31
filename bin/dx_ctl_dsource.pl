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
# Copyright (c) 2016 by Delphix. All rights reserved.
#
# Program Name : dx_ctl_dsource.pl
# Description  : Create / attach / detach dSource
# Author       : Marcin Przepiorowski
# Created      : 12 Apr 2016 (v2.2.4)
#


use warnings;
use strict;
use JSON;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev); #avoids conflicts with ex host and help
use File::Basename;
use Pod::Usage;
use FindBin;
use Data::Dumper;
use version;
use Try::Tiny;

my $abspath = $FindBin::Bin;

use lib '../lib';
use Databases;
use Engine;
use Jobs_obj;
use Group_obj;
use Toolkit_helpers;
use FileMap;

my $dxversion = $Toolkit_helpers::version;

my $compression = "no";
my $dbusertype = 'database';

GetOptions(
  'help|?' => \(my $help),
  'd|engine=s' => \(my $dx_host),
  'sourcename=s' => \(my $sourcename),
  'dsourcename=s'  => \(my $dsourcename),
  'action=s' => \(my $action),
  'group=s' => \(my $group),
  'creategroup' => \(my $creategroup),
  'reponame=s' => \(my $repositoryname),
  'sourceinst=s' => \(my $sourceinst),
  'sourceenv=s' => \(my $sourceenv),
  'stageinst=s' => \(my $stageinst),
  'stageenv=s' => \(my $stageenv),
  'dbuser=s'  => \(my $dbuser),
  'dbusertype=s'  => \($dbusertype),
  'password=s'  => \(my $password),
  'cdbcont=s' => \(my $cdbcont),
  'cdbuser=s' => \(my $cdbuser),
  'cdbpass=s' => \(my $cdbpass),
  'source_os_user=s'  => \(my $source_os_user),
  'stage_os_user=s'  => \(my $stage_os_user),
  'backup_dir=s' => \(my $backup_dir),
  'backupfiles=s' => \(my $backupfiles),
  'dumppwd=s' => \(my $dumppwd),
  'mountbase=s' => \(my $mountbase),
  'logsync=s' => \(my $logsync),
  'logsyncmode=s' => \(my $logsyncmode),
  'validatedsync=s' => \(my $validatedsync),
  'delphixmanaged=s' => \(my $delphixmanaged),
  'commserver=s' => \(my $commserver),
  'commsourceclient=s' => \(my $commsourceclient),
  'commstagingclient=s' => \(my $commstagingclient),
  'exclude=s@' => \(my $exclude),
  'hadr=s' => \(my $hadr),
  'compression=s' => \($compression),
  'type=s' => \(my $type),
  'presync=s@' =>\(my $presync),
  'postsync=s@' =>\(my $postsync),
  'hooks=s' => \(my $hooks),
  'stagingpush' => \(my $stagingpush),
  'instname=s'  => \(my $instname),
  'uniqname=s'  => \(my $uniqname),
  'template=s' => \(my $template),
  'oracledbtype=s' => \(my $oracledbtype),
  'sourcehostname=s' => \(my $sourcehostname),
  'sourceport=n' => \(my $sourceport),
  'ingestiontype=s' => \(my $ingestiontype),
  'singledbname=s' => \(my $singledbname),
  'stagingport=n' => \(my $stagingport),
  'dumpdir=s' => \(my $dumpdir),
  'restorejobs=n' => \(my $restorejobs),
  'dumpjobs=n' => \(my $dumpjobs),
  'customparameters=s@' => \(my $customparameters),
  'backup_dir_log=s' => \(my $backup_dir_log),
  'keepinsync=s' => \(my $keepinsync),
  'dever=s' => \(my $dever),
  'debug:n' => \(my $debug),
  'all' => (\my $all),
  'version' => \(my $print_version),
  'configfile|c=s' => \(my $config_file)
) or pod2usage(-verbose => 1,  -input=>\*DATA);



pod2usage(-verbose => 2,  -input=>\*DATA) && exit if $help;
die  "$dxversion\n" if $print_version;


my $engine_obj = new Engine ($dever, $debug);
$engine_obj->load_config($config_file);


if (defined($all) && defined($dx_host)) {
  print "Option all (-all) and engine (-d|engine) are mutually exclusive \n";
  pod2usage(-verbose => 1,  -input=>\*DATA);
  exit (1);
}


if ( (! defined($action) ) || ( ! ( ( $action eq 'create') || ( $action eq 'attach') || ( $action eq 'detach') || ( $action eq 'update') ) ) ) {
  print "Option -action not defined or has invalid parameter - $action \n";
  pod2usage(-verbose => 1,  -input=>\*DATA);
  exit (1);
}


if (! (($action eq 'detach') || ($action eq 'update')) )  {

  # if (defined($cdbcont) && ((!defined($cdbpass)) || (!defined($cdbuser)))) {
  #   print "Option -cdbcont required a cdbpass and cdbuser to be defined \n";
  #   pod2usage(-verbose => 1,  -input=>\*DATA);
  #   exit (1);
  # }

  if (!defined($type)) {
    print "Option -type is required for this action \n";
    pod2usage(-verbose => 1,  -input=>\*DATA);
    exit (1);
  }

  if ( defined ($type) && ( ! ( ( lc $type eq 'oracle') || ( lc $type eq 'sybase') || ( lc $type eq 'mssql') || ( lc $type eq 'vfiles') || ( lc $type eq 'db2') || ( lc $type eq 'postgresql') ) ) ) {
    print "Option -type has invalid parameter - $type \n";
    pod2usage(-verbose => 1,  -input=>\*DATA);
    exit (1);
  }

  if (((lc $type eq 'vfiles') || ( lc $type eq 'db2') || ( lc $type eq 'postgresql')) && (lc $action eq 'attach')) {
    print "Can't attach $type dSource\n";
    exit (1);
  }


  if (defined($stagingpush)) {
    if (! defined($group)) {
      print "For staging push -group is required. \n";
      pod2usage(-verbose => 1,  -input=>\*DATA);
      exit (1);
    }
  }
  elsif ( ( lc $type ne 'postgresql' ) && ( lc $type ne 'db2' ) && ( ! ( defined($type) && defined($sourcename) && defined($dsourcename)  && defined($source_os_user) && defined($group) ) ) )  {
    print "Options -sourcename, -dsourcename, -group, -source_os_user are required. \n";
    pod2usage(-verbose => 1,  -input=>\*DATA);
    exit (1);
  }



  if (( lc $type eq 'sybase' ) && ( ! ( defined($stage_os_user) && defined($stageinst) && defined($stageenv) && (defined($backup_dir) || defined($backupfiles)) && defined($sourceinst) && defined($sourceenv) ) ) ) {
    print "Options -stage_os_user, -stageinst, -stageenv, -sourceinst, -sourceenv and -backup_dir are required. \n";
    pod2usage(-verbose => 1,  -input=>\*DATA);
    exit (1);
  }

  if ( defined($logsync) && ( ! ( ( lc $logsync eq 'yes') || ( lc $logsync eq 'no')  ) ) ) {
    print "Options -logsync has yes and no value only. \n";
    pod2usage(-verbose => 1,  -input=>\*DATA);
    exit (1);
  }


} else {
  if (defined ($type) && ((lc $type eq 'vfiles') || (lc $type eq 'db2') || ( lc $type eq 'postgresql') ) && (lc $action eq 'detach')) {
    print "Can't deattach $type dSource\n";
    exit (1);
  }

  if (( ! ( defined($group) ) ) && ( ! ( defined($dsourcename)  ) ) ) {
    print "Options  -dsourcename or -group are required to detach or update. \n";
    pod2usage(-verbose => 1,  -input=>\*DATA);
    exit (1);
  }
}

if ( (defined($commserver)) && ( ! ( defined($commsourceclient) && defined($commstagingclient) ) ) ) {
  print "Options -commserver requires commsourceclient and commstagingclient to be configured\n";
  pod2usage(-verbose => 1,  -input=>\*DATA);
  exit (1);
}

my %commvault;

if (defined($commserver)) {
  %commvault = (
    'commserveHostName' => $commserver,
    'sourceClientName' => $commsourceclient,
    'stagingClientName' => $commstagingclient
  );
}


# this array will have all engines to go through (if -d is specified it will be only one engine)
my $engine_list = Toolkit_helpers::get_engine_list($all, $dx_host, $engine_obj);

my $ret = 0;

for my $engine ( sort (@{$engine_list}) ) {
  # main loop for all work
  if ($engine_obj->dlpx_connect($engine)) {
    print "Can't connect to Dephix Engine $dx_host\n\n";
    $ret = $ret + 1;
    next;
  };


  if (((lc $action eq 'attach') || (lc $action eq 'create')) && (( lc $type ne 'db2' ) && ( lc $type ne 'vfiles' ) && (! ( defined($dbuser) && defined($password)  ) ) ) ) {
    # no db user exceptions
    if (!defined($stagingpush)) {
      if (( lc $type eq 'mssql' ) && ( lc $dbusertype eq 'environment' ) )   {
        $dbuser = $source_os_user;
      } elsif (lc $type eq 'oracle') {
          if ( ! (version->parse($engine_obj->getApi()) >= version->parse(1.11.7) ) ) {
            print "Options -dbuser and -password are required for Oracle for version lower than 6.0.7 \n";
            pod2usage(-verbose => 1,  -input=>\*DATA);
            exit (1)
          }
      } elsif (lc $type eq 'postgresql') {
        if ( lc $ingestiontype ne 'externalbackup' ) {
          print "Options -dbuser and -password are required for non vFiles dsources. \n";
          pod2usage(-verbose => 1,  -input=>\*DATA);
          exit (1);   
        }
      } else {
        print "Options -dbuser and -password are required for non vFiles dsources. \n";
        pod2usage(-verbose => 1,  -input=>\*DATA);
        exit (1);
      }
    }
  }


  my $db;
  my $jobno;

  my $groups = new Group_obj($engine_obj, $debug);

  if ((lc $action eq 'detach') || (lc $action eq 'update')) {
    my $databases = new Databases($engine_obj,$debug);

    my $source_ref = Toolkit_helpers::get_dblist_from_filter(undef, $group, undef, $dsourcename, $databases, $groups, undef, undef, undef, undef, undef, undef, $repositoryname, $debug);

    if (!defined($source_ref)) {
      print "Source database not found.\n";
      $ret = $ret + 1;
      next;
    } 


    for my $dbref (@{$source_ref}) {

      my $source = ($databases->getDB($dbref));

      # only for sybase and mssql
      my $type = $source->getDBType();
      if ($action eq 'detach')  {
        # detach dSource
        $jobno = $source->detach_dsource();
        $ret = $ret + Toolkit_helpers::waitForAction($engine_obj, $jobno, "Action completed with success", "There were problems with dSource detach");
      } else {
        # update dSource
        if ((lc $type eq 'sybase') || (lc $type eq 'mssql')) {
          $jobno = $source->update_dsource($backup_dir, $logsync, $validatedsync);
          if (defined($jobno)) {
            $ret = $ret + Toolkit_helpers::waitForAction($engine_obj, $jobno, "Action completed with success", "There were problems with dSource update");
          }
          $jobno = $source->update_dsource_config( $stageenv, $stageinst );
          if (defined($jobno)) {
            $ret = $ret + Toolkit_helpers::waitForAction($engine_obj, $jobno, "Action completed with success", "There were problems with dSource config update");
          }
          if (defined($logsync)) {
            $jobno = $source->setLogSync($logsync);
            if (defined($jobno)) {
              $ret = $ret + Toolkit_helpers::waitForAction($engine_obj, $jobno, "Action completed with success", "There were problems with dSource update");
            }
          }
        } elsif (lc $type eq 'oracle') {
          $jobno = $source->update_dsource($backup_dir, $logsync, $logsyncmode);
          if (defined($jobno)) {
            $ret = $ret + Toolkit_helpers::waitForAction($engine_obj, $jobno, "Action completed with success", "There were problems with dSource update");
          }
        } else {
          print "Update action not supported for dSource type $type\n";
          $ret = $ret + 1;
        }

      }




    }

  } elsif ($action eq 'attach')  {
    my $databases = new Databases($engine_obj,$debug);

    my $source_ref = Toolkit_helpers::get_dblist_from_filter(undef, $group, undef, $dsourcename, $databases, $groups, undef, undef, undef, undef, undef, undef, $repositoryname, $debug);

    if (!defined($source_ref)) {
      print "Source database not found.\n";
      $ret = $ret + 1;
      next;
    }
    elsif (scalar(@{$source_ref})>1) {
      print "Source database not unique defined.\n";
      $ret = $ret + 1;
      next;
    } elsif (scalar(@{$source_ref}) eq 0) {
      print "Source database not found.\n";
      $ret = $ret + 1;
      next;
    }

    # there will be only one database object in the list so we need to assign it to obj variable
    my $source = ($databases->getDB($source_ref->[0]));

    if ( $type eq 'oracle' ) {
      $jobno = $source->attach_dsource($sourcename,$sourceinst,$sourceenv,$source_os_user,$dbuser,$password,$cdbcont, $stagingpush);
    } else {
      $jobno = $source->attach_dsource($sourcename,$sourceinst,$sourceenv,$source_os_user,$dbuser,$password,$stageenv,$stageinst,$stage_os_user, $backup_dir, $validatedsync, $delphixmanaged, $compression, $dbusertype, $stagingpush);
    }


    # you can attach only one dSource at the time so one job
    $ret = $ret + Toolkit_helpers::waitForAction($engine_obj, $jobno, "Action completed with success", "There were problems with dSource action");

  } elsif ($action eq 'create') {

    # create a group for new dSource
    if (! defined($groups->getGroupByName($group))) {
      if (defined($creategroup)) {
        print "Creating not existing group - $group \n";
        my $jobno = $groups->createGroup($group);
        my $actionret = Toolkit_helpers::waitForAction($engine_obj, $jobno, "Action completed with success", "There were problems with group creation");
        if ($actionret > 0) {
          $ret = $ret + 1;
          print "There was a problem with group creation. Skipping source actions on engine\n";
          next;
        }
      } else {
        print "Group $group for target database doesn't exist.\n Skipping source actions on engine.\n";
        $ret = $ret + 1;
        next;
      }
    }


    if (!defined($logsync)) {
      $logsync = 'no';
    }


    if ( $type eq 'oracle' ) {
      my $db = new OracleVDB_obj($engine_obj,$debug);

      if (defined($cdbcont) && defined($cdbuser)) {
        if ($db->discoverPDB($sourceinst,$sourceenv,$cdbcont,$cdbuser,$cdbpass)) {
          print "There was an error with PDB discovery \n";
          $ret = $ret + 1;
          next;
        }
      }
      if (addhooks($hooks, $db, $presync, $postsync)) {
        $ret = $ret + 1;
        last;
      }
      if (defined($stagingpush)) {
        $jobno = $db->addSource($sourcename,$stageinst,$stageenv,$stage_os_user,undef, undef, $dsourcename, $group, $logsync, $cdbcont, $stagingpush, $instname, $uniqname, $template, $oracledbtype, $mountbase);
      } else {
        $jobno = $db->addSource($sourcename,$sourceinst,$sourceenv,$source_os_user,$dbuser,$password,$dsourcename,$group,$logsync, $cdbcont, $stagingpush);
      }
    }
    elsif ($type eq 'sybase') {
      my $db = new SybaseVDB_obj($engine_obj,$debug);
      if (addhooks($hooks, $db, $presync, $postsync)) {
        $ret = $ret + 1;
        last;
      }
      $jobno = $db->addSource($sourcename,$sourceinst,$sourceenv,$source_os_user,$dbuser,$password,$dsourcename,$group,$logsync,$stageenv,$stageinst,$stage_os_user, $backup_dir, $dumppwd, $mountbase);
    }
    elsif ($type eq 'mssql') {
      my $db = new MSSQLVDB_obj($engine_obj,$debug);
      if (addhooks($hooks, $db, $presync, $postsync)) {
        $ret = $ret + 1;
        last;
      }
      $jobno = $db->addSource($sourcename,$sourceinst,$sourceenv,$source_os_user,$dbuser,$password,$dsourcename,$group,$logsync,$stageenv,$stageinst,$stage_os_user, $backup_dir, $dumppwd, $validatedsync, $delphixmanaged, $compression, $dbusertype, \%commvault, $stagingpush);
    }
    elsif ($type eq 'vFiles') {
      my $db = new AppDataVDB_obj($engine_obj,$debug);
      if (addhooks($hooks, $db, $presync, $postsync)) {
        $ret = $ret + 1;
        last;
      }
      $jobno = $db->addSource($sourcename,$sourceinst,$sourceenv,$source_os_user,$dsourcename,$group, $exclude);
    }
    elsif ($type eq 'db2') {
      my $db = new DB2VDB_obj($engine_obj,$debug);
      if (addhooks($hooks, $db, $presync, $postsync)) {
        $ret = $ret + 1;
        last;
      }
      $jobno = $db->addSource($sourcename,$sourceinst,$sourceenv,$source_os_user,$dbuser,$password,$dsourcename,$group,$logsync,$stageenv,$stageinst,$stage_os_user, $backup_dir, $hadr);
    }
    elsif ($type eq 'postgresql') {
      my $db = new PostgresVDB_obj($engine_obj,$debug);
      if (addhooks($hooks, $db, $presync, $postsync)) {
        $ret = $ret + 1;
        last;
      }
      $jobno = $db->addSource($sourcename,$dbuser,$password,$dsourcename,$group,$logsync,$stageenv,$stageinst,$stage_os_user, $backup_dir, 
               $sourcehostname, $sourceport, $ingestiontype, $dumpdir, $restorejobs, $dumpjobs, $stagingport, $singledbname, $mountbase,
               $customparameters, $backup_dir, $backup_dir_log, $keepinsync);

    }

    # we are adding only one dSource - so one job
    $ret = $ret + Toolkit_helpers::waitForAction($engine_obj, $jobno, "Action completed with success", "There were problems with dSource action");

  }



}

exit $ret;


sub addhooks {
  my $hooks = shift;
  my $db = shift;
  my $presync = shift;
  my $postsync = shift;

  if ( defined($presync) ) {
    if ($db->setPreSyncHook($presync)) {
      return 1;
    }
  }

  if ( defined($postsync) ) {
    if ($db->setPostSyncHook($postsync)) {
      return 1;
    }
  }

  if (defined($hooks)) {
    my $FD;
    if (!open ($FD, '<', "$hooks")) {
      print "Can't open a file with hooks: $hooks\n";
      return 1;
    }
    local $/ = undef;
    my $json = JSON->new();
    my $loadedHooks;
    try {
      $loadedHooks = $json->decode(<$FD>);
    } catch {
      print 'Error parsing hooks file. Please check it. ' . $_ . " \n" ;
      close $FD;
      return 1;
    };
    close $FD;

    if (($loadedHooks->{type} ne 'LinkedSourceOperations') && ($loadedHooks->{type} ne 'OracleLinkedSourceOperations') ){
      print '$hooks is not a export file from dx_get_dbhooks\n' ;
      return 1;
    }

    $db->setHooksfromJSON($loadedHooks);

  }
  return 0;
}

__DATA__


=head1 SYNOPSIS

 dx_ctl_dsource [ -engine|d <delphix identifier> | -all ] [ -configfile file ]
                -action create, attach, detach
                -type dsourcetype
                -sourcename name
                -dsourcename dsourcename
                -group groupname
                -sourceinst source_instance
                -sourceenv source_environment
                -dbuser username
                -password password
                -source_os_user osusername
                [-creategroup]
                [-logsync yes/no ]
                [-logsyncmode redo|arch]
                [-stageinst staging_inst ]
                [-stageenv staging_env ]
                [-stage_os_user staging_osuser ]
                [-backup_dir backup_dir ]
                [-dumppwd password ]
                [-mountbase mountpoint ]
                [-validatedsync mode ]
                [-delphixmanaged yes/no ]
                [-dbusertype database|environment|domain]
                [-cdbcont container -cdbuser user -cdbpass password]
                [-commserver Commvault servername]
                [-commsourceclient Commvault client name]
                [-commstagingclient Commvault staging name]
                [-exclude path]
                [-hooks path_to_hooks]
                [-presync [hookname,]template|filename[,OS_shell] ]
                [-postsync [hookname,]template|filename[,OS_shell] ]
                [-stagingpush]
                [-oracledbtype nonmt|cdb|pdb]
                [-customparameters (param_name=value)|(#param_name)]
                [-ingestiontype single|initalized|externalbackup ] 
                [-sourcehostname hostname ] 
                [-sourceport xxx]
                [-singledbname dbname]
                [-stagingport xxx ]
                [-dumpdir directory]
                [-restorejobs x]
                [-dumpjobs x]
                [-backup_dir_log directory]
                [-keepinsync yes|no]
                [-debug ]
                [-version ]
                [-help|? ]

=head1 DESCRIPTION

Create or attache dSource to a Delphix Engine

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

=head2 dSource arguments

=over 1

=item B<-type>
Type (oracle|sybase|mssql|db2|vfiles)

=item B<-action>
Action - create, attach, detach, update

Update action can change a backup path and validated sync mode for MS SQL and Sybase dsources

=item B<-group>
Source Group Name

=item B<-sourcename>
Database Name

=item B<-dsourcename>
dSource name

=item B<-sourceinst source_instance>
Source database instance / home

=item B<-sourceenv source_environment>
Source database environment name

=item B<-dbuser username>
Database user

=item B<-password password>
Database password

=item B<-source_os_user osusername>
Source database os user

=item B<-stageinst staging_inst>
Staging database instance

=item B<-stageenv staging_env>
Staging database environment


=item B<-stage_os_user staging_osuser>
Staging database os user

=item B<-backup_dir backup_dir>
Backup location. From Delphix 5.2.3 multiple backup locations with comma separation can be specified
for MS SQL dSource.

=item B<-logsync yes/no>
Enable or no LogSync for dSource. Default LogSync is disabled.

=item B<-logsyncmode redo|arch>
LogSync mode for Oracle only - allowed values redo to use redo/archivlog logsync
or arch for Archive log only

=item B<-dumppwd password>
Password for backup used to create dsource

=item B<-mountbase mountpoint>
For Sybase only - mount point for staging server

=item B<-validatedsync mode>
Set validated sync mode for MS SQL and Sybase

Allowed values for MS SQL:
TRANSACTION_LOG, FULL, FULL_OR_DIFFERENTIAL, NONE

Allowed values for Sybase:
DISABLED, ENABLED

=item B<-delphixmanaged yes/no>
Use Delphix Manage backup mode for MS SQL

=item B<-cdbcont container>
Oracle only - CDB container for a PDB dSource

=item B<-cdbuser user>
Oracle only - CDB user for a PDB dSource

=item B<-cdbpass password>
Oracle only - CDB password for a PDB dSource

=item B<-creategroup>
Create a Delphix group if it doesn't exist

=item B<-dbusertype database|environment|domain>
Specify a database user type for MS SQL. Default value is database.

=item B<-commserver Commvault servername>
Commvault server name

=item B<-commsourceclient Commvault client name>
Commvault client name

=item B<-commstagingclient Commvault staging name>
Commvault staging name

=item B<-stagingpush>
Create dsource using staging push technology ( current support MS SQL )

=item B<-oracledbtype nonmt|cdb|pdb>
Oracle staging push database type:

 - nonmt - for Oracle non multitenant
 - cdb - for Oracle Container ( required before PDB )
 - pdb - for Oracle Pluggable database

=item B<-hadr hadrPrimarySVC:XXX,hadrPrimaryHostname:hostname,hadrStandbySVC:YYY>
Add DB2 dSource with HADR support
Parameter hadrTargetList is optional.

ex.
hadrPrimarySVC:50001,hadrPrimaryHostname:marcindb2src.dcenter,hadrStandbySVC:50011,hadrTargetList:marcindb2src.dcenter:50001

=item B<-exclude path>
Exclude path for vFiles dSources

=item B<-hooks path_to_hooks>
Import hooks exported using dx_get_hooks

=item B<-customparameters (param_name=value)|(#param_name)>
Provide a custom parameter for Postgresql. For more then one parameter, use -customparameters multiple times.
To comment an existing variable inside Postgresql VDB, put a # sign before a parameter.

=item B<-ingestiontype single|initalized|externalbackup >
Postgresql dSource ingestion type

=item B<-sourcehostname hostname>
Postgresql dSource source host

=item B<-sourceport xxx>
Postgresql dSource source port

=item B<-singledbname dbname>
Postgresql dSource single database name

=item B<-stagingport xxx>
Postgresql dSource staging port

=item B<-dumpdir directory>
Postgresql dSource single database dump directory

=item B<-restorejobs x>
Postgresql dSource single database number of restore jobs

=item B<-dumpjobs x>
Postgresql dSource single database number of dump joba

=item B<-backup_dir_log>
Location of WAL logs for external Postgresql ingestion

=item B<-keepinsync yes|no->
Keep a dSource in sync using Postgresql replication. If value set to yes, replication parameters are mandatory

=back

=head2 Hooks

Hook definition.

File name is a path to a file with a hook body on machine
with dxtoolkit.

Template name is an operational template name

Allowed combinations:

 - hookname,template_name,OS_shell

 - hookname,filename,OS_shell

 - hookname,template_name

 - hookname,filename

 - template_name

 - filename


OS sheel allowed:
- BASH - to force bash
- SHELL - to use default OS user shell
- PS - to force PowerShell 2
- PSD - to use default PowerShell

=over 1

=item B<-presync [hookname,]template|filename[,OS_shell]>
PreSync hook

=item B<-postsync [hookname,]template|filename[,OS_shell]>
PostSync hook

=back

=head1 OPTIONS

=over 2

=item B<-help>
Print this screen

=item B<-debug>
Turn on debugging

=back



=head1 EXAMPLES

Create a Sybase dSource from database called pub3 running on instance LINUXSOURCE discovered in environment LINUXSOURCE,
staging environment is on LINUXTARGET environment with instance named LINUXTARGET

 dx_ctl_dsource -d Landshark5 -type sybase -sourcename pubs3 -sourceinst LINUXSOURCE -sourceenv LINUXSOURCE \
                -source_os_user delphix -dbuser sa -password delphixdb -group Sources -dsourcename "Sybase dsource" \
                -stage_os_user delphix -stageinst LINUXTARGET -stageenv LINUXTARGET -backup_dir "/u02/sybase_back"
                -action create -dumppwd xxxxxx
 Waiting for all actions to complete. Parent action is ACTION-2995
 Action completed with success.

Create an Oracle dSource from database unique name TESTU running from
Oracle Home "/u01/app/oracle/product/11.2.0/dbhome_1" discovered in environment LINUXSOURCE

 dx_ctl_dsource -d Landshark5 -type oracle -sourcename TESTU -sourceinst /u01/app/oracle/product/11.2.0/dbhome_1 \
                -sourceenv LINUXSOURCE -source_os_user delphix -dbuser delphixdb -password delphixdb -group Sources \
                -dsourcename "ORACLE dsource" -action create
 Waiting for all actions to complete. Parent action is ACTION-3011
 Action completed with success.

Create an MSSQL dSource from database unique name AdventureWorksLT2008R2 running on MSSQLSERVER instance discovered in
environment WINDOWSSOURCE, staging environment is on WINDOWSTARGET environment with instance named MSSQLSERVER

 dx_ctl_dsource -d Landshark5 -type mssql -sourcename AdventureWorksLT2008R2 -sourceinst MSSQLSERVER \
                -sourceenv WINDOWSSOURCE -source_os_user "DELPHIX\delphix_admin" -dbuser aw -password delphixdb \
                -group Sources -dsourcename AdventureWorksLT2008R2 -stage_os_user "DELPHIX\delphix_admin"
                -stageinst MSSQLSERVER - stageenv WINDOWSTARGET -backup_dir "\\\\172.16.180.133\\backups" -action create
 Waiting for all actions to complete. Parent action is ACTION-3050
 Action completed with success.

Detach dsource

 dx_ctl_dsource -d Landshark5 -action detach -dsourcename "Sybase dsource"
 Waiting for all actions to complete. Parent action is ACTION-3050
 Action completed with success.

Attach Sybase dsource

 dx_ctl_dsource -d Landshark5 -action attach -type sybase -sourcename pubs3 -sourceinst LINUXSOURCE -sourceenv LINUXSOURCE \
                -source_os_user delphix -dbuser sa -password delphixdb -group Sources -dsourcename "Sybase dsource" \
                -stage_os_user delphix -stageinst LINUXTARGET -stageenv LINUXTARGET -backup_dir "/u02/sybase_back"
 Waiting for all actions to complete. Parent action is ACTION-12699
 Action completed with success

Attach Oracle dsource

 dx_ctl_dsource -d Landshark5 -action attach -type oracle -sourcename TESTU -sourceinst /u01/app/oracle/product/11.2.0/dbhome_1 \
                              -sourceenv LINUXSOURCE -source_os_user delphix -dbuser delphixdb -password delphixdb \
                              -group Sources -dsourcename "Oracle dsource"
 Waiting for all actions to complete. Parent action is ACTION-12691
 Action completed with success


Attach Oracle PDB dsource

 dx_ctl_dsource -d Landshark5 -action attach -type oracle -sourcename PDB1 -source_os_user delphix  \
                              -group Sources -dsourcename "PDB1" -cdbcont CDOML_A
 Waiting for all actions to complete. Parent action is ACTION-1023
 Action completed with success


Adding an Oracle PDB dSource

 dx_ctl_dsource -d Landshark5 -action create -sourcename PDB1 -type oracle -sourceinst /u01/app/oracle/12.2.0.1/db1 \
                              -sourceenv LINUXSOURCE -source_os_user oracle -dbuser delphixdb -password delphixdb -group Sources \
                              -dsourcename PDB1 -cdbcont test122 -cdbuser c##delphixdb -cdbpass delphixdb
 Setting credential for CDB test122 sucessful.
 Waiting for all actions to complete. Parent action is ACTION-13947
 Action completed with success

Adding a DB2 dSource without HADR
 dx_ctl_dsource -d 531 -stage_os_user auto1052 -stageenv marcindb2tgt -stageinst "auto1052 - 10.5.0.5 - db2aese" -action create -type db2  \
                       -sourcename R74D105D -dsourcename dsourceR74D105D -group Untitled -backup_dir "/db2backup"
 Waiting for all actions to complete. Parent action is ACTION-1870
 Action completed with success

Adding a DB2 dSource with HADR

 dx_ctl_dsource -d 531 -stage_os_user auto1052 -stageenv marcindb2tgt -stageinst "auto1052 - 10.5.0.5 - db2aese" -action create -type db2 \
                       -sourcename R74D105E  -dsourcename R74D105E -group Untitled -backup_dir "/db2backup" \
                       -hadr "hadrPrimarySVC:50001,hadrPrimaryHostname:marcindb2src.dcenter,hadrStandbySVC:50011,hadrTargetList:marcindb2src.dcenter:50001"
 Waiting for all actions to complete. Parent action is ACTION-1879
 Action completed with success


Adding a vFiles dSource

 dx_ctl_dsource -d test -action create -group "Untitled" -creategroup -dsourcename "vtest"  -type vFiles -sourcename "vtest" -sourceinst "Unstructured Files" \
                -sourceenv "marcintgt" -source_os_user "delphix" -exclude "dir1/dir2" -exclude "dir3"
 Waiting for all actions to complete. Parent action is ACTION-2919
 Action completed with success

Adding a Posgresql dSource using Delphix initialized backup

 dx_ctl_dsource -d dxtest -action create -group "Untitled" -creategroup -dsourcename "postdsource"  -type postgresql -sourcename "postdsource" -stageinst "Postgres vFiles (15.2)" \
                -stageenv "POSTSTG" -stage_os_user "postgres" -mountbase "/mnt/provision/postdsource" -password xxxxxxxxx -stagingport 5433 -ingestiontype initiated \
                -dbuser "delphix" -sourcehostname "sourceserver" -sourceport 5432 -customparameters "deadlock_timeout=123s"
 Waiting for all actions to complete. Parent action is ACTION-734
 Action completed with success

Adding a Posgresql dSource using single database ingestion

dx_ctl_dsource -d dxtest -action create -group "Untitled" -creategroup -dsourcename "postdsource"  -type postgresql -sourcename "postdsource_cluster" -stageinst "Postgres vFiles (15.2)" \
               -stageenv "POSTSTG" -mountbase "/mnt/provision/pioro" -dbuser "postgres" -password xxxxxxxxx -stagingport 5433 -sourcehostname "sourceserver" \
               -ingestiontype single  -sourceport 5432 -singledbname "singleDB" -dumpdir "/home/postgres" -restorejobs 2 -dumpjobs 2

Adding a Postgresql dSource using external backup

 dx_ctl_dsource -d dxtest -action create -group "Untitled" -creategroup -dsourcename "extbac" -type postgresql -sourcename "extbac" -stageinst "Postgres vFiles (15.2)" \
                -stageenv "POSTSTG"  -mountbase "/mnt/provision/extbac" -stagingport 5434 -ingestiontype externalbackup \
                -backup_dir "/home/postgres/backup" -backup_dir_log "/home/postgres/backup" -keepinsync no


Updating a backup path and validated sync mode for Sybase

 dx_ctl_dsource -d Landshark5 -action update -validatedsync ENABLED -backup_dir "/u02/sybase_back" -dsourcename pubs3
 Waiting for all actions to complete. Parent action is ACTION-20194
 Action completed with success

 Updating a backup path and validated sync mode for MS SQL

  dx_ctl_dsource -d Landshark5 -action update -validatedsync FULL -backup_dir "\\\\172.16.180.10\\loc1,\\\\172.16.180.10\\loc2" -dsourcename AdventureWorks2012
  Waiting for all actions to complete. Parent action is ACTION-20190
  Action completed with success


Update a staging server and instance for Sybase or MS SQL

  dx_ctl_dsource -d Landshark5 -action update -dsourcename pubs3 -backup_dir /u02/sybase_backup -stageinst LINUXTARGET -stageenv linuxtarget
  Waiting for all actions to complete. Parent action is ACTION-8576
  Action completed with success
  Waiting for all actions to complete. Parent action is ACTION-8577
  Action completed with success


Update a staging server and instance for Sybase or MS SQL based on group

  dx_ctl_dsource -d Landshark5 -action update -group SybaseSource -backup_dir /u02/sybase_backup -stageinst LINUXTARGET -stageenv linuxtarget
  Waiting for all actions to complete. Parent action is ACTION-8593
  Action completed with success
  Waiting for all actions to complete. Parent action is ACTION-8594
  Action completed with success




=cut

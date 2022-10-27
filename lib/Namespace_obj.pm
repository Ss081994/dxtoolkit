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
# Copyright (c) 2015,2016 by Delphix. All rights reserved.
#
# Program Name : Namespace_obj.pm
# Description  : Delphix Engine Namespace object
# It's include the following classes:
# - Namespace_obj - class which map a Delphix Engine namespace API object
# Author       : Marcin Przepiorowski
# Created      : 02 Sep 2015 (v2.0.0)
#


package Namespace_obj;

use warnings;
use strict;
use Data::Dumper;
use JSON;
use Toolkit_helpers qw (logger);

use lib '../lib';

use Jobs;

# constructor
# parameters 
# - dlpxObject - connection to DE
# - debug - debug flag (debug on if defined)

sub new {
    my $classname  = shift;
    my $dlpxObject = shift;
    my $debug = shift;
    logger($debug, "Entering Namespace_obj::constructor",1);

    my %namespace;
    my %replica_state;
    my $self = {
        _namespace => \%namespace,
        _dlpxObject => $dlpxObject,
        _debug => $debug,
        _replication_state => \%replica_state
    };
    
    bless($self,$classname);    
    $self->loadNamespaceList($debug);
    return $self;
}


# Procedure getNamespaceByName
# parameters: 
# - name 
# Return namespace reference for particular name

sub getNamespaceByName {
    my $self = shift;
    my $name = shift;
    logger($self->{_debug}, "Entering Namespace_obj::getNamespaceByName",1);    
    my $ret;

    #print Dumper $$config;

    for my $namespaceitem ( sort ( keys %{$self->{_namespace}} ) ) {

        if ( $self->getName($namespaceitem) eq $name) {
            $ret = $namespaceitem; 
        }
    }

    return $ret;
}

# Procedure getNamespace
# parameters: 
# - reference
# Return namespace hash for specific namespace reference

sub getNamespace {
    my $self = shift;
    my $reference = shift;
    
    logger($self->{_debug}, "Entering Namespace_obj::getNamespace",1);    

    my $namespaces = $self->{_namespace};
    return $namespaces->{$reference};
}


# Procedure getNamespaceList
# parameters: 
# Return namespace list

sub getNamespaceList {
    my $self = shift;
    my $reference = shift;
    
    logger($self->{_debug}, "Entering Namespace_obj::getNamespaceList",1);    

    return sort(keys %{$self->{_namespace}});
}


# Procedure getName
# parameters: 
# - reference
# Return namespace name for specific namespace reference

sub getName {
    my $self = shift;
    my $reference = shift;
    
    logger($self->{_debug}, "Entering Namespace_obj::getName",1);   

    my $namespaces = $self->{_namespace};
    return $namespaces->{$reference}->{name};
}


# Procedure getTag
# parameters: 
# - reference
# Return namespace tag for specific namespace reference

sub getTag {
    my $self = shift;
    my $reference = shift;
    
    logger($self->{_debug}, "Entering Namespace_obj::getTag",1);   

    my $namespaces = $self->{_namespace};
    return $namespaces->{$reference}->{tag};
}




# Procedure loadNamespaceList
# parameters: none
# Load a list of template objects from Delphix Engine

sub loadNamespaceList 
{
    my $self = shift;
    logger($self->{_debug}, "Entering Namespace_obj::loadNamespaceList",1);   

    my $operation = "resources/json/delphix/namespace";
    my ($result, $result_fmt) = $self->{_dlpxObject}->getJSONResult($operation);
    if (defined($result->{status}) && ($result->{status} eq 'OK')) {
        my @res = @{$result->{result}};
        my $namespaces = $self->{_namespace};

        for my $namespaceitem (@res) {
            $namespaces->{$namespaceitem->{reference}} = $namespaceitem;
        } 
    } else {
        print "No data returned for $operation. Try to increase timeout \n";
    }
}


# Procedure findlastreplica
# parameters: none
# Find last replica

sub findlastreplica {
  my $self = shift;
  logger( $self->{_debug}, "Entering Namespace_obj::findlastreplica", 1 );

  $self->loadReplicationState();
  my $jobs;

  my %times;

  for my $spec (keys(%{$self->{_replication_state}})) {
    my @objarray = ($spec);
    $jobs = new Jobs($self->{_dlpxObject}, undef, undef, 'COMPLETED', undef, undef, undef, \@objarray, undef, undef, $self->{_debug});
    my $jobobj;

    

    my $jobref = (@{$jobs->getJobList()})[-1];
    my $nsref = $self->getNamespaceByName($self->{_replication_state}->{$spec}->{"name"});
    if (defined($jobref)) {
      $jobobj = $jobs->getJob($jobref);
      if (defined($jobobj)) {
        $times{$nsref} = $jobobj->getJobStartTimeWithTZ();
      } else {
        $times{$nsref} = "N/A";
      }
    } else {
      $times{$nsref} = "N/A";
    }
    
  }

  return \%times;
  

}

# Procedure loadReplicationState
# parameters: none
# Load replication state

sub loadReplicationState {
  my $self = shift;
  logger( $self->{_debug}, "Entering Namespace_obj::loadReplicationState", 1 );

  my $operation = "resources/json/delphix/replication/targetstate";
  my ( $result, $result_fmt ) = $self->{_dlpxObject}->getJSONResult($operation);
  my $replication_state;
  if ( defined( $result->{status} ) && ( $result->{status} eq 'OK' ) ) {
    my @res = @{ $result->{result} };
    if ( scalar( @{ $result->{result} } ) ) {

      $replication_state = $self->{_replication_state};

      for my $repitem (@res) {
        $replication_state->{ $repitem->{reference} } = $repitem;
      }

    }
  }
  else {
    print "No data returned for $operation. Try to increase timeout \n";
  }


}


# Procedure deletenamespace
# parameters:
# - repref - current replication id to process
# Delete a profile

sub deletenamespace {
  my $self = shift;
  my $repref = shift;
  logger( $self->{_debug}, "Entering Namespace_obj::deletenamespace", 1 );
  logger( $self->{_debug}, "Obj ref " . $repref , 2 );
  my $operation = "resources/json/delphix/namespace/" . $repref . "/delete";
  return $self->runJobOperation( $operation, '{}', 'ACTION' );
}

# Procedure failovernamespace
# parameters:
# - repref - current replication id to process
# Delete a profile

sub failovernamespace {
  my $self = shift;
  my $repref = shift;
  my $smart = shift;
  logger( $self->{_debug}, "Entering Namespace_obj::failovernamespace", 1 );
  logger( $self->{_debug}, "Obj ref " . $repref , 2 );

  my %failhash = (
    "type" => "NamespaceFailoverParameters"
  );

  if (lc $smart eq 'yes') {
    $failhash{"smartFailover"} = JSON::true;
  } else {
    $failhash{"smartFailover"} = JSON::false;
  }

  my $json = to_json(\%failhash);

  my $operation = "resources/json/delphix/namespace/" . $repref . "/failover";
  return $self->runJobOperation( $operation, $json, 'ACTION' );
}

# Procedure translateObject
# parameters: 
# - namespace - local namespace ref
# - object - object id from replication source
# Return a object name from local namespace for a object from replication source
# undef if error

sub translateObject 
{
    my $self = shift;
    my $namespace = shift;
    my $object = shift;
    logger($self->{_debug}, "Entering Namespace_obj::translateObject",1);  
    
    my $localobj;
    
    if (!defined($self->{_namespace}->{$namespace})) {
      print "Namespace not found\n";
      return undef;
    } 

    my $operation = "resources/json/delphix/namespace/" . $namespace . "/translate?object=" . $object;
    my ($result, $result_fmt) = $self->{_dlpxObject}->getJSONResult($operation);
    if (defined($result->{status}) && ($result->{status} eq 'OK')) {
      $localobj = $result->{result};
    } else {
      if (!($result->{error}->{details} =~ m/(.*)could not be translated to namespace(.*)/)) {
        print "Error during object translation \n";
      }
    }

    return $localobj;

}


# Procedure generate_replicate_mapping
# parameters: 
# - engine_parent - parent Engine object
# - timeflow_parent - parent Timeflow object 
# Return a hash with current and parent engine object mapping

sub generate_replicate_mapping {
    my $self = shift;
    my $engine_parent = shift;
    my $timeflow_parent = shift;
    my $replication_parent = shift;
    logger($self->{_debug}, "Entering Namespace_obj::translateObject",1);  

  
    my @namespace_list = $self->getNamespaceList();
    
    my %object_hash;
  
    for my $nsitem (@namespace_list) {
      my $tag = $self->getTag($nsitem);
      my $replica_source_ref = $replication_parent->getReplicationByTag($tag);
      my $localobj;  
      my $localtf;  
    
      logger($self->{_debug}, "Namespace id: " . $nsitem, 2);
      
      if (defined($replica_source_ref)) {
    
        for my $obj (@{$replication_parent->getObjects($replica_source_ref)}) {
        
          logger($self->{_debug}, "obj " . $obj, 2);

          $localobj = $self->translateObject($nsitem,$obj);

          if (!defined($localobj)) {
            $localobj = 'no replica for ' . $obj . ' in ' . $nsitem;
          }
        
          logger($self->{_debug}, "remotetf - " . Dumper $obj, 2);
          logger($self->{_debug}, "localtf  - " . Dumper $localobj, 2);

          $object_hash{$localobj} = $obj;

        
          for my $remotetf (@{$timeflow_parent->getTimeflowsForContainer($obj)}) {
            

            $localobj = $self->translateObject($nsitem,$remotetf);

            if (!defined($localobj)) {
              $localobj = 'no replica for ' . $obj . ' in ' . $nsitem;
            }
          
            logger($self->{_debug}, "remotetf - " . Dumper $remotetf, 2);
            logger($self->{_debug}, "localtf  - " . Dumper $localobj, 2);

            $object_hash{$localobj} = $remotetf;
            
          }
        }
      } else {
        print "Replication profile not found (possibly deleted) - parents for some objects can't be found\n";
      }
  }
  
  logger($self->{_debug}, \%object_hash, 2);
    
  return \%object_hash;
  
}

# Procedure runJobOperation
# parameters:
# - operation - API string
# - json_data - JSON encoded data
# Run POST command running background job for particular operation and json data
# Return job number if job started or undef otherwise

sub runJobOperation {
  my $self      = shift;
  my $operation = shift;
  my $json_data = shift;
  my $action    = shift;

  logger( $self->{_debug}, "Entering Namespace_obj::runJobOperation", 1 );
  logger( $self->{_debug}, $operation, 2 );

  my ( $result, $result_fmt ) = $self->{_dlpxObject}->postJSONData( $operation, $json_data );
  my $jobno;

  if ( defined( $result->{status} ) && ( $result->{status} eq 'OK' ) ) {
    if ( defined($action) && $action eq 'ACTION' ) {
      $jobno = $result->{action};
    }
    else {
      $jobno = $result->{job};
    }
  }
  else {
    if ( defined( $result->{error} ) ) {
      print "Problem with starting job\n";
      print "Error: " . Toolkit_helpers::extractErrorFromHash( $result->{error}->{details} ) . "\n";
      logger( $self->{_debug}, "Can't submit job for operation $operation",   1 );
      logger( $self->{_debug}, "error " . Dumper $result->{error}->{details}, 1 );
      logger( $self->{_debug}, $result->{error}->{action},                    1 );
    }
    else {
      print "Unknown error. Try with debug flag\n";
    }
  }

  return $jobno;
}

1;
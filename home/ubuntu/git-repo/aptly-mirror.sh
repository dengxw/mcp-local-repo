#!/bin/bash
#
# Copyright 2014 Hewlett-Packard Development Company, L.P.
# All Rights Reserved.
# Authored by Yazz D. Atlas <yazz.atlas@hp.com>
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#
# Creating a tempfile directory to use later maybe
tempdir=$(mktemp -d )  || { echo "Failed to create temp file"; exit 1; }
line="---------------------------------------------------"

# If I need tempfiles lets do it cleanly 
function cleanup {
  echo ${line}
#  cat ${tempdir}/*
  rm -rf ${tempdir} 
  echo "Removed ${tempdir}"
  exit
}


function fail {
    errcode=$? # save the exit code as the first thing done in the trap function
    echo "error $errorcode"
    echo "the command executing at the time of the error was"
    echo "$BASH_COMMAND"
    echo "on line ${BASH_LINENO[0]}"
    # do some error handling, cleanup, logging, notification
    # $BASH_COMMAND contains the command that was being executed at the time of the trap
    # ${BASH_LINENO[0]} contains the line number in the script of that command
    # exit the script or return to try again, etc.
    cleanup
    exit $errcode  # or use some other value or do return instead
}

# Catch the crtl-c and others nicely 
#trap cleanup EXIT SIGHUP SIGINT SIGTERM
#trap fail ERR
# 

# Wanted to output a nicer message while I debug things.
print(){
 echo "$1"
 echo "${line}"
}

# I needed this to get snapshots to work. Its not ideal to hardcode this
# but it is what it is right now.
components="main,contrib"

# Using an associative array 
declare -A MIRROR

MIRROR[testing-extra]="http://apt.mirantis.com/xenial testing extra"
MIRROR[testing-salt]="http://apt.mirantis.com/xenial testing salt"
MIRROR[testing-ocata]="http://apt.mirantis.com/xenial testing ocata"

MIRROR[stable-extra]="http://apt.mirantis.com/xenial stable extra"
MIRROR[stable-salt]="http://apt.mirantis.com/xenial stable salt"
MIRROR[stable-ocata]="http://apt.mirantis.com/xenial stable ocata"

MIRROR[xenial-main]="http://ppa.launchpad.net/gluster/glusterfs-3.8/ubuntu xenial main"

MIRROR[ocata-holdback-main]="http://mirror.fuel-infra.org/mcp-repos/ocata/xenial ocata-holdback main"
MIRROR[ocata-hotfix-main]="http://mirror.fuel-infra.org/mcp-repos/ocata/xenial ocata-hotfix main"
MIRROR[ocata-main]="http://mirror.fuel-infra.org/mcp-repos/ocata/xenial ocata main"
MIRROR[ocata-security-main]="http://mirror.fuel-infra.org/mcp-repos/ocata/xenial ocata-security main"
MIRROR[ocata-updates-main]="http://mirror.fuel-infra.org/mcp-repos/ocata/xenial ocata-updates main"

MIRROR[saltstack-xenial-main]="https://repo.saltstack.com/apt/ubuntu/16.04/amd64/2016.3 xenial main"
MIRROR[fastly-xenial-main]="https://sensu.global.ssl.fastly.net/apt xenial main"

# This will create the mirror the first time if its not already on the machine.
start_time(){
  date > ${tempdir}/start
  echo -n "Start:  "
  cat ${tempdir}/start
}

end_time(){
  # Timestamp for just to see how long it takes
  echo -n "Finish: "
  date > ${tempdir}/end
  cat ${tempdir}/end
}

create_mirror(){
  # Timestamp
  # Just wanting a list of mirrors before I started
  start_time
  aptly mirror list > ${tempdir}/mirror-list  
  
  for mirror in "${!MIRROR[@]}"; do 
    if ! aptly mirror show $mirror > /dev/null ; then 
      print "aptly mirror create $mirror ${MIRROR[$mirror]}"
      aptly mirror create $mirror ${MIRROR[$mirror]} 
    fi
  done
  end_time
}

# Updating the mirrors and creates a snapshot for the day. Then publishes the mirror. 
# The publishing off a new snapshot requires dropping the already published right now.
update_mirror(){
  start_time
  aptly mirror list -raw | xargs -n 1 aptly mirror update -max-tries=10
  end_time
}

create_snapshot(){
  start_time
  for mirror in "${!MIRROR[@]}"; do 
    if ! aptly snapshot show ${mirror}-$(date +%Y%m%d) > /dev/null ; then
      print "aptly snapshot create ${mirror}-$(date +%Y%m%d) from $mirror"
      aptly snapshot create ${mirror}-$(date +%Y%m%d) from mirror $mirror
    fi
  done
  end_time
}

publish(){
  start_time
  echo "Begin publish !!!!"
  for snapshot in $(aptly snapshot list -raw);do
      mirror=$( aptly snapshot show ${snapshot} |grep mirror |cut -d [ -f 2 |cut -d ] -f 1)
      arch=$(aptly mirror show ${mirror} |grep Architectures |head -1 |cut -d ' ' -f 2)
      component=$(aptly mirror show ${mirror} |grep Components |head -1 |cut -d ' ' -f 2)
      distribution=$(aptly mirror show ${mirror} |grep Distribution |head -1 |cut -d ' ' -f 2)
      aptly publish $1 -architectures='"${arch}"' -component="${component}" -distribution="${distribution}" ${snapshot} ${mirror}
      #aptly publish $1  -component=${component} -distribution=${distribution} ${snapshot}
    done
}
#publish(){
#  start_time
#  for mirror in "${!MIRROR[@]}"; do 
#    echo ${mirror}  | sed -e s/_.*$//g >> ${tempdir}/distribution
#  done
#  for distribution in $(cat ${tempdir}/distribution | sort -u) ; do  
#    snapshot_list=$(aptly snapshot list -raw | grep ${distribution}| grep -v updates | tr "\\n" " " )
#    snapshot_list_updates=$(aptly snapshot list -raw | grep ${distribution} | grep updates | tr "\\n" " " )

#    echo "------publish $snapshot_list"
#    echo "------ publish $snapshot_list_updates"
#    echo "------ publish distribution ${distribution}"
#    #print "aptly publish $1 -component="main,contrib" -distribution=${distribution} ${snapshot_list} atg"
#    aptly publish $1 -component="${components}" -distribution="${distribution}" ${snapshot_list} atg
#    #print "aptly publish $1 -component="main,contrib" -distribution=${distribution}-updates ${snapshot_list_updates} atg"
#    aptly publish $1 -component="${components}" -distribution="${distribution}"-updates ${snapshot_list_updates} atg
#  done
#  rm -f ${tempdir}/distribution
##  end_time
#}


# Do things here
create_mirror
update_mirror
create_snapshot
publish snapshot
#publish switch

aptly publish list

# Clean up the aptly db of dangling references and packages nolonger used in the repos or 
# snapshots
#aptly db cleanup
#aptly graph
#mv /tmp/aptly-graph* /aptly/public/aptly-graph.png

# vim: tabstop=2:softtabstop=2:shiftwidth=2:noexpandtab

#!/bin/bash
QUEUE=$1
DEFAULTQUEUE='service'
GEARMANHOST='172.20.129.117'
WS=40
PL=10
IV=50
DOWNTIME=180
LOGPRAEF='/var/log/gearman_monitor/gearman_monitor_wd'
CHECKCOM="-w 0 -c 0 -W 0 -C 0 -H $GEARMANHOST"
CHECKBIN='/var/data/nagios/libnew/check_gearman'
WAIT='_waiting'
RUN='_running'
WORK='_worker'
DEBUGMODE=1
CSTOP=3
CSTART=3
RP=10
SP=5
PENALTY=111

DEBUG () {
  if [ $DEBUGMODE -gt 0 ]; then
    printf "$1\n"
  fi
}
LOGGER () {
   MESSAGE="$1"
   printf "$MESSAGE\n" >> $LOGPRAEF-$LD.log
   DEBUG "$MESSAGE"
   MESSAGE=''
}


GMRST () {
  LOGGER "`date` gearman watchdog ERROR detected - Restartting daemons"
  MCRS=`service memcached restart`
  DEBUG "MCRS=$MCRS"
  sleep 2
  MCRSS=`service memcached status`
  LOGGER "$MCRSS"
  i=0
  while [ $i -lt $CSTOP ]; do
    GMSSP=`/etc/init.d/gearman-job-server stop`
    DEBUG "GMSSP=$GMSSP"
    i=$(($i+1))
    DEBUG "CSTOP=$CSTOP"
    sleep $RP
    GMSSPEC=`/etc/init.d/gearman-job-server status > /dev/null 2>&1; echo $?`
    DEBUG "GMSSPEC=$GMSSPEC"
    if [ $GMSSPEC -gt 0 ]; then
      i=$CSTOP
    fi
  done
  j=0
  while [ $j -lt $CSTART ]; do
    GMSST=`/etc/init.d/gearman-job-server start`
    DEBUG "GMSST=$GMSST"
    j=$(($j+1))
    DEBUG "CSTART=$CSTART"
    sleep $SP
    GMSSTEC=`/etc/init.d/gearman-job-server status > /dev/null 2>&1; echo $?`
    DEBUG "GMSSTEC=$GMSSTEC"
    if [ $GMSSTEC -eq 0 ]; then
      j=$CSTART
    fi
  done
  if [ $GMSSTEC -eq 0 ]; then
    GMSST=`service gearman-job-server status`
    LOGGER "$GMSST"
  else
    LOGGER "emergency reboot required"
    sleep 10 && nohup /sbin/reboot &
  fi
  NARS=`service nagios restart`
  DEBUG "NARS=$NARS"
  sleep 2
  NARSS=`service nagios status`
  LOGGER "$NARSS"
}
GMSTATE () {
#  ps aux | grep '/usr/sbin/gearmand --pid-file=/run/gearman/gearmand.pid --user=gearman --daemon --file-descriptors=49152 --log-file=/var/log/gearman-job-server/gearman.log --listen=0.0.0.0' | grep -v grep > /dev/null
#  ps aux | grep '/usr/local/sbin/gearmand -d --listen=172.20.129.117 --pid-file=/run/gearman/server.pid --log-file=/var/log/gearman-job-server/gearman.log --backlog=5000' | grep -v grep > /dev/null
  ps aux | grep '/usr/local/sbin/gearmand -d --listen=172.20.129.117 --pid-file=/run/gearman/server.pid --log-file=/var/log/gearman-job-server/gearman.log --backlog=5000 --verbose=INFO' | grep -v grep > /dev/null
  EGR=$?
}

if [ $# -eq 0 ]; then
  QUEUE=$DEFAULTQUEUE
fi
DEBUG "QUEUE=$QUEUE"

LD=`date -d "$DATUM" +"%Y-%m-%d"`
LOGGER "`date` gearman watchdog is starting ..."

while [ 1 ]; do
  LD=`date -d "$DATUM" +"%Y-%m-%d"`
  LOGGER "`date` gearman watchdog check loop is starting ..."
  GMSTATE
  DEBUG "gearmand status 1: EGR=$EGR"
  if [[ $EGR -eq 0 ]]; then
    LOGGER "`date` gearman watchdog check: gearman-job-server is running ..."
  else
    LOGGER "`date` gearman watchdog check: gearman-job-server was stopped, trying to start ..."
    GMRST
    GMSTATE
    DEBUG "gearmand status 2: EGR=$EGR"
    if [[ $EGR -eq 0 ]]; then
      LOGGER "`date` gearman watchdog check: gearman-job-server is running ..."
    else
      LOGGER "`date` gearman watchdog check: gearman-job-server seems still stopped. For now I give up ..."
    fi
  fi
  for ((i=1;i<3;i++)); do # trendbrechnung
    AW=0
    AR=0
    AO=0
    AC=0
    IT=0
    k=$(($i-1))
    while [[ $IT -lt $IV ]]; do # Durchschnitt
      IT=$(($IT+$PL))
      AC=$(($AC+1))
      DEBUG "IT=$IT"
      DEBUG "AC=$AC"
      DEBUG "IV=$IV"
      ND=`date`
      UD=`date -d "$DATUM" +%s`
      LD=`date -d "$DATUM" +"%Y-%m-%d"`
      RESULT=`$CHECKBIN $CHECKCOM -q $QUEUE`
      # RES_W
      RES_T=${RESULT#*\'$QUEUE$WAIT\'=}
      RES_W=${RES_T%%;*}
      if [[ $RES_W =~ ^[0-9]+$ ]]; then
        DEBUG "### RES_W=$RES_W ok ###"
      else
        DEBUG "### RES_W=$RES_W nok, i=$i ###"
        if [[ $i -eq 1 ]]; then
          RES_W=$PENALTY
        else
          RES_W=${W[$k]}
        fi
        DEBUG "### RES_W=$RES_W new ###"
      fi
      # RES_R
      RES_T=${RESULT#*\'$QUEUE$RUN\'=}
      RES_R=${RES_T%% *}
      if [[ $RES_R =~ ^[0-9]+$ ]]; then
        DEBUG "### RES_R=$RES_R ok ###"
      else
        DEBUG "### RES_R=$RES_R nok , i=$i ###"
        if [[ $i -eq 1 ]]; then
          RES_R=$PENALTY
        else
          RES_R=${R[$k]}
        fi
        DEBUG "### RES_R=$RES_R new ###"
      fi
      # RES_O
      RES_T=${RESULT#*\'$QUEUE$WORK\'=}
      RES_O=${RES_T%%;*}
      if [[ $RES_O =~ ^[0-9]+$ ]]; then
        DEBUG "### RES_O=$RES_O ok ###"
      else
        DEBUG "### RES_O=$RES_O nok, i=$i ###"
        if [[ $i -eq 1 ]]; then
          RES_O=$PENALTY
        else
          RES_O=${O[$k]}
        fi
        DEBUG "### RES_O=$RES_O new ###"
      fi
      LOGGER "$ND NAME=$QUEUE WAIT=$RES_W RUN=$RES_R WORKER=$RES_O"
      AW=$(($AW+$RES_W))
      AR=$(($AR+$RES_R))
      AO=$(($AO+$RES_O))
      sleep $PL
    done
    W[$i]=$(($AW/$AC))
    R[$i]=$(($AR/$AC))
    O[$i]=$(($AO/$AC))
    LD=`date -d "$DATUM" +"%Y-%m-%d"`
    LOGGER "$ND AV$i NAME=$QUEUE AWAIT=${W[$i]} ARUN=${R[$i]} AWORK=${O[$i]}"
  done
  DEBUG "Wait1: ${W[1]} max Wait: $WS"
  if [[ ${W[1]} -ge $WS ]]; then
    DEBUG "Wait1: ${W[1]} Wait2: ${W[2]}"
    if [[ ${W[2]} -ge $WS ]]; then
      LOGGER "gearman watchdog ERROR - Wait1: ${W[1]} Wait2: ${W[2]}"
      LD=`date -d "$DATUM" +"%Y-%m-%d"`
      GMRST
      DT=$DOWNTIME
      LOGGER "`date` gearman watchdog Hold Down Timer was started ( Timer==$DOWNTIME sec )"
    else
      DT=$PL
    fi
  else
    DT=$PL
  fi
  sleep $DT 
done


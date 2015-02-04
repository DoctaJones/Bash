#!/bin/bash
#
#This script depends on nova settings files in the home directory. I bet
#there is a better way to do that, but for the purposes of this script
#this works fine. You can either change the files names in here for your
#individual use or change the files in your home directory.
#Script steps:
# 1. Take in a cli flag that signifies which stack is broken
# 2. Source the nova settings for that stack
# 3. Search for that stack's ES nodes and outpt the IPs to a file
# 4. Loop through each IP in file
# 5. For each IP, ssh in to that node and:
#     a. df -h the /mnt directory
#     b. clean all old backups
#     c. list new disk usage
# 6. Disable allocation using last IP in list
# 7. Enable allocation using last IP in list
# 8. Check cluster health
# 9. Remove IP list file

die() {
  errCode=$1
  shift
  echo "$*" >&2
  exit $errCode
}

USAGE=$'
Usage: -u | -d | -q | -s | -p
  Where:
    -u    Unstable stack
    -d    Devint stack
    -q    QA stack
    -s    Staging stack
    -P    Production stack
'

if [ $# -ne 1 ]; then
  die 1 "$USAGE"
fi

touch stack_metaindex.tmp
node_list=stack_metaindex.tmp

if [ "$1" = "-u" ]; then
  source ~/novaini-qa135
  nova list | grep u135 | awk '/metaindex/{print $13}' > $node_list
elif [ "$1" = "-d" ]; then
  source ~/novaini-qa135
  nova list | grep dev135 | awk '/metaindex/{print $13}' > $node_list
elif [ "$1" = "-q" ]; then 
  source ~/novaini-qa135
  nova list | grep qa135 | awk '/metaindex/{print $13}' > $node_list
elif [ "$1" = "-s" ]; then
  source ~/novaini-stage135
  nova list | awk '/metaindex/{print $13}' > $node_list
elif [ "$1" = "-p" ]; then 
  source ~/novaini-prod135
  nova list | awk '/metaindex/{print $13}' > $node_list
else
  die 1 "$USAGE"
fi

for IP in $(cat $node_list); do
  echo $IP
  ssh $IP \
  'df -h /mnt;
   echo cleaning...
   sudo find /mnt/backups/backup_storage/* -mmin +1600 -exec rm {} \;
   df -h /mnt;
  ' 
  echo
done

echo "Disabling allocation on the cluster via $IP..."
curl -s -XPUT $IP:9200/_cluster/settings -d '{"transient" : {"cluster.routing.allocation.enable": "none"}}'
echo

echo "Enabling allocation on the cluster via $IP..."
curl -s -XPUT $IP:9200/_cluster/settings -d '{"transient" : {"cluster.routing.allocation.enable": "all"}}'
echo

echo
echo "Sleeping 5 seconds then checking cluster health..."
sleep 5
curl -s $IP:9200/_cluster/health?pretty

rm $node_list

#! /bin/sh

ARG1=$1
ARG2=$2

DAEMON=bmxd
DAEMON_PATH=/usr/bin
RUN_STATUS_FILE=/var/run/batman-status-running
DB_PATH=/var/lib/ddmesh/bmxd
STAT_DIR=/var/statistic

mkdir -p $DB_PATH
mkdir -p $STAT_DIR

touch $DB_PATH/links
touch $DB_PATH/gateways
touch $DB_PATH/originators
touch $DB_PATH/status
touch $DB_PATH/networks	# network ids
touch $STAT_DIR/gateway_usage


eval $(/usr/lib/ddmesh/ddmesh-ipcalc.sh -n $(uci get ddmesh.system.node))

ROUTING_CLASS="$(uci -q get ddmesh.bmxd.routing_class)"
ROUTING_CLASS="${ROUTING_CLASS:-3}"
ROUTING_CLASS="-r $ROUTING_CLASS --gateway_hysteresis 20"

GATEWAY_CLASS="$(uci -q get ddmesh.bmxd.gateway_class)"
GATEWAY_CLASS="${GATEWAY_CLASS:-512/512}"
GATEWAY_CLASS="-g $GATEWAY_CLASS"

MESH_NETWORK_ID="$(uci -q get ddmesh.network.mesh_network_id)"
MESH_NETWORK_ID="${MESH_NETWORK_ID:-0}"

PREFERRED_GATEWAY="$(uci -q get ddmesh.bmxd.preferred_gateway | sed -n '/^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$/p')"
test -n "$PREFERRED_GATEWAY" && PREFERRED_GATEWAY="-p $PREFERRED_GATEWAY"

# create a virtual interface for primary interface. loopback has
# 127er IP would be broadcasted

PRIMARY_IF="bmx_prime"
FASTD_IF="tbb_fastd"
LAN_IF="br-mesh_lan"
WAN_IF="br-mesh_wan"
if [ "$1" = "start" ]; then
#	ip tuntap add dev $PRIMARY_IF mod tun
	brctl addbr $PRIMARY_IF
	ip addr add $_ddmesh_ip/$_ddmesh_netpre broadcast $_ddmesh_broadcast dev $PRIMARY_IF
	ip link set dev $PRIMARY_IF up
fi
_IF="dev=$PRIMARY_IF /linklayer 0 dev=$FASTD_IF /linklayer 1 dev=$LAN_IF /linklayer 1 dev=$WAN_IF /linklayer 1"

#add wifi, if hotplug event did occur before starting bmxd
eval $(/usr/lib/ddmesh/ddmesh-utils-network-info.sh wifi)
if [ -n "$net_ifname" ]; then
	_IF="$_IF dev=$net_ifname /linklayer 2"
fi

#default start with no gatway.will be updated by gateway_check.sh
#SPECIAL_OPTS="--throw-rules 0 --prio-rules 0 --meshNetworkIdPreferred $MESH_NETWORK_ID"
SPECIAL_OPTS="--throw-rules 0 --prio-rules 0"
TUNNEL_OPTS="--gateway_tunnel_network $_ddmesh_network/$_ddmesh_netpre --one-way-tunnel 1"
TUNING_OPTS="--purge_timeout 20"
DAEMON_OPTS="$SPECIAL_OPTS $TUNNEL_OPTS $TUNING_OPTS $ROUTING_CLASS $PREFERRED_GATEWAY $_IF"


test -x $DAEMON_PATH/$DAEMON || exit 0

case "$ARG1" in
  start)
	echo "Starting $DAEMON: opt: $DAEMON_OPTS"
	# set initial wifi ssid to "FF no-inet"
	/usr/lib/bmxd/bmxd-gateway.sh init
	$DAEMON_PATH/$DAEMON $DAEMON_OPTS
	;;

  stop)
	echo "Stopping $DAEMON: "
	killall -9 $DAEMON
	;;

  restart|force-reload)
	$0 stop
	sleep 1
	$0 start
	;;

  nightly)
	logger -t bmx-nightly "bmxd restart bat0: $(ip addr show bat0 | grep 'inet')"
	$0 stop
	$0 start
	;;

  gateway)
	echo $DAEMON -c $GATEWAY_CLASS
	$DAEMON_PATH/$DAEMON -c $GATEWAY_CLASS
	;;

  no_gateway)
	echo $DAEMON -c $ROUTING_CLASS
	$DAEMON_PATH/$DAEMON -c $ROUTING_CLASS
	;;
  add_if)
	$DAEMON_PATH/$DAEMON -c dev=$ARG2 /linklayer 2
	;;
  del_if)
	$DAEMON_PATH/$DAEMON -c dev=-$ARG2
	;;
  check)
	test -z "$(pidof $DAEMON)" && logger -s "$DAEMON not running - restart" && $0 restart && exit
	test -n "$(pidof $DAEMON)" && test ! -f "$RUN_STATUS_FILE" && (
	touch $RUN_STATUS_FILE
	$DAEMON_PATH/$DAEMON -c --gateways > $DB_PATH/gateways
	$DAEMON_PATH/$DAEMON -c --links > $DB_PATH/links
	$DAEMON_PATH/$DAEMON -c --originators > $DB_PATH/originators
	$DAEMON_PATH/$DAEMON -c --status > $DB_PATH/status
#	$DAEMON_PATH/$DAEMON -c --networks > $DB_PATH/networks
	$DAEMON_PATH/$DAEMON -ci > $DB_PATH/info
	rm $RUN_STATUS_FILE
	)

	;;

  *)
	echo "Usage: $0 {start|stop|restart|gateway|no_gateway|check|add_if|del_if}" >&2
	exit 1         ;;


esac

exit 0

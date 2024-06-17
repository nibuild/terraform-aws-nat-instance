#!/bin/bash -x

# Make sure we know which interface is the new wan
# shellcheck disable=SC2154
EIPMAC="${eip_macaddress}"

# Change mac address to ethernet device
FINDEIP=$(grep -r "$EIPMAC" /sys/class/net/*/address)
if [ $? -gt 0 ] ; then
  echo "No interface loaded matching mac of $EIPMAC"
  echo "Rebooting to try again"
  logger "No interface found matching $EIPMAC, rebooting in 60 seconds"
  sleep 60
  reboot
fi

EIPDEV=$(echo "$FINDEIP" | cut -d/ -f5)
echo "Output eth is $EIPDEV"

# Get any route that is not our new interface
GWS=$(ip ro | grep default | grep -v "$EIPDEV" | cut -d' ' -f5)
INTS=$(ip link show | grep -E '^[0-9]*: ' | grep -Ev "docker|lo" | cut -d' ' -f2 | sed -e 's/:$//g')

# Configure iptables to forward packets - only run on first boot
if [ ! -f /.configured ]; then
  #  make this a nat instance
  echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
  sysctl -p
  # Setup masquerade on the EIP device
  iptables -t nat -A POSTROUTING -o "$EIPDEV" -j MASQUERADE
  # Allow forwarding traffic from all interfaces
  for CINT in $INTS; do
    iptables -A FORWARD -i "$CINT" -o "$EIPDEV" -j ACCEPT
    iptables -A FORWARD -i "$CINT" -o "$EIPDEV" -m state --state RELATED,ESTABLISHED -j ACCEPT
  done
  # Disable everything else
  iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited
  service iptables save

  # ensure these settings persist across reboots
  echo "@reboot root iptables-restore < /etc/sysconfig/iptables" | tee -a /etc/crontab
  # Touch our file so we don't duplicate all the rules
  touch /.configured
fi

EXTWORKING=0
EXTTRYS=0
while [ $EXTWORKING -eq 0 ]; do
  # switch the default route to new gateway
  for CGW in $GWS; do
    echo "Removing default route through $CGW"
    if ! /usr/sbin/ip ro del default dev "$CGW"; then
      echo "Failed removing default gw through $CGW"
    fi
  done
  # Check for internet is working
  if curl --retry 2 https://google.com; then
    EXTWORKING=1
    echo "Internet online"
  else
    EXTTRYS=$((EXTTRYS + 1))
  fi

  if [ $EXTTRYS -ge 5 ]; then
    echo "Failed to bring network up, rebooting."
    reboot
  fi
done

# re-establish connections
systemctl restart amazon-ssm-agent

# Run any defined startup scripts
if [ -d /opt/nat/startup.d ]; then
  # If cd'ing to the directy fails just exit cleanly
  cd /opt/nat/startup.d || exit 0
  for CSCRIPT in *.sh; do
    bash "$CSCRIPT"
  done
fi

# Exit cleanly
exit 0

#!/bin/bash -x

# Make sure we know which interface is the new wan
EIPMAC="${eip_macaddress}"
# Change mac address to ethernet device
FINDEIP=$(grep -r $EIPMAC /sys/class/net/*/address)

if [ $? -gt 0 ]; then
  echo "No interface loaded matching mac of $EIPMAC"
  echo "Rebooting to try again"
  reboot
fi
EIPDEV=$(echo $FINDEIP | cut -d/ -f5)
echo "Output eth is $EIPDEV"

#  make this a nat instance
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Get any route that is not our new interface
GWS=$(ip ro | grep default | grep -v $EIPDEV | cut -d' ' -f5)

# Configure iptables to forward packets - only run on first boot
if [ ! -f /.configured ]; then
  sudo iptables -t nat -A POSTROUTING -o $EIPDEV -j MASQUERADE
  for CGW in $GWS; do
    sudo iptables -A FORWARD -i $CGW -o $EIPDEV -j ACCEPT
    sudo iptables -A FORWARD -i $CGW -o $EIPDEV -m state --state RELATED,ESTABLISHED -j ACCEPT
  done
  sudo iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited
  sudo service iptables save
  
  # ensure these settings persist across reboots
  echo "@reboot root iptables-restore < /etc/sysconfig/iptables" | sudo tee -a /etc/crontab
  # Touch our file so we don't duplicate all the rules
  touch /.configured
fi

# switch the default route to new gateway
for CGW in $GWS; do
ip route del default dev $CGW
done

# Check for internet
curl --retry 10 https://google.com

# re-establish connections
systemctl restart amazon-ssm-agent

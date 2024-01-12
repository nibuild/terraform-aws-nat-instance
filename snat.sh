#!/bin/bash -x

# wait for ens6
while ! ip link show dev ens6; do
  sleep 1
done

#  make this a nat instance
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Configure iptables to forward packets
sudo iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
sudo iptables -A FORWARD -i ens6 -o ens5 -j ACCEPT
sudo iptables -A FORWARD -i ens5 -o ens6 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited
sudo service iptables save

# ensure these settings persist across reboots
echo "@reboot root iptables-restore < /etc/sysconfig/iptables" | sudo tee -a /etc/crontab

# wait for network connection
curl --retry 10 https://google.com

# re-establish connections
systemctl restart amazon-ssm-agent

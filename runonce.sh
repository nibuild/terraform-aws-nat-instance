#!/bin/bash -x

# Disable Source/Destination Check for the instance default interface
aws ec2 modify-instance-attribute --instance-id "$(/usr/bin/ec2-metadata -i | cut -d' ' -f2)" --no-source-dest-check

# try to attach the ENI
max_attempts=10
attempt=0

while true; do
    aws ec2 attach-network-interface \
        --region "$(/usr/bin/ec2-metadata -z | sed 's/placement: \(.*\).$/\1/')" \
        --instance-id "$(/usr/bin/ec2-metadata -i | cut -d' ' -f2)" \
        --device-index 1 \
        --network-interface-id "${eni_id}" && break

    attempt=$((attempt + 1))

    if [ "$attempt" -ge "$max_attempts" ]; then
        echo "Maximum attempts reached. Initiating reboot."
        sudo reboot
        break
    fi

    echo "Attempt $attempt failed. Retrying..."
    sleep 5 # waits for 5 seconds before retrying
done

# Install IP tables its not available by default on Amazon Linux 2023 anymore
sudo yum install -y iptables-services
sudo systemctl enable iptables
sudo systemctl start iptables

# start SNAT
systemctl enable snat
systemctl start snat
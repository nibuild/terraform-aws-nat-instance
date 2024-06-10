#!/bin/bash -x

# Get some needed informaiton
AWS_REGION=$(/usr/bin/ec2-metadata -z | sed 's/placement: \(.*\).$/\1/')
INSTANCE_ID=$(/usr/bin/ec2-metadata -i | cut -d' ' -f2)
# Disable Source/Destination Check for the instance default interface
aws ec2 modify-instance-attribute --region "$AWS_REGION" --instance-id "$INSTANCE_ID" --no-source-dest-check

# try to attach the ENI
max_attempts=10
attempt=0

while true; do
  # shellcheck disable=SC2154
  aws ec2 attach-network-interface \
    --region "$AWS_REGION" \
    --instance-id "$INSTANCE_ID" \
    --device-index 1 \
    --network-interface-id "${eni_id}" && break

  attempt=$((attempt + 1))

  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "Maximum attempts reached. Initiating reboot."
    # ensure this runs after reboot
    echo "@reboot root /opt/nat/runonce.sh" | tee -a /etc/crontab
    # reboot to try again
    reboot
    break
  fi

  echo "Attempt $attempt / $max_attempts failed. Retrying..."
  sleep 5 # waits for 5 seconds before retrying
done

# Install IP tables its not available by default on Amazon Linux 2023 anymore
yum install -y iptables-services
systemctl enable --now iptables

# start SNAT
systemctl enable --now --no-block snat

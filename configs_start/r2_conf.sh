mkdir /run/bird
rm /etc/bird/bird.conf
ip addr add 203.0.113.5/30 dev eth0
ip addr add 203.0.113.34/30 dev eth1

mkdir /run/bird
rm /etc/bird/bird.conf
ip addr add 203.0.113.1/30 dev eth0
ip addr add 203.0.113.33/30 dev eth1
ip addr add 192.0.2.2/30 dev eth2
